"""Real integration tests for the trip-preview pipeline
(app.services.route_preview) — modeled on test_monologue_pipeline.py.

Runs against real MongoDB and makes real Mapbox Directions/reverse-geocode
calls. The Anthropic authoring call is mocked (same technique as
test_monologue_pipeline.py) — authored prose is LLM-variable and would
make assertions flaky; this file covers what a mocked LLM can't: the
real polyline fetch, real town extraction, the polyline_hash caching/
locking behavior, and the town-name anchoring guard.
"""

import asyncio
from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from motor.motor_asyncio import AsyncIOMotorClient
from beanie import init_beanie

from app.database import MONGODB_URL, MONGODB_DATABASE, RouteMonologue, RoutePreview
from app.services.mapbox_directions import fetch_route
from app.services.monologue_pipeline import polyline_hash
from app.services.route_preview import (
    _anchor_hotspots,
    get_preview,
    start_preview,
)
from app.services.town_extractor import Town, extract_towns

SF = (37.7749, -122.4194)
SACRAMENTO = (38.5816, -121.4944)
ORIGIN_NAME = "San Francisco, CA"
DEST_NAME = "Sacramento, CA"
ROUTE_LABEL = f"{ORIGIN_NAME} -> {DEST_NAME}"


async def _init_db() -> None:
    client = AsyncIOMotorClient(MONGODB_URL)
    # RouteMonologue is included because _generate opportunistically reads
    # RouteMonologue.characterization for the same polyline_hash as free
    # grounding — its class-level query attributes only exist once Beanie
    # has initialized that model in this process.
    await init_beanie(
        database=client[MONGODB_DATABASE],
        document_models=[RoutePreview, RouteMonologue],
    )


def _fake_llm_client(response_json: str) -> MagicMock:
    """A fake AsyncAnthropic client returning one authoring response —
    route_preview's pipeline is a single LLM call, unlike the
    monologue's two-stage characterize+author."""
    client = MagicMock()
    client.messages.create = AsyncMock(
        return_value=SimpleNamespace(content=[SimpleNamespace(type="text", text=response_json)])
    )
    return client


async def _wait_ready(p_hash: str, timeout: float = 5.0) -> RoutePreview:
    """Poll get_preview until generation leaves 'pending', matching how
    a real client would wait. Generation runs as a background
    asyncio task kicked off by start_preview, so tests need to yield
    control for it to actually execute."""
    deadline = asyncio.get_event_loop().time() + timeout
    while True:
        doc = await get_preview(p_hash)
        if doc is not None and doc.status != "pending":
            return doc
        if asyncio.get_event_loop().time() > deadline:
            raise AssertionError(f"preview for {p_hash[:8]} never left pending")
        await asyncio.sleep(0.05)


@pytest.mark.asyncio
class TestRoutePreview:
    async def test_start_preview_generates_and_caches(self):
        await _init_db()

        route = await fetch_route(SF[0], SF[1], SACRAMENTO[0], SACRAMENTO[1])
        assert route, "Real Mapbox Directions call should return a route"
        p_hash = polyline_hash(route.polyline)
        await RoutePreview.find(RoutePreview.polyline_hash == p_hash).delete()

        towns = await extract_towns(route.polyline)
        assert towns, "Real town extraction along SF->Sacramento should find towns"
        anchor_town = towns[-1].name

        fake_response = (
            '{"rundown": "A short valley drive.", "hotspots": '
            '[{"title": "Old Rail Depot", "town": "%s", "theme": "history", '
            '"blurb": "A well-preserved depot from the Gold Rush era, '
            'still standing beside the tracks it once served.", '
            '"detour_hint": "right off the highway"}]}' % anchor_town
        )

        try:
            with patch(
                "app.services.route_preview.AsyncAnthropic",
                return_value=_fake_llm_client(fake_response),
            ):
                started = await start_preview(
                    SF[0], SF[1], SACRAMENTO[0], SACRAMENTO[1], route_label=ROUTE_LABEL,
                )
                assert started is not None
                assert started.polyline_hash == p_hash
                assert started.status == "pending"
                assert started.distance_miles > 0
                assert started.duration_minutes > 0

                ready = await _wait_ready(p_hash)

            assert ready.status == "ready"
            assert ready.stage == "done"
            assert ready.rundown == "A short valley drive."
            assert len(ready.hotspots) == 1
            assert ready.hotspots[0]["town"] == anchor_town
            assert ready.hotspots[0]["theme"] in {
                "history", "landscape", "food_culture", "quirky",
            }
        finally:
            await RoutePreview.find(RoutePreview.polyline_hash == p_hash).delete()

    async def test_cache_hit_does_not_call_llm_again(self):
        await _init_db()

        route = await fetch_route(SF[0], SF[1], SACRAMENTO[0], SACRAMENTO[1])
        assert route
        p_hash = polyline_hash(route.polyline)
        await RoutePreview.find(RoutePreview.polyline_hash == p_hash).delete()

        towns = await extract_towns(route.polyline)
        anchor_town = towns[-1].name
        fake_response = (
            '{"rundown": "Rundown.", "hotspots": '
            '[{"title": "Thing", "town": "%s", "theme": "quirky", '
            '"blurb": "A specific, genuinely odd roadside detail worth '
            'a look if you have five minutes to spare.", '
            '"detour_hint": null}]}' % anchor_town
        )
        fake_client = _fake_llm_client(fake_response)

        try:
            with patch(
                "app.services.route_preview.AsyncAnthropic",
                return_value=fake_client,
            ):
                await start_preview(
                    SF[0], SF[1], SACRAMENTO[0], SACRAMENTO[1], route_label=ROUTE_LABEL,
                )
                await _wait_ready(p_hash)

                second = await start_preview(
                    SF[0], SF[1], SACRAMENTO[0], SACRAMENTO[1], route_label=ROUTE_LABEL,
                )
            assert second.status == "ready"
            assert fake_client.messages.create.await_count == 1
        finally:
            await RoutePreview.find(RoutePreview.polyline_hash == p_hash).delete()

    async def test_concurrent_start_preview_calls_llm_once(self):
        await _init_db()

        route = await fetch_route(SF[0], SF[1], SACRAMENTO[0], SACRAMENTO[1])
        assert route
        p_hash = polyline_hash(route.polyline)
        await RoutePreview.find(RoutePreview.polyline_hash == p_hash).delete()

        towns = await extract_towns(route.polyline)
        anchor_town = towns[-1].name
        fake_response = (
            '{"rundown": "Rundown.", "hotspots": '
            '[{"title": "Thing", "town": "%s", "theme": "landscape", '
            '"blurb": "A view worth slowing down for, especially in the '
            'late afternoon when the light comes in low.", '
            '"detour_hint": null}]}' % anchor_town
        )
        fake_client = _fake_llm_client(fake_response)

        try:
            with patch(
                "app.services.route_preview.AsyncAnthropic",
                return_value=fake_client,
            ):
                results = await asyncio.gather(
                    start_preview(SF[0], SF[1], SACRAMENTO[0], SACRAMENTO[1], route_label=ROUTE_LABEL),
                    start_preview(SF[0], SF[1], SACRAMENTO[0], SACRAMENTO[1], route_label=ROUTE_LABEL),
                )
                assert all(r is not None for r in results)
                await _wait_ready(p_hash)

            assert fake_client.messages.create.await_count == 1
        finally:
            await RoutePreview.find(RoutePreview.polyline_hash == p_hash).delete()

    async def test_stale_pending_doc_is_retaken(self):
        await _init_db()

        route = await fetch_route(SF[0], SF[1], SACRAMENTO[0], SACRAMENTO[1])
        assert route
        p_hash = polyline_hash(route.polyline)
        await RoutePreview.find(RoutePreview.polyline_hash == p_hash).delete()

        stale = RoutePreview(
            polyline_hash=p_hash,
            polyline=route.polyline,
            route_label=ROUTE_LABEL,
            status="pending",
            stage="routing",
            distance_miles=route.distance_miles,
            duration_minutes=route.duration_minutes,
            created_at=datetime.utcnow() - timedelta(seconds=300),
            updated_at=datetime.utcnow() - timedelta(seconds=300),
        )
        await stale.insert()

        towns = await extract_towns(route.polyline)
        anchor_town = towns[-1].name
        fake_response = (
            '{"rundown": "Rundown.", "hotspots": '
            '[{"title": "Thing", "town": "%s", "theme": "food_culture", '
            '"blurb": "A tiny diner that has been serving the same pie '
            'recipe since the highway first came through town.", '
            '"detour_hint": "a 5-minute detour"}]}' % anchor_town
        )

        try:
            with patch(
                "app.services.route_preview.AsyncAnthropic",
                return_value=_fake_llm_client(fake_response),
            ):
                await start_preview(
                    SF[0], SF[1], SACRAMENTO[0], SACRAMENTO[1], route_label=ROUTE_LABEL,
                )
                ready = await _wait_ready(p_hash)
            assert ready.status == "ready"
        finally:
            await RoutePreview.find(RoutePreview.polyline_hash == p_hash).delete()


class TestAnchorHotspots:
    def test_drops_hotspots_whose_town_is_not_on_route(self):
        towns = [Town(name="Vacaville", lat=38.36, lng=-121.99)]
        raw = [
            {"title": "Real thing", "town": "Vacaville", "theme": "history",
             "blurb": "A real detail about a real place, long enough to pass."},
            {"title": "Made up thing", "town": "Neverville", "theme": "quirky",
             "blurb": "This town does not exist on the route at all."},
        ]
        out = _anchor_hotspots(raw, towns)
        assert len(out) == 1
        assert out[0]["title"] == "Real thing"
        assert out[0]["lat"] == 38.36
        assert out[0]["lng"] == -121.99

    def test_town_match_is_case_insensitive(self):
        towns = [Town(name="Davis", lat=38.55, lng=-121.74)]
        raw = [{"title": "Thing", "town": "DAVIS", "theme": "landscape",
                "blurb": "A real detail about a real place, long enough to pass."}]
        out = _anchor_hotspots(raw, towns)
        assert len(out) == 1
        assert out[0]["town"] == "Davis"

    def test_invalid_theme_falls_back_to_quirky(self):
        towns = [Town(name="Davis", lat=38.55, lng=-121.74)]
        raw = [{"title": "Thing", "town": "Davis", "theme": "not-a-real-theme",
                "blurb": "A real detail about a real place, long enough to pass."}]
        out = _anchor_hotspots(raw, towns)
        assert out[0]["theme"] == "quirky"

    def test_drops_hotspots_missing_title_or_blurb(self):
        towns = [Town(name="Davis", lat=38.55, lng=-121.74)]
        raw = [
            {"title": "", "town": "Davis", "theme": "history", "blurb": "Has a blurb."},
            {"title": "Has a title", "town": "Davis", "theme": "history", "blurb": ""},
        ]
        assert _anchor_hotspots(raw, towns) == []
