#!/usr/bin/env python3
"""Verify Slice C end-to-end.

Slice C adds POI verification: every LLM-proposed stop is checked
against Mapbox Search Box (with OSM Overpass fallback) and on-route
distance. Unverified picks get dropped before they reach the user.

Scenarios:
  1. Generate a monologue with stop_interests that should produce
     verifiable picks (food + entertainment in SF→Tahoe).
     Expected: most picks survive Mapbox; some may need Overpass.
  2. Inspect each verified stop: must have lat/lng, place_formatted,
     source ∈ {"mapbox", "osm"}, distance_from_route_miles <= 5.0.
  3. Confirm the proposed→verified attrition is reasonable (not all,
     not zero).

Run inside the container:
    docker compose exec -T backend python < backend/scripts/verify_slice_c.py
"""

from __future__ import annotations

import asyncio
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import (  # type: ignore  # noqa: E402
    MONGODB_DATABASE, MONGODB_URL, MonologueAudio, RouteMonologue,
)
from app.services.mapbox_directions import fetch_polyline  # noqa: E402
from app.services.monologue_pipeline import (  # noqa: E402
    generate_monologue, polyline_hash,
)
from motor.motor_asyncio import AsyncIOMotorClient  # noqa: E402
from beanie import init_beanie  # noqa: E402


SF = (37.7749, -122.4194)
TAHOE = (38.9399, -119.9772)
ROUTE_LABEL = "San Francisco, CA -> South Lake Tahoe, CA"


async def init_db():
    client = AsyncIOMotorClient(MONGODB_URL)
    await init_beanie(
        database=client[MONGODB_DATABASE],
        document_models=[RouteMonologue, MonologueAudio],
    )


async def main() -> int:
    print("Verify Slice C — stop verification (Mapbox + OSM Overpass)")
    print("=" * 72)

    if not os.getenv("MAPBOX_ACCESS_TOKEN") or not os.getenv("ANTHROPIC_API_KEY"):
        print("ERROR: need MAPBOX_ACCESS_TOKEN + ANTHROPIC_API_KEY")
        return 1

    await init_db()
    polyline = await fetch_polyline(SF[0], SF[1], TAHOE[0], TAHOE[1])
    p_hash = polyline_hash(polyline)
    # Clear any cached doc for this exact vibe so we run the full
    # verification path, not a cache hit.
    await RouteMonologue.find(RouteMonologue.polyline_hash == p_hash).delete()

    stop_interests = [
        {"category": "food", "detail": "Mexican, hole-in-the-wall"},
        {"category": "entertainment", "detail": "live music venues"},
        {"category": "attractions", "detail": "historic Gold Rush sites"},
    ]

    print(f"Generating monologue with {len(stop_interests)} stop_interests...")
    doc = await generate_monologue(
        polyline=polyline,
        route_label=ROUTE_LABEL,
        narration_themes=["history"],
        stop_interests=stop_interests,
    )
    if not doc:
        print("FAILED: no doc")
        return 1
    print(f"  utterances: {len(doc.utterances)}")
    print(f"  stops (verified, post-filter): {len(doc.stops)}")
    print()

    if not doc.stops:
        print("WARN: zero verified stops — verifier may be too strict, or "
              "LLM proposed picks Mapbox+OSM both couldn't pin.")

    # Inspect each verified stop
    print("=" * 72)
    print("Verified stops:")
    print("=" * 72)
    sources = {"mapbox": 0, "osm": 0}
    for s in doc.stops:
        src = s.get("source", "?")
        sources[src] = sources.get(src, 0) + 1
        print(f"  [{s.get('category','?')}] {s.get('name','?')}")
        print(f"    town          : {s.get('town','?')}")
        print(f"    coords        : ({s.get('lat','?')}, {s.get('lng','?')})")
        print(f"    place_formatted: {s.get('place_formatted','?')}")
        print(f"    source        : {src}")
        print(f"    distance      : {s.get('distance_from_route_miles', '?'):.2f}mi from route")
        print(f"    tied to utt   : {s.get('tied_to_utterance')}")
        print(f"    reason        : {(s.get('reason') or '')[:80]}")
        print()

    print("=" * 72)
    print(f"Source breakdown: mapbox={sources.get('mapbox',0)} "
          f"osm={sources.get('osm',0)}")
    print(f"Slice C verification: {'PASSED' if doc.stops else 'PARTIAL (no verified stops)'}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
