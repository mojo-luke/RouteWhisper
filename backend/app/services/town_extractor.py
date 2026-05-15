"""
Town extractor — polyline → ordered list of towns the route passes through.

Used by the monologue pipeline as stage 1. The monologue's utterances
are anchored to these town names, and the on-device GPS-triggering
logic uses the same list to fire utterances when the user enters
each town.

The approach is the same as the spike (spike_drive_monologue.py):
  1. Decode the polyline.
  2. Sample it every ~25 miles.
  3. Reverse-geocode each sample via Mapbox Geocoding `place` type.
  4. Dedupe by name, preserve along-route order.

This isn't free-form Mapbox Tilequery against `place` tiles (which
would be cleaner and respect polygon boundaries) because we don't
yet have Tilequery wired up. Sampling + dedupe is fine for v1; the
polygon upgrade is in the broader plan as a refactor.
"""

from __future__ import annotations

import asyncio
import logging
import os
from typing import Optional

import httpx
from pydantic import BaseModel

from app.utils.polyline import (
    calculate_distance_miles,
    decode_polyline,
)

logger = logging.getLogger(__name__)

# Spec'd in companion-monologue-v1-plan.md. Tuned to give ~8-10 towns
# on a typical 4-hour rural route. Adjustable per-route in v1.5 once
# we want to support short trips that need finer sampling.
DEFAULT_STRIDE_MILES = 25.0

_GEOCODING_URL = "https://api.mapbox.com/geocoding/v5/mapbox.places/{lng},{lat}.json"


class Town(BaseModel):
    """One named locality along a route, in along-route order."""
    name: str
    lat: float
    lng: float


async def extract_towns(
    polyline: str,
    *,
    stride_miles: float = DEFAULT_STRIDE_MILES,
    client: Optional[httpx.AsyncClient] = None,
) -> list[Town]:
    """Decode the polyline, sample, reverse-geocode each sample to a
    locality, dedupe by name preserving order.

    Returns an empty list on any catastrophic failure (no Mapbox
    token, unreachable network). Caller should treat the empty list
    as "no monologue authoring this trip" rather than crashing.
    """
    token = os.getenv("MAPBOX_ACCESS_TOKEN")
    if not token:
        logger.warning("town_extractor: no MAPBOX_ACCESS_TOKEN; returning empty")
        return []

    coords = decode_polyline(polyline)
    if not coords:
        return []

    samples = _stride_sample(coords, stride_miles=stride_miles)
    logger.info(
        "town_extractor: %d coords → %d samples (%smi stride)",
        len(coords), len(samples), stride_miles,
    )

    own_client = client is None
    c = client or httpx.AsyncClient(timeout=15.0)
    try:
        # Bounded concurrency — Mapbox geocoding has a generous per-second
        # quota but bursts get throttled.
        sem = asyncio.Semaphore(3)

        async def _one(point: tuple[float, float]) -> Optional[dict]:
            async with sem:
                return await _reverse_geocode_place(c, point[0], point[1], token)

        loc_results = await asyncio.gather(*[_one(p) for p in samples])
    finally:
        if own_client:
            await c.aclose()

    # Dedupe by name; preserve along-route order. The first sample
    # to hit a given town wins (the entry of the route into that town).
    seen: set[str] = set()
    out: list[Town] = []
    for loc in loc_results:
        if not loc:
            continue
        name = loc["name"]
        if name in seen:
            continue
        seen.add(name)
        out.append(Town(name=name, lat=loc["lat"], lng=loc["lng"]))
    logger.info("town_extractor: %d unique towns", len(out))
    return out


async def _reverse_geocode_place(
    client: httpx.AsyncClient,
    lat: float,
    lng: float,
    token: str,
) -> Optional[dict]:
    """One reverse-geocode call. `types=place` returns the locality
    (city/town/village) containing the coordinate. Returns None on any
    error so failed samples just get dropped from the dedupe pass."""
    url = _GEOCODING_URL.format(lng=lng, lat=lat)
    params = {"types": "place", "access_token": token, "limit": 1}
    try:
        r = await client.get(url, params=params)
        r.raise_for_status()
        feats = r.json().get("features") or []
        if not feats:
            return None
        f = feats[0]
        return {
            "name": f.get("text"),
            "lng": f["center"][0],
            "lat": f["center"][1],
        }
    except Exception as e:
        logger.warning("town_extractor: geocode failed at %s,%s: %r", lat, lng, e)
        return None


def _stride_sample(
    coords: list[tuple[float, float]],
    *,
    stride_miles: float,
) -> list[tuple[float, float]]:
    """Walk consecutive coords summing haversine distance; emit a sample
    every time cumulative distance crosses the stride. Always include
    first and last points so the route's start and end towns get
    captured. Deterministic for a given polyline."""
    if not coords:
        return []
    if len(coords) == 1:
        return [coords[0]]
    samples: list[tuple[float, float]] = [coords[0]]
    cumulative = 0.0
    for i in range(1, len(coords)):
        cumulative += calculate_distance_miles(coords[i - 1], coords[i])
        if cumulative >= stride_miles:
            samples.append(coords[i])
            cumulative = 0.0
    if samples[-1] != coords[-1]:
        samples.append(coords[-1])
    return samples
