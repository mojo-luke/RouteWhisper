#!/usr/bin/env python3
"""Spike: route-as-narrative.

A more creative angle than "list of stops." Instead of asking the
LLM to PICK from candidates or PROPOSE from a vibe query, we ask
it to first CHARACTERIZE the route — what's this corridor *about*?
What's its identity, its themes, its arc? — and only THEN propose
stops that fit that identity.

The hypothesis: a route has character (I-80 SF->Tahoe is the Gold
Rush corridor / Donner Party trail / coast-to-alpine arc). LLMs
have encoded this character from travel writing, history, geography.
If we surface that character first, downstream stop picks become
part of a connected story rather than a list of restaurants.

This is also the closest spike to the companion-first product
ethos — the companion as someone who knows what this drive IS,
not just what's near you.

Pipeline:
  1. Get the route polyline
  2. Stage 1 LLM: characterize the corridor (themes, story, arc)
  3. Stage 2 LLM: given that characterization, propose 5-7 stops
     that build a narrative along the route, with reasoning that
     references the character
  4. Verify each via Mapbox Search Box /forward + on-route check
  5. Print: the characterization, the narrative picks, the verification
     status, and a side-by-side comparison vs a naive baseline
     (just "suggest 5 stops, no characterization") to see if the
     two-stage approach changes the picks.

Run from anywhere:
    python3 backend/scripts/spike_route_narrative.py
"""

from __future__ import annotations

import asyncio
import json
import os
import re
import sys
import urllib.parse
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


ROUTES = {
    # Famous corridor — strong baseline of LLM knowledge to draw from.
    "sf-tahoe": {
        "origin": (37.7749, -122.4194),
        "dest": (38.9399, -119.9772),
        "label": "San Francisco, CA -> South Lake Tahoe, CA",
    },
    # Obscure rural drive — tests whether the narrative approach
    # generalizes beyond famous corridors. Oregon high desert,
    # ~130 mi mostly through emptiness with a few small towns.
    "bend-burns": {
        "origin": (44.0582, -121.3153),
        "dest": (43.5862, -118.9526),
        "label": "Bend, OR -> Burns, OR (via US-20 through Oregon high desert)",
    },
    # Mid-fame corridor — Memphis blues / Mississippi Delta vibes.
    "memphis-littlerock": {
        "origin": (35.1495, -90.0490),
        "dest": (34.7465, -92.2896),
        "label": "Memphis, TN -> Little Rock, AR (via I-40)",
    },
}
ROUTE_KEY = sys.argv[1] if len(sys.argv) > 1 else "sf-tahoe"
if ROUTE_KEY not in ROUTES:
    print(f"unknown route key: {ROUTE_KEY}. options: {list(ROUTES)}")
    sys.exit(2)
_R = ROUTES[ROUTE_KEY]
SF = _R["origin"]
TAHOE = _R["dest"]
ROUTE_LABEL = _R["label"]
NUM_STOPS = 6
ON_ROUTE_MAX_MILES = 5.0
LLM_MODEL = "claude-sonnet-4-6"


CHARACTERIZE_PROMPT = """You are a travel writer who knows American
road trips intimately. Characterize the following route as a place
with identity, not just a line on a map.

Route: {route}

In 3-4 short paragraphs, describe:
- The route's historic, cultural, or geographic identity (what is this
  corridor known for? what does it mean in American road-trip lore?)
- The story arc of the drive (what changes between start and end —
  landscape, climate, vibe?)
- Any specific themes or threads a traveler might consciously follow

Keep it grounded — only mention places, events, or themes you're
confident are real. No invented history.
"""


NARRATIVE_STOPS_PROMPT = """You are still the same travel writer.
You just wrote the characterization below.

ROUTE CHARACTERIZATION:
{characterization}

Now propose {n} specific stops along this route that build a
narrative thread true to the route's identity. Each stop should:
- Be a REAL place (only list places you're confident exist)
- Connect to the route's character (don't pick random restaurants
  that could exist anywhere — pick things that *belong here*)
- Vary in type if possible — historic site, regional food, viewpoint,
  oddity — but don't force variety; let the route's character lead

For each stop, include the town, an address hint if you know it,
and ONE short line tying it back to the route's character.

Return ONLY a JSON array (no markdown fences, no preamble):
[
  {{"name": "...", "town": "...", "address_hint": "...", "reason": "..."}},
  ...
]
"""


BASELINE_PROMPT = """You are a travel writer. Suggest {n} real
places to stop at along this route: {route}. Pick a mix of types.
Only list places you're confident exist.

Return ONLY a JSON array (no markdown fences, no preamble):
[
  {{"name": "...", "town": "...", "address_hint": "...", "reason": "..."}},
  ...
]
"""


def _clean_town(town: str) -> str:
    t = re.sub(r"\([^)]*\)", "", town).strip()
    t = t.split(",")[0].strip()
    return t


def _parse_json_array(text: str) -> list[dict]:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return []


async def llm_characterize(client) -> str:
    resp = await client.messages.create(
        model=LLM_MODEL,
        max_tokens=900,
        messages=[{"role": "user", "content": CHARACTERIZE_PROMPT.format(route=ROUTE_LABEL)}],
    )
    return resp.content[0].text.strip()


async def llm_narrative_stops(client, characterization: str) -> list[dict]:
    resp = await client.messages.create(
        model=LLM_MODEL,
        max_tokens=1800,
        messages=[{"role": "user", "content": NARRATIVE_STOPS_PROMPT.format(
            characterization=characterization, n=NUM_STOPS,
        )}],
    )
    return _parse_json_array(resp.content[0].text)


async def llm_baseline_stops(client) -> list[dict]:
    resp = await client.messages.create(
        model=LLM_MODEL,
        max_tokens=1800,
        messages=[{"role": "user", "content": BASELINE_PROMPT.format(
            route=ROUTE_LABEL, n=NUM_STOPS,
        )}],
    )
    return _parse_json_array(resp.content[0].text)


async def geocode_place(http, name: str, town: str, token: str) -> dict | None:
    """Mapbox Search Box /forward; POI-aware."""
    clean_town = _clean_town(town)
    query = f"{name} {clean_town}".strip()
    url = "https://api.mapbox.com/search/searchbox/v1/forward"
    # Bias toward the route's midpoint so we don't get NJ matches
    # for Oregon names.
    mid_lat = (SF[0] + TAHOE[0]) / 2
    mid_lng = (SF[1] + TAHOE[1]) / 2
    params = {
        "q": query,
        "limit": 5,
        "country": "us",
        "proximity": f"{mid_lng},{mid_lat}",
        "access_token": token,
    }
    try:
        r = await http.get(url, params=params, timeout=15.0)
        r.raise_for_status()
        feats = r.json().get("features") or []
        if not feats:
            return None
        for f in feats:
            p = f.get("properties") or {}
            f_name = (p.get("name") or "").lower()
            place_formatted = (p.get("place_formatted") or "").lower()
            coords = (f.get("geometry") or {}).get("coordinates") or []
            if len(coords) < 2:
                continue
            name_match = name.lower() in f_name or f_name in name.lower()
            town_match = clean_town.lower() in place_formatted or "california" in place_formatted
            if name_match and town_match:
                return {
                    "name": p.get("name"),
                    "place_formatted": p.get("place_formatted"),
                    "lng": coords[0],
                    "lat": coords[1],
                }
        # Weak match
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


async def verify_stops(stops, http, coords, token):
    """Verify a list of LLM-proposed stops; classify each."""
    sem = asyncio.Semaphore(3)

    async def _one(s):
        async with sem:
            await asyncio.sleep(0.1)
            match = await geocode_place(http, s["name"], s["town"], token)
            return s, match

    results = await asyncio.gather(*[_one(s) for s in stops])
    classified = []
    for s, m in results:
        if not m:
            classified.append((s, m, "hallucinated", None))
        elif m.get("weak_match"):
            classified.append((s, m, "weak", None))
        else:
            d = point_to_line_distance((m["lat"], m["lng"]), coords)
            if d > ON_ROUTE_MAX_MILES:
                classified.append((s, m, "off_route", d))
            else:
                classified.append((s, m, "verified", d))
    return classified


def print_stop_set(label, classified):
    print(f"\n--- {label} ---")
    counts = {"verified": 0, "off_route": 0, "weak": 0, "hallucinated": 0}
    for s, m, status, d in classified:
        counts[status] += 1
        if status == "verified":
            print(f"  ✓ {s['name']} ({s['town']}) — {d:.1f}mi from route")
            print(f"     {m['place_formatted']}")
            print(f"     {s['reason']}")
        elif status == "off_route":
            print(f"  ◯ {s['name']} ({s['town']}) — {d:.1f}mi OFF route")
            print(f"     {s['reason']}")
        elif status == "weak":
            print(f"  ? {s['name']} ({s['town']}) — Mapbox returned: {m.get('place_formatted','?')}")
        else:
            print(f"  ✗ {s['name']} ({s['town']}) — no geocode match")
    print(f"  Score: {counts['verified']}/{len(classified)} verified on route")
    return counts


async def main() -> int:
    load_dotenv(BACKEND_DIR / ".env")
    mbx = os.getenv("MAPBOX_ACCESS_TOKEN")
    ant_key = os.getenv("ANTHROPIC_API_KEY")
    if not mbx or not ant_key:
        print("Need MAPBOX_ACCESS_TOKEN + ANTHROPIC_API_KEY")
        return 1

    print(f"Spike: route-as-narrative")
    print(f"Route : {ROUTE_LABEL}")
    print(f"Model : {LLM_MODEL}")
    print("=" * 72)

    polyline = await fetch_polyline(SF[0], SF[1], TAHOE[0], TAHOE[1])
    if not polyline:
        return 1
    coords = decode_polyline(polyline)

    anth = AsyncAnthropic(api_key=ant_key)

    # STAGE 1: characterize the route
    print("\n=== STAGE 1: Route characterization ===")
    characterization = await llm_characterize(anth)
    print(characterization)

    # STAGE 2A: narrative stops (informed by characterization)
    print(f"\n=== STAGE 2A: Narrative-driven picks (LLM uses the characterization) ===")
    narrative_stops = await llm_narrative_stops(anth, characterization)
    print(f"LLM proposed {len(narrative_stops)} picks tied to the route's identity")

    # STAGE 2B: baseline (no characterization)
    print(f"\n=== STAGE 2B: Baseline picks (no characterization context) ===")
    baseline_stops = await llm_baseline_stops(anth)
    print(f"LLM proposed {len(baseline_stops)} picks from a generic prompt")

    # VERIFY both sets
    async with httpx.AsyncClient() as http:
        narrative_classified = await verify_stops(narrative_stops, http, coords, mbx)
        baseline_classified = await verify_stops(baseline_stops, http, coords, mbx)

    print("\n" + "=" * 72)
    print("RESULTS — side by side")
    print("=" * 72)
    narr_counts = print_stop_set("Narrative-driven picks", narrative_classified)
    base_counts = print_stop_set("Baseline picks (no character context)", baseline_classified)

    # Honest comparison
    print("\n" + "=" * 72)
    print("SUMMARY")
    print("=" * 72)
    print(f"Narrative-driven: {narr_counts['verified']}/{len(narrative_classified)} verified on route")
    print(f"Baseline:         {base_counts['verified']}/{len(baseline_classified)} verified on route")
    print()
    print("Eyeball: do the narrative picks feel like they BELONG on this")
    print("specific route, or could they exist anywhere? Does the picks'")
    print("reasoning reference the route's character?")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
