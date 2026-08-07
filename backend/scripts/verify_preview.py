#!/usr/bin/env python3
"""Verify the trip-preview pipeline end-to-end, with real Anthropic calls.

This is what actually tells us whether the prompt is good — the unit/
integration tests in tests/test_route_preview.py mock the LLM entirely,
so they can't catch "technically valid JSON, but the rundown reads like
a brochure" or "hotspots feel padded on a short route."

Two scenarios on purpose:
  1. A long, scenic route (SF -> Tahoe) — the easy case, plenty of
     towns and obvious material.
  2. A short, mundane local drive (Columbia, MO -> Jefferson City, MO,
     ~35 min) — the actual product risk. This is the "drive to the
     in-laws" case: few towns, nothing famous, and the prompt has to
     find something honest to say instead of padding.

Run inside the container:
    docker compose exec backend python scripts/verify_preview.py
"""

from __future__ import annotations

import asyncio
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import (  # type: ignore  # noqa: E402
    MONGODB_DATABASE, MONGODB_URL, RouteMonologue, RoutePreview,
)
from app.services.mapbox_directions import fetch_route  # noqa: E402
from app.services.monologue_pipeline import polyline_hash  # noqa: E402
from app.services.route_preview import get_preview, start_preview  # noqa: E402
from motor.motor_asyncio import AsyncIOMotorClient  # noqa: E402
from beanie import init_beanie  # noqa: E402


SF = (37.7749, -122.4194)
TAHOE = (38.9399, -119.9772)

COLUMBIA_MO = (38.9517, -92.3341)
JEFFERSON_CITY_MO = (38.5767, -92.1735)

SCENARIOS = [
    ("SF -> Tahoe (scenic, long)", "San Francisco, CA", *SF, "South Lake Tahoe, CA", *TAHOE),
    ("Columbia -> Jefferson City, MO (mundane, short)",
     "Columbia, MO", *COLUMBIA_MO, "Jefferson City, MO", *JEFFERSON_CITY_MO),
]


async def init_db():
    client = AsyncIOMotorClient(MONGODB_URL)
    await init_beanie(
        database=client[MONGODB_DATABASE],
        document_models=[RoutePreview, RouteMonologue],
    )


async def _wait_ready(p_hash: str, timeout: float = 90.0) -> RoutePreview:
    deadline = time.time() + timeout
    last_stage = None
    while True:
        doc = await get_preview(p_hash)
        if doc.stage != last_stage:
            print(f"    stage -> {doc.stage}")
            last_stage = doc.stage
        if doc.status != "pending":
            return doc
        if time.time() > deadline:
            raise TimeoutError(f"preview for {p_hash[:8]} never finished")
        await asyncio.sleep(1.0)


def _print_result(doc: RoutePreview) -> None:
    print(f"  status: {doc.status}  distance: {doc.distance_miles:.0f}mi  "
          f"duration: {doc.duration_minutes}min")
    if doc.error:
        print(f"  error: {doc.error}")
        return
    print(f"  towns ({len(doc.towns)}): {', '.join(t['name'] for t in doc.towns)}")
    print(f"\n  RUNDOWN:\n  {'-' * 60}")
    for line in doc.rundown.splitlines():
        print(f"  {line}")
    print(f"\n  HOTSPOTS ({len(doc.hotspots)}):")
    for h in doc.hotspots:
        print(f"  [{h['theme']}] {h['title']} — near {h['town']}")
        print(f"    {h['blurb']}")
        if h.get("detour_hint"):
            print(f"    ({h['detour_hint']})")


async def main() -> int:
    if not os.getenv("MAPBOX_ACCESS_TOKEN"):
        print("ERROR: MAPBOX_ACCESS_TOKEN not in env")
        return 1
    if not os.getenv("ANTHROPIC_API_KEY"):
        print("ERROR: ANTHROPIC_API_KEY not in env")
        return 1

    await init_db()

    for label, origin_name, origin_lat, origin_lng, dest_name, dest_lat, dest_lng in SCENARIOS:
        print("\n" + "=" * 72)
        print(label)
        print("=" * 72)

        # Clear any prior cached preview so this run always exercises a
        # real generation — otherwise a repeat script run just serves
        # the first run's cached prose, which defeats the point of a
        # prompt-iteration script.
        route = await fetch_route(origin_lat, origin_lng, dest_lat, dest_lng)
        if route:
            deleted = await RoutePreview.find(
                RoutePreview.polyline_hash == polyline_hash(route.polyline),
            ).delete()
            if deleted.deleted_count:
                print(f"  (cleared {deleted.deleted_count} prior cached preview)")

        started = await start_preview(
            origin_lat, origin_lng, dest_lat, dest_lng,
            route_label=f"{origin_name} -> {dest_name}",
        )
        if started is None:
            print("  FAILED: no route from Mapbox Directions")
            continue

        t0 = time.time()
        doc = await _wait_ready(started.polyline_hash)
        dt = time.time() - t0
        print(f"  generated in {dt:.1f}s")
        _print_result(doc)

    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
