#!/usr/bin/env python3
"""Spike: LLM-first stop suggester (vs the multi-step pipeline).

Question: instead of (Mapbox /category -> LLM filter), what if we
just ask the LLM directly? Pros: simpler, taps editorial knowledge
in training data. Cons: hallucination risk, stale knowledge, no
coords. This spike measures the risk.

Pipeline:
  1. Ask Claude Sonnet for 10 real hole-in-the-wall Mexican spots
     along SF -> Lake Tahoe. Force structured JSON output. Tell
     the model to omit places it isn't confident about.
  2. For each suggestion: forward-geocode via Mapbox.
     - No match  -> probable hallucination
     - Match     -> check distance from the actual route polyline
  3. Report: hallucination rate, on-route rate, list verified picks.

Output should answer: "is the multi-step pipeline overengineered,
or does the LLM-only path hallucinate too often to trust?"

Run from anywhere:
    python3 backend/scripts/spike_llm_first.py
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
from pathlib import Path

import httpx
from dotenv import load_dotenv

BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_DIR))

from app.services.mapbox_directions import fetch_polyline  # noqa: E402
from app.utils.polyline import (  # noqa: E402
    decode_polyline,
    point_to_line_distance,
)
from anthropic import AsyncAnthropic  # noqa: E402


SF = (37.7749, -122.4194)
TAHOE = (38.9399, -119.9772)
ROUTE_LABEL = "San Francisco, CA -> South Lake Tahoe, CA (via I-80)"
VIBE_QUERY = (
    "hole-in-the-wall taco or Mexican food joints — places with "
    "character, locals love them, not chains, not generic fast food"
)
NUM_SUGGESTIONS_REQUESTED = 10
ON_ROUTE_MAX_MILES = 5.0
LLM_MODEL = "claude-sonnet-4-6"  # better world knowledge than haiku


PROMPT_TEMPLATE = """You are a knowledgeable road-trip food writer.

Route: {route}
Vibe: {vibe}

Suggest up to {n} REAL places along this route that fit the vibe.

HARD RULES:
- Only list places you are confident actually exist. If you only know
  4 places, list 4. Do NOT pad to {n}.
- Include the town/city the place is in.
- Include the street address if you know it; leave it blank otherwise.
- One short reason per place explaining why it fits the vibe.

Return ONLY a JSON array, no preamble, no markdown fences:

[
  {{"name": "...", "town": "...", "address_hint": "...", "reason": "..."}},
  ...
]"""


async def ask_llm_for_picks(client) -> list[dict]:
    """Ask the LLM for candidate places. Returns list of dicts."""
    prompt = PROMPT_TEMPLATE.format(
        route=ROUTE_LABEL,
        vibe=VIBE_QUERY,
        n=NUM_SUGGESTIONS_REQUESTED,
    )
    resp = await client.messages.create(
        model=LLM_MODEL,
        max_tokens=2000,
        messages=[{"role": "user", "content": prompt}],
    )
    text = resp.content[0].text.strip()
    # Strip ```json fences if Sonnet adds them despite the prompt.
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        print(f"  LLM JSON parse failed: {e}")
        print(f"  Raw text:\n{text}")
        return []


def _clean_town(town: str) -> str:
    """LLM sometimes appends '(Glen Park)' or ', CA' to the town
    name — strip both so it doesn't pollute the query."""
    import re
    t = re.sub(r"\([^)]*\)", "", town).strip()
    t = t.split(",")[0].strip()
    return t


async def geocode_place(http, name: str, town: str, token: str) -> dict | None:
    """Forward-geocode a place via Mapbox Search Box /forward.

    Search Box /forward is POI-aware, unlike the legacy v5 geocoder
    which is address-focused. For 'La Corneta Taqueria', the legacy
    geocoder returns nothing or 'Diamond Street'; Search Box returns
    the actual POI with all of its locations.
    """
    clean_town = _clean_town(town)
    query = f"{name} {clean_town}".strip()
    url = "https://api.mapbox.com/search/searchbox/v1/forward"
    params = {
        "q": query,
        "limit": 5,
        "country": "us",
        "proximity": "-121.2,38.4",  # SF-Tahoe corridor midpoint
        "access_token": token,
    }
    try:
        r = await http.get(url, params=params, timeout=15.0)
        r.raise_for_status()
        feats = r.json().get("features") or []
        if not feats:
            return None
        # Prefer features whose name matches the LLM-given name AND
        # whose place_formatted contains the town.
        for f in feats:
            p = f.get("properties") or {}
            f_name = (p.get("name") or "").lower()
            place_formatted = (p.get("place_formatted") or "").lower()
            coords = (f.get("geometry") or {}).get("coordinates") or []
            if len(coords) < 2:
                continue
            name_match = (name.lower() in f_name) or (f_name in name.lower())
            town_match = (clean_town.lower() in place_formatted) or ("california" in place_formatted)
            if name_match and town_match:
                return {
                    "name": p.get("name"),
                    "place_formatted": p.get("place_formatted"),
                    "lng": coords[0],
                    "lat": coords[1],
                }
        # Soft match: town matches but name doesn't.
        for f in feats:
            p = f.get("properties") or {}
            place_formatted = (p.get("place_formatted") or "").lower()
            coords = (f.get("geometry") or {}).get("coordinates") or []
            if len(coords) < 2:
                continue
            if clean_town.lower() in place_formatted:
                return {
                    "name": p.get("name"),
                    "place_formatted": p.get("place_formatted"),
                    "lng": coords[0],
                    "lat": coords[1],
                    "weak_match": True,
                }
        return None
    except Exception:
        return None


async def main() -> int:
    load_dotenv(BACKEND_DIR / ".env")
    mbx = os.getenv("MAPBOX_ACCESS_TOKEN")
    ant_key = os.getenv("ANTHROPIC_API_KEY")
    if not mbx or not ant_key:
        print("Need MAPBOX_ACCESS_TOKEN + ANTHROPIC_API_KEY in backend/.env")
        return 1

    print(f"Spike: LLM-first stop suggester")
    print(f"Route : {ROUTE_LABEL}")
    print(f"Vibe  : {VIBE_QUERY!r}")
    print(f"Model : {LLM_MODEL}")
    print("=" * 72)

    # 1. Route polyline for off-route filtering
    polyline = await fetch_polyline(SF[0], SF[1], TAHOE[0], TAHOE[1])
    if not polyline:
        print("ERROR: no polyline")
        return 1
    coords = decode_polyline(polyline)
    print(f"Polyline: {len(coords)} coords")

    # 2. Ask the LLM
    anth = AsyncAnthropic(api_key=ant_key)
    print(f"\nAsking {LLM_MODEL} for up to {NUM_SUGGESTIONS_REQUESTED} picks...")
    suggestions = await ask_llm_for_picks(anth)
    if not suggestions:
        print("LLM returned no parsable suggestions.")
        return 1
    print(f"LLM returned {len(suggestions)} suggestions:")
    for s in suggestions:
        addr = f" — {s['address_hint']}" if s.get('address_hint') else ""
        print(f"  - {s['name']} ({s['town']}){addr}")

    # 3. Geocode-verify each
    print(f"\nVerifying each via Mapbox forward geocoding...")
    async with httpx.AsyncClient() as http:
        sem = asyncio.Semaphore(3)

        async def _verify(s):
            async with sem:
                await asyncio.sleep(0.1)
                match = await geocode_place(http, s["name"], s["town"], mbx)
                return s, match

        results = await asyncio.gather(*[_verify(s) for s in suggestions])

    # 4. Classify each
    real = []
    hallucinated = []
    weak = []
    off_route = []

    for s, match in results:
        if not match:
            hallucinated.append(s)
            continue
        if match.get("weak_match"):
            weak.append((s, match))
            continue
        # Check on-route distance
        dist_miles = point_to_line_distance((match["lat"], match["lng"]), coords)
        if dist_miles > ON_ROUTE_MAX_MILES:
            off_route.append((s, match, dist_miles))
            continue
        real.append((s, match, dist_miles))

    # 5. Report
    print("\n" + "=" * 72)
    print("RESULTS")
    print("=" * 72)
    print(f"Total LLM suggestions:       {len(suggestions)}")
    print(f"  Verified (on route)        {len(real)}")
    print(f"  Off route (>{ON_ROUTE_MAX_MILES:.0f}mi from line) {len(off_route)}")
    print(f"  Weak name match           {len(weak)}")
    print(f"  No geocode match (likely hallucinated) {len(hallucinated)}")
    print()
    hallucination_rate = (
        100 * (len(hallucinated) + len(weak)) / len(suggestions)
    )
    print(f"Soft hallucination rate (no-match + weak-match): {hallucination_rate:.0f}%")

    if real:
        print(f"\n--- Verified on-route picks ({len(real)}) ---")
        for s, m, d in real:
            print(f"  ✓ {s['name']} ({s['town']}) — {d:.1f}mi from route")
            print(f"    {m.get('place_formatted') or m.get('place_name')}")
            print(f"    Reason: {s['reason']}")
            print()

    if off_route:
        print(f"\n--- Off-route ({len(off_route)}) ---")
        for s, m, d in off_route:
            print(f"  ◯ {s['name']} ({s['town']}) — {d:.1f}mi off route")

    if weak:
        print(f"\n--- Weak-match (likely wrong place returned) ({len(weak)}) ---")
        for s, m in weak:
            print(f"  ? LLM said: {s['name']} in {s['town']}")
            print(f"    Mapbox returned: {m['place_name']}")

    if hallucinated:
        print(f"\n--- No geocode match — likely hallucinated ({len(hallucinated)}) ---")
        for s in hallucinated:
            addr = f" — {s.get('address_hint','')}" if s.get('address_hint') else ""
            print(f"  ✗ {s['name']} ({s['town']}){addr}")

    print("\n" + "=" * 72)
    print("Compare these picks to the pipeline's picks from earlier.")
    print("Honest question: which list would you actually drive to?")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
