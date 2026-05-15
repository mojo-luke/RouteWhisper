#!/usr/bin/env python3
"""Spike: end-to-end vibe-aware stop suggester.

Goal: does the architecture we sketched actually produce good picks?

Pipeline (all on free-tier APIs we already have keys for):
  1. SF -> Tahoe driving polyline (Mapbox Directions)
  2. Sample polyline ~every N miles, reverse-geocode each
     -> unique town names the route passes through
  3. For each town: Mapbox Search Box /category=restaurant
     -> top ~15 restaurant candidates with name + category + address
  4. LLM (Claude Haiku): given the vibe query and the candidate list,
     pick the top 3 that match the vibe, with a one-line reason each.
     Allowed to say "no good matches in this town" — we don't want
     forced picks.
  5. Print per-town picks. Eyeball quality.

If the picks are good with just Mapbox POI names + categories, we've
proven the architecture is real without needing Brave Search or
Google Places reviews. If the picks are weak, we know exactly which
signal layer to invest in next.

Run from anywhere:
    python3 backend/scripts/spike_stop_suggester.py
"""

from __future__ import annotations

import asyncio
import os
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

# ---- Spike inputs ------------------------------------------------------
SF = (37.7749, -122.4194)              # San Francisco
TAHOE = (38.9399, -119.9772)           # South Lake Tahoe
VIBE_QUERY = (
    "quirky roadside attraction, weird little museum, photo-worthy "
    "oddity, or historic curiosity — the kind of thing you'd brag about "
    "having stopped at, not a generic city park"
)
SAMPLE_STRIDE_MILES = 25.0
# Multiple categories merged + deduped to give the LLM a broader
# candidate set for "things to see" vibes.
CATEGORIES = ["tourist_attraction", "museum", "historic_site"]
# Hint passed to Wikipedia town lookup (most towns we sample on
# SF->Tahoe are in CA; if we expand routes, swap this per-route).
STATE_HINT = "California"
PER_TOWN_LIMIT = 15
TOP_PICKS_PER_TOWN = 3
LLM_MODEL = "claude-haiku-4-5"


# ---- Helpers -----------------------------------------------------------
def stride_sample(coords, stride_miles):
    if not coords:
        return []
    samples = [coords[0]]
    cumulative = 0.0
    for i in range(1, len(coords)):
        cumulative += calculate_distance_miles(coords[i - 1], coords[i])
        if cumulative >= stride_miles:
            samples.append(coords[i])
            cumulative = 0.0
    if samples[-1] != coords[-1]:
        samples.append(coords[-1])
    return samples


async def reverse_geocode_locality(client, lat, lng, token):
    """Return locality info for a coord, or None.

    Uses Mapbox Geocoding (legacy v5) with types=place — these are
    cities/towns/villages. We deliberately want the human-readable
    'town' even when the precise sample lands on a rural road.
    """
    url = f"https://api.mapbox.com/geocoding/v5/mapbox.places/{lng},{lat}.json"
    params = {"types": "place", "access_token": token, "limit": 1}
    r = await client.get(url, params=params, timeout=15.0)
    r.raise_for_status()
    feats = r.json().get("features") or []
    if not feats:
        return None
    f = feats[0]
    return {
        "name": f.get("text"),
        "full": f.get("place_name"),
        "lng": f["center"][0],
        "lat": f["center"][1],
    }


async def fetch_town_context(client, town, state_hint):
    """Fetch a short summary of the town from Wikipedia.

    Uses the REST summary endpoint — clean JSON, no MediaWiki query
    fiddling. Returns the first ~400 chars of the article extract,
    or None if the article doesn't exist (e.g., 404 for an unusual
    town name).
    """
    # Wikipedia REST API requires a User-Agent; httpx defaults are
    # rejected by their CDN edge. Use a descriptive one.
    headers = {"User-Agent": "RouteWhisperSpike/0.1 (research)"}
    # Try disambiguated form first, then bare town name.
    titles_to_try = [
        f"{town},_{state_hint}".replace(" ", "_"),
        town.replace(" ", "_"),
    ]
    for title in titles_to_try:
        url = f"https://en.wikipedia.org/api/rest_v1/page/summary/{title}"
        try:
            r = await client.get(url, timeout=10.0, headers=headers)
            if r.status_code != 200:
                continue
            data = r.json()
            # Disambiguation pages have type=disambiguation; skip them.
            if data.get("type") == "disambiguation":
                continue
            extract = (data.get("extract") or "").strip()
            if extract:
                return extract[:500]
        except Exception:
            continue
    return None


async def search_one_category(client, category, lat, lng, token, *, limit):
    """Mapbox Search Box /category={category} around a point."""
    url = f"https://api.mapbox.com/search/searchbox/v1/category/{category}"
    params = {
        "proximity": f"{lng},{lat}",
        "limit": limit,
        "access_token": token,
    }
    r = await client.get(url, params=params, timeout=15.0)
    r.raise_for_status()
    feats = r.json().get("features") or []
    out = []
    for f in feats:
        p = f.get("properties") or {}
        coords = (f.get("geometry") or {}).get("coordinates") or []
        out.append({
            "name": p.get("name") or "?",
            "category": ", ".join(p.get("poi_category") or []),
            "address": p.get("place_formatted") or "",
            "lat": coords[1] if len(coords) >= 2 else None,
            "lng": coords[0] if len(coords) >= 1 else None,
        })
    return out


# Bound concurrency across all category searches — Mapbox 429s
# easily when we burst 27 requests for a 9-town × 3-category sweep.
_search_sem = asyncio.Semaphore(2)


async def search_pois_near(client, categories, lat, lng, token, *, limit):
    """Query categories with bounded concurrency; merge + dedupe by name."""
    async def _one(cat):
        async with _search_sem:
            await asyncio.sleep(0.15)  # small jitter between bursts
            return await search_one_category(client, cat, lat, lng, token, limit=limit)
    results = await asyncio.gather(*[_one(c) for c in categories])
    seen = set()
    merged = []
    for batch in results:
        for poi in batch:
            key = poi["name"].lower().strip()
            if key in seen:
                continue
            seen.add(key)
            merged.append(poi)
    return merged


async def llm_pick_for_vibe(town, town_context, candidates, vibe_query, top_k, client):
    """Ask Claude Haiku to pick top-k candidates matching the vibe."""
    if not candidates:
        return "(no candidates)"
    listing = "\n".join(
        f"{i+1}. {c['name']}  [{c['category'] or 'uncategorized'}]"
        for i, c in enumerate(candidates)
    )
    context_section = (
        f"\nAbout {town} (from Wikipedia):\n{town_context}\n"
        if town_context else ""
    )
    prompt = f"""You are helping a road tripper choose stops along their route.

Town: {town}{context_section}
Vibe they want: {vibe_query}

Candidates (Mapbox POI data — names and categories only, no reviews):
{listing}

Pick the TOP {top_k} candidates that best match the vibe. For each,
give a one-line reason. You only have names + categories — be honest
about uncertainty ("name suggests..." / "could fit if..."). When the
town context adds useful signal (e.g., a Gold Rush town might have
historic-feeling places), use it; otherwise ignore it.

If NONE of the candidates seem to match the vibe, output exactly:

  No good matches in this town.

Otherwise, output picks in this format (no preamble, no numbering):

Pick: <name>
Reason: <one short line>
"""
    resp = await client.messages.create(
        model=LLM_MODEL,
        max_tokens=500,
        messages=[{"role": "user", "content": prompt}],
    )
    return resp.content[0].text.strip()


# ---- Main --------------------------------------------------------------
async def main() -> int:
    load_dotenv(BACKEND_DIR / ".env")
    mbx = os.getenv("MAPBOX_ACCESS_TOKEN")
    ant_key = os.getenv("ANTHROPIC_API_KEY")
    if not mbx:
        print("ERROR: MAPBOX_ACCESS_TOKEN missing from backend/.env")
        return 1
    if not ant_key:
        print("ERROR: ANTHROPIC_API_KEY missing from backend/.env")
        return 1

    print(f"Spike: SF {SF} -> Tahoe {TAHOE}")
    print(f"Vibe : {VIBE_QUERY!r}")
    print("=" * 72)

    # 1. Polyline
    polyline = await fetch_polyline(SF[0], SF[1], TAHOE[0], TAHOE[1])
    if not polyline:
        print("ERROR: no polyline from Mapbox Directions")
        return 1
    coords = decode_polyline(polyline)
    samples = stride_sample(coords, SAMPLE_STRIDE_MILES)
    print(f"Polyline: {len(coords)} coords, sampled {len(samples)} at "
          f"{SAMPLE_STRIDE_MILES}mi stride")

    # 2. Reverse-geocode -> towns
    anth_client = AsyncAnthropic(api_key=ant_key)
    async with httpx.AsyncClient() as http:
        sem = asyncio.Semaphore(5)

        async def _geo(p):
            async with sem:
                try:
                    return await reverse_geocode_locality(http, p[0], p[1], mbx)
                except Exception as e:
                    print(f"  geo fail at {p}: {e!r}")
                    return None

        locs = await asyncio.gather(*[_geo(p) for p in samples])

        # Dedupe by town name, preserve along-route order
        towns: "OrderedDict[str, dict]" = OrderedDict()
        for loc in locs:
            if loc and loc.get("name") and loc["name"] not in towns:
                towns[loc["name"]] = loc

        print(f"\nUnique towns the route passes through ({len(towns)}):")
        for n, loc in towns.items():
            print(f"  - {n:30s}  ({loc['lat']:.3f}, {loc['lng']:.3f})")

        # 3. Mapbox /category per town
        cat_label = ",".join(CATEGORIES) if isinstance(CATEGORIES, list) else CATEGORIES
        print(f"\n=== POI search per town (Mapbox categories: {cat_label}) ===")
        town_candidates: dict[str, list] = {}
        for name, loc in towns.items():
            cands = await search_pois_near(
                http, CATEGORIES, loc["lat"], loc["lng"], mbx, limit=PER_TOWN_LIMIT,
            )
            town_candidates[name] = cands
            print(f"  {name:30s} -> {len(cands)} candidates (merged across categories)")

        # 3b. Per-town Wikipedia context (free, parallel)
        print(f"\n=== Wikipedia town context ===")
        town_ctx: dict[str, str | None] = {}
        ctx_results = await asyncio.gather(*[
            fetch_town_context(http, name, STATE_HINT) for name in towns
        ])
        for name, ctx in zip(towns, ctx_results):
            town_ctx[name] = ctx
            mark = "✓" if ctx else "—"
            print(f"  {mark} {name}{(' (' + str(len(ctx)) + ' chars)') if ctx else ' (no article)'}")

    # 4. LLM picks per town
    print(f"\n=== LLM picks (Claude Haiku, top {TOP_PICKS_PER_TOWN}/town) ===")
    for name, cands in town_candidates.items():
        print(f"\n--- {name} ---")
        if not cands:
            print("  (no candidates)")
            continue
        try:
            out = await llm_pick_for_vibe(
                name, town_ctx.get(name), cands,
                VIBE_QUERY, TOP_PICKS_PER_TOWN, anth_client,
            )
        except Exception as e:
            print(f"  LLM error: {e!r}")
            continue
        for line in out.splitlines():
            print(f"  {line}")

    print("\n" + "=" * 72)
    print("Done. Eyeball the picks per town. Are these the kinds of places")
    print("you'd actually want to stop at on this route?")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
