#!/usr/bin/env python3
"""Spike: drive-narration monologue (companion mode).

Different output shape than the stop-suggester spikes. Instead of
"here's a list of stops to pick from," this asks the LLM to write
the actual sequence of utterances a companion would speak DURING
the drive — short, conversational, each tied to a specific point
on the route.

Output: 8-12 narration cards, each ~25-40 words, sequenced from
origin to destination. The LLM weaves the route's character into
the cadence — the same characterization step from spike_route_
narrative.py, but the *output* is dialogue, not a list.

This is the closest spike to the actual product surface (the
companion that whispers facts as you drive). The narration_card
widget already exists; this is asking what would FILL it.

Pipeline:
  1. Get the polyline + town list (reverse-geocode samples).
  2. Stage 1 LLM: characterize the route (same prompt as the
     other spike — reused for consistency).
  3. Stage 2 LLM: given the characterization AND the actual town
     list, write a monologue of 8-12 utterances each tied to a
     specific town or landmark. Conversational tone, ~30 words
     each, narrative arc across the drive.
  4. Verify each trigger location is actually on the polyline.
  5. Print the monologue as the companion would deliver it.

Run from anywhere:
    python3 backend/scripts/spike_drive_monologue.py [route-key]
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
# Optional second arg: vibe overlay (the companion's interest tilt).
VIBE_OVERLAY = sys.argv[2] if len(sys.argv) > 2 else None
_R = ROUTES[ROUTE_KEY]
ORIGIN = _R["origin"]
DEST = _R["dest"]
ROUTE_LABEL = _R["label"]
NUM_UTTERANCES = 10
SAMPLE_STRIDE_MILES = 25.0
LLM_MODEL = "claude-sonnet-4-6"


CHARACTERIZE_PROMPT = """You are a travel writer who knows American
road trips intimately. In 3-4 short paragraphs, characterize this
route as a place with identity: its history, the story arc of the
drive, any themes a traveler might follow. Stay grounded — only
mention places, events, themes you're confident are real.

Route: {route}
"""


MONOLOGUE_PROMPT = """You are a road-trip companion riding along with
the driver. You just wrote the characterization below.

ROUTE CHARACTERIZATION:
{characterization}

TOWNS THE ROUTE PASSES THROUGH (in order):
{town_list}
{vibe_section}
Now write {n} short narration utterances that you'd actually speak
during the drive. Each utterance:
- Is 25-40 words. Aim for ~15 seconds of speech.
- Sounds like a friend in the passenger seat, NOT a tour guide
  or Wikipedia entry. Conversational, specific, occasionally
  intimate.
- Is anchored to one of the towns or to a specific landmark you
  know is along that stretch.
- Builds on the previous ones — the sequence should feel like a
  thread through the drive, not 10 disconnected facts.
- Avoids forcing every utterance to be educational. Some can
  notice landscape, weather, vibe. Quiet moments are okay.
- Never invents. If you're not sure, skip rather than make up.

Return ONLY a JSON array, no preamble or markdown fences:
[
  {{"anchor": "<town or landmark>", "utterance": "..."}},
  ...
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


async def reverse_geocode_locality(client, lat, lng, token):
    url = f"https://api.mapbox.com/geocoding/v5/mapbox.places/{lng},{lat}.json"
    params = {"types": "place", "access_token": token, "limit": 1}
    r = await client.get(url, params=params, timeout=15.0)
    r.raise_for_status()
    feats = r.json().get("features") or []
    if not feats:
        return None
    return feats[0].get("text")


def _parse_json_array(text: str) -> list[dict]:
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
        print(f"  Raw text head: {text[:300]}")
        return []


async def main() -> int:
    load_dotenv(BACKEND_DIR / ".env")
    mbx = os.getenv("MAPBOX_ACCESS_TOKEN")
    ant_key = os.getenv("ANTHROPIC_API_KEY")
    if not mbx or not ant_key:
        print("Need MAPBOX_ACCESS_TOKEN + ANTHROPIC_API_KEY")
        return 1

    print(f"Spike: drive-narration monologue")
    print(f"Route : {ROUTE_LABEL}")
    print(f"Vibe  : {VIBE_OVERLAY or '(none)'}")
    print(f"Model : {LLM_MODEL}")
    print("=" * 72)

    # 1. Polyline + towns
    polyline = await fetch_polyline(ORIGIN[0], ORIGIN[1], DEST[0], DEST[1])
    if not polyline:
        return 1
    coords = decode_polyline(polyline)
    samples = _stride_sample(coords, SAMPLE_STRIDE_MILES)
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
    print(f"Towns the route passes through ({len(towns)}):")
    for t in towns:
        print(f"  - {t}")

    # 2. Characterize
    anth = AsyncAnthropic(api_key=ant_key)
    print("\n=== STAGE 1: Route characterization ===")
    char_resp = await anth.messages.create(
        model=LLM_MODEL,
        max_tokens=900,
        messages=[{"role": "user", "content": CHARACTERIZE_PROMPT.format(route=ROUTE_LABEL)}],
    )
    characterization = char_resp.content[0].text.strip()
    print(characterization)

    # 3. Generate monologue
    print(f"\n=== STAGE 2: Drive monologue ({NUM_UTTERANCES} utterances) ===")
    vibe_section = (
        f"\nYOUR VOICE/INTEREST TILT FOR THIS DRIVE: {VIBE_OVERLAY}\n"
        if VIBE_OVERLAY else ""
    )
    mono_resp = await anth.messages.create(
        model=LLM_MODEL,
        max_tokens=2000,
        messages=[{"role": "user", "content": MONOLOGUE_PROMPT.format(
            characterization=characterization,
            town_list=", ".join(towns),
            vibe_section=vibe_section,
            n=NUM_UTTERANCES,
        )}],
    )
    utterances = _parse_json_array(mono_resp.content[0].text)

    if not utterances:
        print("(no utterances parsed)")
        return 1

    # 4. Render as a script the companion would speak
    print()
    for i, u in enumerate(utterances, 1):
        anchor = u.get("anchor") or "?"
        anchor_on_route = anchor.lower() in " ".join(towns).lower()
        mark = "✓" if anchor_on_route else "?"
        words = len((u.get("utterance") or "").split())
        print(f"[{i:2d}] {mark} @ {anchor}  ({words} words)")
        # Soft-wrap to ~80 col for readability
        utt = u.get("utterance") or ""
        line = ""
        for w in utt.split():
            if len(line) + len(w) > 78:
                print(f"     {line}")
                line = w
            else:
                line = (line + " " + w).strip()
        if line:
            print(f"     {line}")
        print()

    # 5. Summary
    anchored = sum(
        1 for u in utterances
        if (u.get("anchor") or "").lower() in " ".join(towns).lower()
    )
    avg_words = (
        sum(len((u.get("utterance") or "").split()) for u in utterances) / len(utterances)
        if utterances else 0
    )
    print("=" * 72)
    print(f"Anchored to a real town on route: {anchored}/{len(utterances)}")
    print(f"Avg utterance length: {avg_words:.0f} words (~{int(avg_words * 0.4)}s of speech)")
    print()
    print("Eyeball: does this sound like a friend in the passenger seat?")
    print("Would you want this playing during the drive? Are the gaps")
    print("between utterances natural?")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
