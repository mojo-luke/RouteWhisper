#!/usr/bin/env python3
"""
Spike: Foursquare Places API along SF -> Lake Tahoe.

Goal: figure out whether Foursquare can be the "stop suggester" data
layer behind the trip-planning canvas. Wikipedia answers "what's
interesting to *hear about* here." Foursquare needs to answer
"what's actually worth *stopping at*."

What this script does:
  1. Asks Mapbox for the real driving polyline (same code path our
     trip-prewarm uses, so the sampling matches production).
  2. Samples points every N miles along the polyline.
  3. Queries Foursquare /v3/places/search around each sample.
  4. Dedupes by fsq_id, computes each result's actual distance from
     the route line (not the sample point).
  5. Prints density, category breakdown, top-rated picks, and a
     "what does the long tail look like" sample so we can eyeball
     quality.

Run from anywhere; .env is loaded relative to backend/.

    python backend/scripts/spike_foursquare.py
"""

from __future__ import annotations

import asyncio
import os
import sys
from collections import Counter
from pathlib import Path

import httpx
from dotenv import load_dotenv

# Make backend/ importable so we can reuse the polyline + directions
# code paths used by the real flow.
BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_DIR))

from app.services.mapbox_directions import fetch_polyline  # noqa: E402
from app.services.wikipedia_facts import _stride_sample  # noqa: E402
from app.utils.polyline import (  # noqa: E402
    decode_polyline,
    detect_trip_scale,
    point_to_line_distance,
)


# Endpoints / route -------------------------------------------------
SF = (37.7749, -122.4194)              # SF Civic Center area
TAHOE = (38.9399, -119.9772)           # South Lake Tahoe

FSQ_URL = "https://places-api.foursquare.com/places/search"
FSQ_API_VERSION = "2025-02-05"

# Tunables ----------------------------------------------------------
STRIDE_MILES = 10.0     # one query per 10mi of route
RADIUS_M = 5000         # 5km radius around each sample
LIMIT = 50              # max per call (Foursquare cap is 50)
NEAR_MILES = 2.0        # "near the route" threshold
ON_ROUTE_MILES = 0.5    # "essentially on the route"


async def query_fsq(
    client: httpx.AsyncClient,
    lat: float,
    lng: float,
    key: str,
) -> list[dict]:
    params = {
        "ll": f"{lat},{lng}",
        "radius": RADIUS_M,
        "limit": LIMIT,
        # The default response is sparse; ask for the fields we care
        # about so we don't need a second round of detail calls.
        "fields": ",".join([
            "fsq_id",
            "name",
            "geocodes",
            "categories",
            "distance",
            "rating",
            "popularity",
            "stats",
            "hours",
            "price",
            "website",
        ]),
        "sort": "RATING",
    }
    headers = {
        "Authorization": f"Bearer {key}",
        "Accept": "application/json",
        "X-Places-Api-Version": FSQ_API_VERSION,
    }
    r = await client.get(FSQ_URL, params=params, headers=headers, timeout=20.0)
    if r.status_code != 200:
        print(f"  fsq {r.status_code}: {r.text[:200]}")
        r.raise_for_status()
    return r.json().get("results", [])


async def main() -> int:
    load_dotenv(BACKEND_DIR / ".env")
    fsq_key = os.getenv("FOURSQUARE_API_KEY")
    mbx_key = os.getenv("MAPBOX_ACCESS_TOKEN")
    if not fsq_key:
        print("ERROR: FOURSQUARE_API_KEY not set in backend/.env")
        return 1
    if not mbx_key:
        print("ERROR: MAPBOX_ACCESS_TOKEN not set in backend/.env")
        return 1

    print(f"Spike: SF {SF} -> Tahoe {TAHOE}")
    print("=" * 70)

    # 1. Real driving polyline ------------------------------------------
    polyline = await fetch_polyline(SF[0], SF[1], TAHOE[0], TAHOE[1])
    if not polyline:
        print("ERROR: no polyline from Mapbox Directions")
        return 1
    coords = decode_polyline(polyline)
    scale = detect_trip_scale(coords)
    print(f"Polyline: {len(coords)} coords, scale={scale.value}")

    # 2. Sample along the route -----------------------------------------
    samples = _stride_sample(coords, stride_miles=STRIDE_MILES)
    print(f"Sampled {len(samples)} points at {STRIDE_MILES}mi stride")
    print(f"Querying Foursquare (radius={RADIUS_M}m, limit={LIMIT})...")

    # 3. Foursquare per sample, bounded concurrency ---------------------
    all_places: dict[str, dict] = {}
    async with httpx.AsyncClient() as client:
        sem = asyncio.Semaphore(5)

        async def bounded(point: tuple[float, float]) -> list[dict]:
            async with sem:
                try:
                    return await query_fsq(client, point[0], point[1], fsq_key)
                except Exception as e:
                    print(f"  fsq fail at {point}: {e!r}")
                    return []

        batches = await asyncio.gather(*[bounded(p) for p in samples])

    # 4. Dedupe + measure distance from the route LINE ------------------
    for batch in batches:
        for p in batch:
            fid = p.get("fsq_id")
            if not fid or fid in all_places:
                continue
            geo = (p.get("geocodes") or {}).get("main") or {}
            lat = geo.get("latitude")
            lng = geo.get("longitude")
            if lat is None or lng is None:
                continue
            dist_miles = point_to_line_distance((lat, lng), coords)
            cats = p.get("categories") or []
            stats = p.get("stats") or {}
            all_places[fid] = {
                "name": p.get("name") or "(unnamed)",
                "lat": lat,
                "lng": lng,
                "categories": [c.get("name") for c in cats if c.get("name")],
                "category_ids": [c.get("id") for c in cats if c.get("id")],
                "rating": p.get("rating"),
                "popularity": p.get("popularity"),
                "total_ratings": stats.get("total_ratings"),
                "price": p.get("price"),
                "website": p.get("website"),
                "has_hours": bool(p.get("hours")),
                "distance_from_route_miles": dist_miles,
            }

    print()
    print("=" * 70)
    print(f"RESULTS: {len(all_places)} unique places returned")
    print("=" * 70)

    if not all_places:
        print("(empty result set — check API key / quota)")
        return 1

    # 5. Density buckets ------------------------------------------------
    on_route = [p for p in all_places.values()
                if p["distance_from_route_miles"] <= ON_ROUTE_MILES]
    near = [p for p in all_places.values()
            if p["distance_from_route_miles"] <= NEAR_MILES]
    print(f"  on-route (<= {ON_ROUTE_MILES}mi from line): {len(on_route)}")
    print(f"  near     (<= {NEAR_MILES}mi from line):     {len(near)}")
    print(f"  total returned (some far from route):       {len(all_places)}")

    # 6. Data completeness ---------------------------------------------
    with_rating = [p for p in all_places.values() if p["rating"] is not None]
    with_hours = [p for p in all_places.values() if p["has_hours"]]
    with_website = [p for p in all_places.values() if p["website"]]
    print()
    print("Data completeness (of all returned):")
    print(f"  with rating:  {len(with_rating):4d}  "
          f"({100*len(with_rating)/len(all_places):.0f}%)")
    print(f"  with hours:   {len(with_hours):4d}  "
          f"({100*len(with_hours)/len(all_places):.0f}%)")
    print(f"  with website: {len(with_website):4d}  "
          f"({100*len(with_website)/len(all_places):.0f}%)")

    # 7. Top categories on-route ---------------------------------------
    cat_counter: Counter[str] = Counter()
    for p in near:
        for c in p["categories"]:
            cat_counter[c] += 1
    print()
    print(f"Top 25 categories within {NEAR_MILES}mi of route:")
    for cat, n in cat_counter.most_common(25):
        print(f"  {n:4d}  {cat}")

    # 8. Top-rated near-route ------------------------------------------
    rated_near = sorted(
        [p for p in near if p["rating"] is not None],
        key=lambda p: (-p["rating"], p["distance_from_route_miles"]),
    )
    print()
    print(f"Top 20 rated picks within {NEAR_MILES}mi:")
    for p in rated_near[:20]:
        cats = ", ".join(p["categories"][:2]) if p["categories"] else "-"
        rating = p["rating"]
        print(f"  *{rating:4.1f}  {p['distance_from_route_miles']:5.2f}mi  "
              f"{p['name'][:42]:<42}  [{cats[:40]}]")

    # 9. Sample of unrated near-route (gauges the long tail) -----------
    unrated_near = [p for p in near if p["rating"] is None]
    print()
    print(f"Unrated near-route: {len(unrated_near)} of {len(near)}")
    print("  Sample of 15 (sorted by distance from route):")
    unrated_near.sort(key=lambda p: p["distance_from_route_miles"])
    for p in unrated_near[:15]:
        cats = ", ".join(p["categories"][:2]) if p["categories"] else "-"
        print(f"        {p['distance_from_route_miles']:5.2f}mi  "
              f"{p['name'][:42]:<42}  [{cats[:40]}]")

    print()
    print("=" * 70)
    print("Done. Eyeball the lists above to judge whether this data is")
    print("the foundation for a stop suggester or whether we need more.")
    print("=" * 70)
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
