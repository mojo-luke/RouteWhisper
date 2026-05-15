#!/usr/bin/env python3
"""Spike: monologue + stops as a single coherent narrative.

The two previous spikes were great but they treated stops and
narration as separate things. This spike tests: what if we ask the
LLM for BOTH in one call? The stops emerge as natural detours from
the monologue's narrative arc, not as a parallel list.

Pipeline:
  1. Polyline + town list
  2. Stage 1: route characterization (same prompt as siblings)
  3. Stage 2: ONE prompt that asks for both:
        - 6-8 narration utterances along the drive
        - 3-5 specific places the listener might actually want to
          pull over for, each tied to a moment in the monologue
        - Output is a single JSON object with both keys
  4. Verify each stop via Mapbox Search Box; check on-route
  5. Render the script with embedded "[suggested stop here]" markers
     so the connection between monologue and stops is visible

Run from anywhere:
    python3 backend/scripts/spike_monologue_with_stops.py [route] [vibe]
"""

from __future__ import annotations

import asyncio
import json
import os
import re
import sys
from collections import OrderedDict
from pathlib import Path

import httpx
from dotenv import load_dotenv

BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_DIR))

from app.services.mapbox_directions import fetch_polyline  # noqa: E402
from app.utils.polyline import (  # noqa: E402
    calculate_distance_miles,
    decode_polyline,
    point_to_line_distance,
)
from anthropic import AsyncAnthropic  # noqa: E402


ROUTES = {
    "sf-tahoe": {
        "origin": (37.7749, -122.4194),
        "dest": (38.9399, -119.9772),
        "label": "San Francisco, CA -> South Lake Tahoe, CA",
    },
    "bend-burns": {
        "origin": (44.0582, -121.3153),
        "dest": (43.5862, -118.9526),
        "label": "Bend, OR -> Burns, OR (via US-20 through Oregon high desert)",
    },
}
ROUTE_KEY = sys.argv[1] if len(sys.argv) > 1 else "sf-tahoe"
VIBE_OVERLAY = sys.argv[2] if len(sys.argv) > 2 else None
_R = ROUTES[ROUTE_KEY]
ORIGIN = _R["origin"]
DEST = _R["dest"]
ROUTE_LABEL = _R["label"]
NUM_UTTERANCES = 8
NUM_STOPS = 4
ON_ROUTE_MAX_MILES = 5.0
LLM_MODEL = "claude-sonnet-4-6"


CHARACTERIZE_PROMPT = """You are a travel writer who knows American
road trips intimately. In 3-4 short paragraphs, characterize this
route as a place with identity: its history, the story arc, themes
a traveler might follow. Stay grounded — only mention real places.

Route: {route}
"""


COMBINED_PROMPT = """You are a road-trip companion riding along with
the driver. You wrote the characterization below.

ROUTE CHARACTERIZATION:
{characterization}

TOWNS THE ROUTE PASSES THROUGH (in order):
{town_list}
{vibe_section}
Now write TWO things in one response, as a single JSON object:

1. A "monologue" of {n_utt} short utterances you'd actually speak
   during the drive. Each utterance: 25-40 words, conversational
   ("friend in the passenger seat" voice, NOT tour-guide), anchored
   to a town or landmark along the route, building on the previous
   ones as a connected narrative.

2. A "stops" list of {n_stops} specific real places the driver
   might want to PULL OFF the road for — places that emerge
   organically from your monologue's themes, not random nearby
   restaurants. Each stop should connect to one of the utterances
   you wrote. Reference the utterance index it ties to.

Format (return EXACTLY this shape, no preamble, no markdown fences):

{{
  "monologue": [
    {{"i": 1, "anchor": "town", "utterance": "..."}},
    {{"i": 2, "anchor": "town", "utterance": "..."}}
  ],
  "stops": [
    {{"name": "...", "town": "...", "address_hint": "...",
      "tied_to_utterance": 3, "reason": "..."}}
  ]
}}

Hard rules:
- Only mention REAL places. If unsure, omit.
- Stops must be along the route, not 50 miles off.
- Each stop's "tied_to_utterance" must reference a real utterance index.
"""


def _stride_sample(coords, stride_miles):
    if not coords:
        return []
    samples = [coords[0]]
    cum = 0.0
    for i in range(1, len(coords)):
        cum += calculate_distance_miles(coords[i - 1], coords[i])
        if cum >= stride_miles:
            samples.append(coords[i])
            cum = 0.0
    if samples[-1] != coords[-1]:
        samples.append(coords[-1])
    return samples


def _clean_town(town: str) -> str:
    t = re.sub(r"\([^)]*\)", "", town).strip()
    t = t.split(",")[0].strip()
    return t


def _parse_json(text: str) -> dict:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        print(f"  JSON parse failed: {e}")
        print(f"  Raw head: {text[:300]}")
        return {}


async def reverse_geocode_locality(client, lat, lng, token):
    url = f"https://api.mapbox.com/geocoding/v5/mapbox.places/{lng},{lat}.json"
    params = {"types": "place", "access_token": token, "limit": 1}
    r = await client.get(url, params=params, timeout=15.0)
    r.raise_for_status()
    feats = r.json().get("features") or []
    return feats[0].get("text") if feats else None


async def geocode_place(http, name: str, town: str, token: str) -> dict | None:
    clean_town = _clean_town(town)
    query = f"{name} {clean_town}".strip()
    url = "https://api.mapbox.com/search/searchbox/v1/forward"
    mid_lat = (ORIGIN[0] + DEST[0]) / 2
    mid_lng = (ORIGIN[1] + DEST[1]) / 2
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
            town_match = (clean_town.lower() in place_formatted
                          or "california" in place_formatted
                          or "oregon" in place_formatted)
            if name_match and town_match:
                return {
                    "name": p.get("name"),
                    "place_formatted": p.get("place_formatted"),
                    "lng": coords[0],
                    "lat": coords[1],
                }
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
        print("Need MAPBOX_ACCESS_TOKEN + ANTHROPIC_API_KEY")
        return 1

    print(f"Spike: monologue + stops in one call")
    print(f"Route : {ROUTE_LABEL}")
    print(f"Vibe  : {VIBE_OVERLAY or '(none)'}")
    print(f"Model : {LLM_MODEL}")
    print("=" * 72)

    polyline = await fetch_polyline(ORIGIN[0], ORIGIN[1], DEST[0], DEST[1])
    if not polyline:
        return 1
    coords = decode_polyline(polyline)
    samples = _stride_sample(coords, 25.0)
    async with httpx.AsyncClient() as http:
        sem = asyncio.Semaphore(3)

        async def _geo(p):
            async with sem:
                await asyncio.sleep(0.1)
                try:
                    return await reverse_geocode_locality(http, p[0], p[1], mbx)
                except Exception:
                    return None

        names = await asyncio.gather(*[_geo(p) for p in samples])
    towns = list(OrderedDict((n, None) for n in names if n).keys())
    print(f"\nTowns on route ({len(towns)}): {', '.join(towns)}")

    anth = AsyncAnthropic(api_key=ant_key)

    print("\n=== STAGE 1: Route characterization ===")
    char_resp = await anth.messages.create(
        model=LLM_MODEL,
        max_tokens=800,
        messages=[{"role": "user", "content": CHARACTERIZE_PROMPT.format(route=ROUTE_LABEL)}],
    )
    characterization = char_resp.content[0].text.strip()
    print(characterization[:500] + ("..." if len(characterization) > 500 else ""))

    print(f"\n=== STAGE 2: Combined monologue + stops ===")
    vibe_section = (
        f"\nYOUR VOICE/INTEREST TILT FOR THIS DRIVE: {VIBE_OVERLAY}\n"
        if VIBE_OVERLAY else ""
    )
    combined_resp = await anth.messages.create(
        model=LLM_MODEL,
        max_tokens=2800,
        messages=[{"role": "user", "content": COMBINED_PROMPT.format(
            characterization=characterization,
            town_list=", ".join(towns),
            vibe_section=vibe_section,
            n_utt=NUM_UTTERANCES,
            n_stops=NUM_STOPS,
        )}],
    )
    parsed = _parse_json(combined_resp.content[0].text)
    monologue = parsed.get("monologue") or []
    stops = parsed.get("stops") or []
    print(f"Parsed: {len(monologue)} utterances, {len(stops)} stops")

    # Verify stops
    print(f"\n=== Verifying stops ===")
    async with httpx.AsyncClient() as http:
        sem2 = asyncio.Semaphore(3)

        async def _vstop(s):
            async with sem2:
                await asyncio.sleep(0.1)
                m = await geocode_place(http, s.get("name", ""), s.get("town", ""), mbx)
                return s, m

        verified_pairs = await asyncio.gather(*[_vstop(s) for s in stops])

    # Index utterances by i
    utt_by_i = {u.get("i"): u for u in monologue}

    print("\n" + "=" * 72)
    print("THE SCRIPT (utterances with embedded stop suggestions)")
    print("=" * 72)

    # Render: walk utterances, inject stops at their tied utterance
    stops_by_tied = {}
    for s, m in verified_pairs:
        key = s.get("tied_to_utterance")
        stops_by_tied.setdefault(key, []).append((s, m))

    for u in monologue:
        i = u.get("i")
        anchor = u.get("anchor") or "?"
        utt = u.get("utterance") or ""
        anchor_ok = anchor.lower() in " ".join(towns).lower()
        mark = "✓" if anchor_ok else "?"
        print(f"\n[{i:2d}] {mark} @ {anchor}")
        # Soft-wrap
        line = ""
        for w in utt.split():
            if len(line) + len(w) > 76:
                print(f"     {line}")
                line = w
            else:
                line = (line + " " + w).strip()
        if line:
            print(f"     {line}")
        # Stops tied to this utterance
        for s, m in stops_by_tied.get(i, []):
            if not m:
                print(f"     >> Stop suggestion: {s['name']} (?? — no geocode match)")
                continue
            if m.get("weak_match"):
                print(f"     >> Stop suggestion: {s['name']} (weak match: {m['place_formatted']})")
                continue
            d = point_to_line_distance((m["lat"], m["lng"]), coords)
            on_route = d <= ON_ROUTE_MAX_MILES
            mark2 = "✓" if on_route else "◯"
            print(f"     >> {mark2} Stop: {s['name']} ({d:.1f}mi from route)")
            print(f"        {m['place_formatted']}")
            print(f"        {s.get('reason','')}")

    # Stops not tied to any utterance (orphans)
    orphans = [(s, m) for s, m in verified_pairs
               if s.get("tied_to_utterance") not in utt_by_i]
    if orphans:
        print(f"\n--- Stops without a tied utterance ---")
        for s, m in orphans:
            print(f"  ! {s['name']} — tied_to_utterance={s.get('tied_to_utterance')}")

    # Summary
    n_verified = sum(
        1 for s, m in verified_pairs
        if m and not m.get("weak_match")
        and point_to_line_distance((m["lat"], m["lng"]), coords) <= ON_ROUTE_MAX_MILES
    )
    n_tied = sum(1 for s, _ in verified_pairs if s.get("tied_to_utterance") in utt_by_i)
    print("\n" + "=" * 72)
    print("SUMMARY")
    print("=" * 72)
    print(f"Utterances: {len(monologue)}")
    print(f"Stops proposed: {len(stops)}")
    print(f"Stops verified on route: {n_verified}/{len(stops)}")
    print(f"Stops correctly tied to a real utterance: {n_tied}/{len(stops)}")
    print()
    print("Eyeball: do the stops feel like natural continuations of the")
    print("monologue's voice, or like a tacked-on list?")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
