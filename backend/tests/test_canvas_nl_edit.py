"""Real integration tests for the canvas NL-edit endpoint
(POST /api/v1/trips/{trip_id}/nl) — the backend half of the canvas NL
textbox flow (frontend Slice 2).

Runs the actual FastAPI app in-process against real MongoDB (backend/.env
points at localhost, reachable from the test process once
`docker-compose up -d` is running) and a real Mapbox geocode call for
pin_stop. The only thing mocked is the Anthropic client inside
nl_parser.py — its parsing contract already has focused unit tests in
test_nl_parser.py; this file exists to cover what those don't: the
endpoint's Trip lookup/ownership check, the real Mapbox geocode round
trip, and that pins actually persist to MongoDB.

Trips are created/read/deleted through the real HTTP endpoints (not
direct Beanie calls) — Beanie's Motor client binds to whichever event
loop was running when TestClient's startup event initialized it, and a
direct `await Trip.insert()` from the test body runs on pytest-asyncio's
own loop, which raises "Future attached to a different loop". Routing
everything through the same TestClient sidesteps that entirely.
"""

import os
import time
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import jwt
from fastapi.testclient import TestClient

from app.main import app

USER_A_ID = "00000000-0000-0000-0000-000000000042"
USER_B_ID = "00000000-0000-0000-0000-000000000099"


def _make_test_jwt(sub: str) -> str:
    secret = os.getenv("SUPABASE_JWT_SECRET")
    assert secret, "SUPABASE_JWT_SECRET must be set in backend/.env for this test"
    now = int(time.time())
    payload = {
        "sub": sub,
        "email": f"{sub}@example.com",
        "role": "authenticated",
        "aud": "authenticated",
        "iat": now,
        "exp": now + 3600,
    }
    return jwt.encode(payload, secret, algorithm="HS256")


def _fake_llm_response(text: str) -> MagicMock:
    client = MagicMock()
    client.messages.create.return_value = SimpleNamespace(
        content=[SimpleNamespace(type="text", text=text)]
    )
    return client


def _auth_header(sub: str) -> dict:
    return {"Authorization": f"Bearer {_make_test_jwt(sub)}"}


def _create_trip(client: TestClient, sub: str, pins: list | None = None) -> str:
    response = client.post(
        "/api/v1/trips",
        json={
            "name": "Test Trip",
            "origin_name": "San Francisco, CA",
            "origin_lat": 37.7749,
            "origin_lng": -122.4194,
            "destination_name": "Los Angeles, CA",
            "destination_lat": 34.0522,
            "destination_lng": -118.2437,
            "pins": pins or [],
        },
        headers=_auth_header(sub),
    )
    assert response.status_code == 200, response.text
    return response.json()["id"]


def _delete_trip(client: TestClient, sub: str, trip_id: str) -> None:
    client.delete(f"/api/v1/trips/{trip_id}", headers=_auth_header(sub))


class TestCanvasNLEdit:
    def test_pin_stop_geocodes_and_persists_a_real_pin(self):
        with TestClient(app) as client:
            trip_id = _create_trip(client, USER_A_ID)
            try:
                llm_json = (
                    '{"type": "pin_stop", "name": "Fisherman\'s Wharf stop", '
                    '"location": "Fisherman\'s Wharf, San Francisco, CA"}'
                )
                with patch("app.services.nl_parser._CLIENT", _fake_llm_response(llm_json)):
                    response = client.post(
                        f"/api/v1/trips/{trip_id}/nl",
                        json={"text": "add a stop at Fisherman's Wharf"},
                        headers=_auth_header(USER_A_ID),
                    )

                assert response.status_code == 200
                data = response.json()
                assert len(data["pins"]) == 1
                pin = data["pins"][0]
                assert pin["type"] == "suggested"
                assert pin["name"] == "Fisherman's Wharf stop"
                # Real Mapbox geocode result — Fisherman's Wharf is
                # unambiguously in SF, nowhere near (0, 0).
                assert 37.7 < pin["lat"] < 37.9
                assert -122.6 < pin["lng"] < -122.3

                # Persisted, not just echoed back in the response.
                reloaded = client.get(
                    f"/api/v1/trips/{trip_id}", headers=_auth_header(USER_A_ID)
                ).json()
                assert len(reloaded["pins"]) == 1
                assert reloaded["pins"][0]["name"] == "Fisherman's Wharf stop"
            finally:
                _delete_trip(client, USER_A_ID, trip_id)

    def test_remove_stop_matches_by_name_and_persists(self):
        with TestClient(app) as client:
            trip_id = _create_trip(
                client,
                USER_A_ID,
                pins=[
                    {
                        "type": "suggested",
                        "id": "abc-123",
                        "name": "Fisherman's Wharf stop",
                        "lat": 37.808,
                        "lng": -122.4177,
                    }
                ],
            )
            try:
                llm_json = (
                    '{"type": "remove_stop", "name_pattern": "Fisherman\'s Wharf"}'
                )
                with patch("app.services.nl_parser._CLIENT", _fake_llm_response(llm_json)):
                    response = client.post(
                        f"/api/v1/trips/{trip_id}/nl",
                        json={"text": "remove the fisherman's wharf stop"},
                        headers=_auth_header(USER_A_ID),
                    )

                assert response.status_code == 200
                data = response.json()
                assert data["pins"] == []
                assert "Removed 1 stop" in data["message"]

                reloaded = client.get(
                    f"/api/v1/trips/{trip_id}", headers=_auth_header(USER_A_ID)
                ).json()
                assert reloaded["pins"] == []
            finally:
                _delete_trip(client, USER_A_ID, trip_id)

    def test_rejects_trip_owned_by_a_different_user(self):
        with TestClient(app) as client:
            trip_id = _create_trip(client, USER_B_ID)
            try:
                response = client.post(
                    f"/api/v1/trips/{trip_id}/nl",
                    json={"text": "add a stop anywhere"},
                    headers=_auth_header(USER_A_ID),
                )
                assert response.status_code == 404
            finally:
                _delete_trip(client, USER_B_ID, trip_id)

    def test_unparseable_instruction_leaves_pins_unchanged(self):
        with TestClient(app) as client:
            trip_id = _create_trip(client, USER_A_ID)
            try:
                llm_json = '{"type": "unknown", "message": "Not sure what you mean."}'
                with patch("app.services.nl_parser._CLIENT", _fake_llm_response(llm_json)):
                    response = client.post(
                        f"/api/v1/trips/{trip_id}/nl",
                        json={"text": "asdkjhaskjdh"},
                        headers=_auth_header(USER_A_ID),
                    )

                assert response.status_code == 200
                data = response.json()
                assert data["pins"] == []
                assert data["message"] == "Not sure what you mean."
            finally:
                _delete_trip(client, USER_A_ID, trip_id)

