"""Real integration tests for the monologue authoring pipeline
(app.services.monologue_pipeline.generate_monologue) — converts the
manual backend/scripts/verify_slice_a.py script into an automated
pytest test.

Runs against real MongoDB and makes real Mapbox Directions/reverse-geocode
calls (backend/.env points at localhost, reachable once
`docker-compose up -d` is running). The Anthropic authoring calls are
mocked (same technique as test_nl_parser.py / test_canvas_nl_edit.py) —
authored prose is LLM-variable and would make assertions flaky; this
file exists to cover what a mocked LLM can't: the real polyline fetch,
real town extraction, and the (polyline_hash, vibe_hash) MongoDB caching
behavior (miss -> author -> insert -> hit).

TTS synthesis (Slice B) is skipped here by unsetting OPENAI_API_KEY for
the test — it already has its own mocked-client tests in
test_openai_tts.py, and skipping avoids real per-utterance synthesis
cost/latency on every test run. Stop verification (Slice C) is
sidestepped by having the fake author return an empty "stops" list,
avoiding a real Mapbox Search Box / OSM Overpass dependency.
"""

import os
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from motor.motor_asyncio import AsyncIOMotorClient
from beanie import init_beanie

from app.database import RouteMonologue, MONGODB_URL, MONGODB_DATABASE
from app.services.mapbox_directions import fetch_polyline
from app.services.monologue_pipeline import (
    generate_monologue,
    polyline_hash,
    vibe_hash,
)

SF = (37.7749, -122.4194)
SACRAMENTO = (38.5816, -121.4944)
ROUTE_LABEL = "San Francisco, CA -> Sacramento, CA"


async def _init_db() -> None:
    client = AsyncIOMotorClient(MONGODB_URL)
    await init_beanie(database=client[MONGODB_DATABASE], document_models=[RouteMonologue])


def _fake_llm_client(characterization_text: str, monologue_json: str) -> MagicMock:
    """A fake AsyncAnthropic client whose messages.create() returns the
    characterization text on its first call and the monologue+stops JSON
    on its second — matching generate_monologue's two-stage authoring
    (_characterize_route then _author_monologue_and_stops)."""
    client = MagicMock()
    client.messages.create = AsyncMock(
        side_effect=[
            SimpleNamespace(content=[SimpleNamespace(type="text", text=characterization_text)]),
            SimpleNamespace(content=[SimpleNamespace(type="text", text=monologue_json)]),
        ]
    )
    return client


@pytest.mark.asyncio
class TestMonologuePipeline:
    async def test_generate_monologue_caches_across_calls(self, monkeypatch):
        monkeypatch.delenv("OPENAI_API_KEY", raising=False)
        await _init_db()

        polyline = await fetch_polyline(SF[0], SF[1], SACRAMENTO[0], SACRAMENTO[1])
        assert polyline, (
            "Real Mapbox Directions call should return a polyline — check "
            "MAPBOX_ACCESS_TOKEN in backend/.env"
        )

        p_hash = polyline_hash(polyline)
        v_hash = vibe_hash(["history"], [])
        await RouteMonologue.find(
            RouteMonologue.polyline_hash == p_hash,
            RouteMonologue.vibe_hash == v_hash,
        ).delete()

        try:
            fake_client = _fake_llm_client(
                "This route winds through the Central Valley, tracing the "
                "path Gold Rush traffic once took inland from the bay.",
                '{"monologue": [{"i": 1, "anchor": "Sacramento", '
                '"utterance": "Test utterance about the drive."}], '
                '"stops": []}',
            )
            with patch(
                "app.services.monologue_pipeline.AsyncAnthropic",
                return_value=fake_client,
            ):
                doc1 = await generate_monologue(
                    polyline=polyline,
                    route_label=ROUTE_LABEL,
                    narration_themes=["history"],
                    stop_interests=[],
                )

            assert doc1 is not None
            assert doc1.polyline_hash == p_hash
            assert doc1.vibe_hash == v_hash
            assert len(doc1.towns) >= 1, (
                "Real town extraction along SF->Sacramento should find at "
                "least one town"
            )
            assert doc1.characterization.startswith("This route winds")
            assert len(doc1.utterances) == 1
            assert doc1.utterances[0]["utterance"] == "Test utterance about the drive."
            # TTS was skipped (no OPENAI_API_KEY) — should still set the
            # key rather than omit it, so the response shape is stable.
            assert doc1.utterances[0]["audio_url"] is None
            assert doc1.stops == []
            assert fake_client.messages.create.await_count == 2

            # Second call with the same (polyline, vibe): should hit the
            # cache and not call the LLM again at all.
            with patch(
                "app.services.monologue_pipeline.AsyncAnthropic",
                return_value=fake_client,
            ):
                doc2 = await generate_monologue(
                    polyline=polyline,
                    route_label=ROUTE_LABEL,
                    narration_themes=["history"],
                    stop_interests=[],
                )
            assert doc2 is not None
            assert doc2.id == doc1.id
            assert fake_client.messages.create.await_count == 2  # unchanged
        finally:
            await RouteMonologue.find(
                RouteMonologue.polyline_hash == p_hash,
                RouteMonologue.vibe_hash == v_hash,
            ).delete()

    async def test_different_vibe_on_same_route_authors_separately(self, monkeypatch):
        monkeypatch.delenv("OPENAI_API_KEY", raising=False)
        await _init_db()

        polyline = await fetch_polyline(SF[0], SF[1], SACRAMENTO[0], SACRAMENTO[1])
        assert polyline

        p_hash = polyline_hash(polyline)
        v_hash_a = vibe_hash(["history"], [])
        v_hash_b = vibe_hash(["food_culture"], [])
        await RouteMonologue.find(
            RouteMonologue.polyline_hash == p_hash,
            RouteMonologue.vibe_hash == v_hash_a,
        ).delete()
        await RouteMonologue.find(
            RouteMonologue.polyline_hash == p_hash,
            RouteMonologue.vibe_hash == v_hash_b,
        ).delete()

        try:
            # Two full authoring cycles (characterize + author, each) —
            # one per vibe, since each is a fresh cache miss.
            fake_client = MagicMock()
            fake_client.messages.create = AsyncMock(
                side_effect=[
                    SimpleNamespace(content=[SimpleNamespace(type="text", text="Characterization text A.")]),
                    SimpleNamespace(content=[SimpleNamespace(
                        type="text",
                        text='{"monologue": [{"i": 1, "anchor": "X", "utterance": "u-a"}], "stops": []}',
                    )]),
                    SimpleNamespace(content=[SimpleNamespace(type="text", text="Characterization text B.")]),
                    SimpleNamespace(content=[SimpleNamespace(
                        type="text",
                        text='{"monologue": [{"i": 1, "anchor": "X", "utterance": "u-b"}], "stops": []}',
                    )]),
                ]
            )
            with patch(
                "app.services.monologue_pipeline.AsyncAnthropic",
                return_value=fake_client,
            ):
                doc_a = await generate_monologue(
                    polyline=polyline,
                    route_label=ROUTE_LABEL,
                    narration_themes=["history"],
                    stop_interests=[],
                )
                doc_b = await generate_monologue(
                    polyline=polyline,
                    route_label=ROUTE_LABEL,
                    narration_themes=["food_culture"],
                    stop_interests=[],
                )

            assert doc_a is not None and doc_b is not None
            assert doc_a.id != doc_b.id
            assert doc_a.vibe_hash != doc_b.vibe_hash
            # Two distinct vibes on the same route both hit the LLM —
            # a different vibe_hash should never be served from the
            # other's cache entry.
            assert fake_client.messages.create.await_count == 4
        finally:
            await RouteMonologue.find(
                RouteMonologue.polyline_hash == p_hash,
                RouteMonologue.vibe_hash == v_hash_a,
            ).delete()
            await RouteMonologue.find(
                RouteMonologue.polyline_hash == p_hash,
                RouteMonologue.vibe_hash == v_hash_b,
            ).delete()
