#!/usr/bin/env python3
"""Verify Slice A end-to-end.

Initializes Mongo + Beanie, then calls generate_monologue directly
(same code path the new endpoint runs, without the HTTP/auth shell).

Scenarios:
  1. SF -> Tahoe with narration_themes=["history"], no stops
     Expected: 8-10 utterances, 0 stops, towns extracted
  2. Same route with themes=["history", "food_culture"] +
     stop_interests=[{food, "Mexican"}, {entertainment, "live music"}]
     Expected: blended monologue, stops list populated
  3. Repeat call #1 — should be a cache hit (no LLM call)

Run inside the container:
    docker compose exec backend python /app/app/../scripts/verify_slice_a.py
"""

from __future__ import annotations

import asyncio
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import (  # type: ignore  # noqa: E402
    RouteMonologue, MONGODB_URL, MONGODB_DATABASE,
)
from app.services.mapbox_directions import fetch_polyline  # noqa: E402
from app.services.monologue_pipeline import (  # noqa: E402
    generate_monologue, polyline_hash, vibe_hash,
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
        document_models=[RouteMonologue],
    )


def _summarize(doc: RouteMonologue):
    print(f"  polyline_hash : {doc.polyline_hash[:12]}...")
    print(f"  vibe_hash     : {doc.vibe_hash[:12]}...")
    print(f"  themes        : {doc.narration_themes}")
    print(f"  stop_interests: {doc.stop_interests}")
    print(f"  towns         : {len(doc.towns)} ({', '.join(t['name'] for t in doc.towns)})")
    print(f"  characterization: {len(doc.characterization)} chars")
    print(f"  utterances    : {len(doc.utterances)}")
    print(f"  stops         : {len(doc.stops)}")
    if doc.utterances:
        print(f"  first utterance:")
        u = doc.utterances[0]
        print(f"    [{u.get('i','?')}] @ {u.get('anchor','?')}: {u.get('utterance','')[:120]}...")
    if doc.stops:
        print(f"  first stop:")
        s = doc.stops[0]
        print(f"    {s.get('category','?')}: {s.get('name','?')} in {s.get('town','?')}")
        print(f"    tied_to_utterance={s.get('tied_to_utterance')}")


async def main() -> int:
    print(f"Verify Slice A — generate_monologue end-to-end")
    print("=" * 72)

    if not os.getenv("MAPBOX_ACCESS_TOKEN"):
        print("ERROR: MAPBOX_ACCESS_TOKEN not in env")
        return 1
    if not os.getenv("ANTHROPIC_API_KEY"):
        print("ERROR: ANTHROPIC_API_KEY not in env")
        return 1

    await init_db()
    print("DB initialized.")

    # Get the polyline
    polyline = await fetch_polyline(SF[0], SF[1], TAHOE[0], TAHOE[1])
    if not polyline:
        print("ERROR: no polyline from Mapbox Directions")
        return 1
    p_hash = polyline_hash(polyline)
    print(f"Polyline: {p_hash[:12]}... ({len(polyline)} chars)")

    # Clean up any previous RouteMonologue for this polyline so the
    # cache-miss path runs (otherwise we'd just get a hit from a prior run).
    deleted = await RouteMonologue.find(
        RouteMonologue.polyline_hash == p_hash,
    ).delete()
    print(f"Cleared {deleted.deleted_count} prior cached docs for this polyline.")

    # --- Scenario 1: history-only, no stops ---
    print("\n--- Scenario 1: themes=['history'], no stops ---")
    t0 = time.time()
    doc1 = await generate_monologue(
        polyline=polyline,
        route_label=ROUTE_LABEL,
        narration_themes=["history"],
        stop_interests=[],
    )
    dt = time.time() - t0
    if not doc1:
        print("FAILED: no doc produced")
        return 1
    print(f"  generated in {dt:.1f}s (cache miss)")
    _summarize(doc1)

    # --- Scenario 2: themes + stops ---
    print("\n--- Scenario 2: themes=['history', 'food_culture'], "
          "stop_interests=[Mexican food, live music] ---")
    t0 = time.time()
    doc2 = await generate_monologue(
        polyline=polyline,
        route_label=ROUTE_LABEL,
        narration_themes=["history", "food_culture"],
        stop_interests=[
            {"category": "food", "detail": "Mexican, hole-in-the-wall"},
            {"category": "entertainment", "detail": "live music venues"},
        ],
    )
    dt = time.time() - t0
    if not doc2:
        print("FAILED: no doc produced")
        return 1
    print(f"  generated in {dt:.1f}s (cache miss)")
    _summarize(doc2)

    # --- Scenario 3: repeat scenario 1, expect cache hit ---
    print("\n--- Scenario 3: REPEAT scenario 1, expect cache hit ---")
    t0 = time.time()
    doc3 = await generate_monologue(
        polyline=polyline,
        route_label=ROUTE_LABEL,
        narration_themes=["history"],
        stop_interests=[],
    )
    dt = time.time() - t0
    if not doc3:
        print("FAILED: no doc produced")
        return 1
    same = doc3.id == doc1.id
    print(f"  returned in {dt:.2f}s")
    print(f"  same doc as scenario 1: {same}")
    if dt > 2.0:
        print(f"  WARN: too slow for a cache hit ({dt:.1f}s) — was LLM called?")

    print("\n" + "=" * 72)
    print("Slice A verification PASSED" if same and doc2.id != doc1.id
          else "Slice A verification PARTIAL — check output above")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
