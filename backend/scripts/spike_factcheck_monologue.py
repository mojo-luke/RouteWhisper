#!/usr/bin/env python3
"""Spike: monologue + stops + fact-check pass.

Builds on spike_monologue_with_stops.py. After the LLM produces the
monologue, run an INDEPENDENT fact-check pass (different model —
Opus, separate weights = independent take) against each utterance's
specific factual claims. The fact-checker rates confidence and
proposes hedges or rewrites for anything it can't fully vouch for.

Tests whether we can keep the magic of grounded LLM narration
while shipping a credibility guardrail — especially important for
high-stakes vibes like true crime where a false claim about a
named person or alleged crime is a defamation risk.

Pipeline:
  1. Polyline + town list
  2. Sonnet: characterize the route
  3. Sonnet: monologue + stops (with the user's vibe overlay)
  4. Opus: fact-check each utterance. For each one:
        - HIGH: well-documented; ship as-is
        - MEDIUM: probably true; ship hedged ("there's a story that...")
        - LOW: probably fabricated; ship a rewrite that drops the
          uncertain detail, or omit entirely
  5. Verify stops via Mapbox Search Box
  6. Print original / fact-check verdict / final shippable version

Run from anywhere:
    python3 backend/scripts/spike_factcheck_monologue.py [route] [vibe]
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
VIBE_OVERLAY = sys.argv[2] if len(sys.argv) > 2 else (
    "true crime stories — historical or recent crimes, mysteries, "
    "disappearances, dark moments that happened along this corridor. "
    "Stop suggestions should be either bars with good margaritas, or "
    "antique/vintage shops worth browsing."
)
_R = ROUTES[ROUTE_KEY]
ORIGIN = _R["origin"]
DEST = _R["dest"]
ROUTE_LABEL = _R["label"]
NUM_UTTERANCES = 8
NUM_STOPS = 4
ON_ROUTE_MAX_MILES = 5.0
AUTHOR_MODEL = "claude-sonnet-4-6"
CHECKER_MODEL = "claude-opus-4-7"


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

YOUR VOICE/INTEREST TILT FOR THIS DRIVE: {vibe}

Now write TWO things in one response, as a single JSON object:

1. A "monologue" of {n_utt} utterances. Each: 25-40 words, conversational
   ("friend in the passenger seat" voice, NOT tour-guide), anchored to
   a town or landmark along the route, building as a connected narrative.

2. A "stops" list of {n_stops} specific real places. Each: tied via
   "tied_to_utterance" to one of your utterances.

CRITICAL — for the vibe given:
- Only state facts you're highly confident are TRUE. If a story is
  apocryphal or you're unsure, either skip it or phrase it as "there's
  a story that..." rather than asserting it.
- Especially for the true-crime/historical-claim category: no inventing
  victim names, perpetrator names, or specific dates unless you are
  absolutely sure. Better to skip a detail than fabricate one.

Format (return EXACTLY this shape, no preamble, no markdown fences):

{{
  "monologue": [
    {{"i": 1, "anchor": "town", "utterance": "..."}}
  ],
  "stops": [
    {{"name": "...", "town": "...", "tied_to_utterance": 1, "reason": "..."}}
  ]
}}
"""


FACTCHECK_PROMPT = """You are a senior fact-checker for a publication
that's about to broadcast these audio narration snippets to road-trip
listeners. Your job is to flag anything that should not ship as-is.

For each utterance below, output:
- "confidence": HIGH if you would stake your reputation on every
  factual claim in it, MEDIUM if the gist is right but specific
  details (names, dates, exact counts) might be wrong, LOW if you
  suspect specific claims are fabricated or seriously inaccurate.
- "concerns": list of specific things you're worried about (empty if HIGH).
- "shippable_version": the rewritten utterance.
  - For HIGH: return it unchanged.
  - For MEDIUM: rewrite to hedge uncertain claims ("there's a story
    that...", "supposedly", remove specific numbers/names you can't
    verify, etc.) while keeping the spirit and voice.
  - For LOW: rewrite to remove the dubious claim entirely. Keep what's
    true. If almost nothing is verifiable, return an empty string and
    we'll drop the utterance.

IMPORTANT:
- Do not be over-cautious. Real, well-documented true crimes (Zodiac
  Killer, Golden State Killer / Joseph DeAngelo, the 1980 Harvey's
  Resort bombing) are HIGH-confidence; flag them HIGH.
- Be specific about WHY you're uncertain. "Can't find anyone named X
  matching this description" is more useful than "this seems suspicious."

Utterances to check:
{utterance_list}

Return ONLY a JSON array, same length as utterances, in order:
[
  {{"i": 1, "confidence": "HIGH|MEDIUM|LOW", "concerns": [...], "shippable_version": "..."}}
]
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


def _parse_json(text: str):
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
        print(f"  Raw head: {text[:400]}")
        return None


async def reverse_geocode_locality(client, lat, lng, token):
    url = f"https://api.mapbox.com/geocoding/v5/mapbox.places/{lng},{lat}.json"
    params = {"types": "place", "access_token": token, "limit": 1}
    r = await client.get(url, params=params, timeout=15.0)
    r.raise_for_status()
    feats = r.json().get("features") or []
    return feats[0].get("text") if feats else None


def _wrap(text, indent="     ", width=76):
    line = ""
    out_lines = []
    for w in text.split():
        if len(line) + len(w) > width:
            out_lines.append(f"{indent}{line}")
            line = w
        else:
            line = (line + " " + w).strip()
    if line:
        out_lines.append(f"{indent}{line}")
    return "\n".join(out_lines)


async def main() -> int:
    load_dotenv(BACKEND_DIR / ".env")
    mbx = os.getenv("MAPBOX_ACCESS_TOKEN")
    ant_key = os.getenv("ANTHROPIC_API_KEY")
    if not mbx or not ant_key:
        print("Need MAPBOX_ACCESS_TOKEN + ANTHROPIC_API_KEY")
        return 1

    print(f"Spike: monologue + fact-check pass")
    print(f"Route   : {ROUTE_LABEL}")
    print(f"Vibe    : {VIBE_OVERLAY[:80]}...")
    print(f"Author  : {AUTHOR_MODEL}")
    print(f"Checker : {CHECKER_MODEL}")
    print("=" * 76)

    # Polyline + towns
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

    # STAGE 1: Characterize
    print("\n=== STAGE 1: Characterization ===")
    char_resp = await anth.messages.create(
        model=AUTHOR_MODEL,
        max_tokens=800,
        messages=[{"role": "user", "content": CHARACTERIZE_PROMPT.format(route=ROUTE_LABEL)}],
    )
    characterization = char_resp.content[0].text.strip()
    print(characterization[:400] + ("..." if len(characterization) > 400 else ""))

    # STAGE 2: Monologue + stops
    print("\n=== STAGE 2: Author monologue + stops ===")
    combined_resp = await anth.messages.create(
        model=AUTHOR_MODEL,
        max_tokens=2800,
        messages=[{"role": "user", "content": COMBINED_PROMPT.format(
            characterization=characterization,
            town_list=", ".join(towns),
            vibe=VIBE_OVERLAY,
            n_utt=NUM_UTTERANCES,
            n_stops=NUM_STOPS,
        )}],
    )
    parsed = _parse_json(combined_resp.content[0].text)
    if not parsed:
        return 1
    monologue = parsed.get("monologue") or []
    stops = parsed.get("stops") or []
    print(f"Author produced {len(monologue)} utterances, {len(stops)} stops")

    # STAGE 3: Fact-check
    print(f"\n=== STAGE 3: Fact-check pass ({CHECKER_MODEL}) ===")
    utterance_list = "\n".join(
        f"[{u['i']}] (anchor: {u.get('anchor','?')}) {u['utterance']}"
        for u in monologue
    )
    check_resp = await anth.messages.create(
        model=CHECKER_MODEL,
        max_tokens=3000,
        messages=[{"role": "user", "content": FACTCHECK_PROMPT.format(
            utterance_list=utterance_list,
        )}],
    )
    checks = _parse_json(check_resp.content[0].text) or []
    if not checks:
        print("Fact-check returned no parseable JSON")
        return 1

    # Index by i
    checks_by_i = {c.get("i"): c for c in checks}

    # Render side-by-side
    print("\n" + "=" * 76)
    print("RESULTS — Original | Fact-Check Verdict | Shippable Version")
    print("=" * 76)

    counts = {"HIGH": 0, "MEDIUM": 0, "LOW": 0, "UNCHECKED": 0}
    for u in monologue:
        i = u["i"]
        c = checks_by_i.get(i)
        print(f"\n[{i:2d}] @ {u.get('anchor','?')}")
        print(f"  ORIGINAL:")
        print(_wrap(u["utterance"], indent="    "))
        if not c:
            print(f"  VERDICT: (no check returned)")
            counts["UNCHECKED"] += 1
            continue
        conf = c.get("confidence", "?")
        counts[conf] = counts.get(conf, 0) + 1
        mark = {"HIGH": "✓", "MEDIUM": "~", "LOW": "✗"}.get(conf, "?")
        print(f"  VERDICT: {mark} {conf}")
        for concern in c.get("concerns") or []:
            print(f"    - {concern}")
        ship = c.get("shippable_version") or ""
        if conf == "HIGH":
            print(f"  SHIP AS-IS")
        elif ship:
            print(f"  SHIPPABLE VERSION:")
            print(_wrap(ship, indent="    "))
        else:
            print(f"  RECOMMEND DROP (no shippable version offered)")

    print("\n" + "=" * 76)
    print("SUMMARY")
    print("=" * 76)
    total = sum(counts.values())
    for conf in ["HIGH", "MEDIUM", "LOW", "UNCHECKED"]:
        if counts.get(conf):
            print(f"  {conf:10s}: {counts[conf]:2d} / {total}")
    print()
    print("Eyeball: did the fact-checker catch claims you weren't sure about?")
    print("Are the hedged versions still listenable, or do they kill the magic?")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
