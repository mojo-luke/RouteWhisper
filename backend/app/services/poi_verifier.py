"""
POI verifier for monologue stop suggestions.

The LLM proposes places by name + town. Before we surface them to a
user as "pull off here," we need to be sure the place actually
exists, is on the route, and has real coordinates. This service is
the verification layer.

Two-source strategy:
  1. Mapbox Search Box /forward — POI-aware, fast, well-curated for
     urban and chain spots. Works great for big-city restaurants,
     well-known museums, etc.
  2. OSM Overpass — free, deeper rural coverage, picks up small
     businesses and geological features Mapbox doesn't index. Falls
     back here when Mapbox can't pin a name.

Verified stops carry:
  - lat / lng
  - place_formatted (human-readable address)
  - source ("mapbox" | "osm")
  - distance_from_route_miles (filtered to <= ON_ROUTE_MAX_MILES)

Stops that neither source can verify get dropped — the rule is
"never surface a place we can't confirm exists." The LLM's narrative
references can still mention places (in the monologue text), but
verified stops are the only things that get tappable cards.

Trip-start refresh of business_status / opening_hours is a follow-up
to this slice (uses the same Mapbox/Google calls but at drive-time
rather than trip-save).
"""

from __future__ import annotations

import asyncio
import logging
import os
import re
import urllib.parse
from typing import Optional

import httpx
from pydantic import BaseModel

from app.utils.polyline import point_to_line_distance

logger = logging.getLogger(__name__)


_MAPBOX_FORWARD_URL = "https://api.mapbox.com/search/searchbox/v1/forward"
_OVERPASS_URL = "https://overpass-api.de/api/interpreter"

# Verification thresholds — match what spike_route_narrative tuned.
ON_ROUTE_MAX_MILES = 5.0  # stop is "on the route" within this many miles
OVERPASS_RADIUS_M = 5000  # ±5km around the town centroid for OSM fallback
VERIFY_CONCURRENCY = 4    # bounded async fanout — Mapbox + Overpass both rate-limit


class VerifiedStop(BaseModel):
    """A stop that survived verification. Returned by verify_stop and
    eventually persisted as part of the RouteMonologue.stops[] list."""
    # Original LLM-proposed fields preserved for downstream display.
    name: str
    town: str
    category: str
    detail_matched: Optional[str] = None
    tied_to_utterance: Optional[int] = None
    reason: Optional[str] = None
    # Verification-supplied fields.
    lat: float
    lng: float
    place_formatted: Optional[str] = None
    source: str  # "mapbox" or "osm"
    distance_from_route_miles: float


async def verify_stops(
    proposed: list[dict],
    route_coords: list[tuple[float, float]],
    towns: list[dict],
    *,
    client: Optional[httpx.AsyncClient] = None,
) -> list[dict]:
    """Verify a list of LLM-proposed stops, returning only those that
    pass: real place + on-route within ON_ROUTE_MAX_MILES.

    `towns` is the list of route towns (with lat/lng) — used to give
    the OSM Overpass fallback a search center for stops whose
    town name we have a coordinate for. Stops in towns we don't
    have in this list can still be Mapbox-verified, just not
    Overpass-verified.
    """
    if not proposed:
        return []
    if not os.getenv("MAPBOX_ACCESS_TOKEN"):
        logger.warning("poi_verifier: no MAPBOX_ACCESS_TOKEN; skipping verification")
        return []

    # Build a name → coords lookup for the OSM fallback.
    town_coords: dict[str, tuple[float, float]] = {
        t["name"].lower(): (t["lat"], t["lng"])
        for t in towns
        if t.get("name") and t.get("lat") is not None and t.get("lng") is not None
    }

    own_client = client is None
    c = client or httpx.AsyncClient(timeout=20.0)
    try:
        sem = asyncio.Semaphore(VERIFY_CONCURRENCY)

        async def _one(stop: dict) -> Optional[dict]:
            async with sem:
                return await _verify_one_stop(c, stop, route_coords, town_coords)

        results = await asyncio.gather(*[_one(s) for s in proposed])
    finally:
        if own_client:
            await c.aclose()

    verified = [r for r in results if r is not None]
    logger.info(
        "poi_verifier: verified %d / %d proposed stops",
        len(verified), len(proposed),
    )
    return verified


async def _verify_one_stop(
    client: httpx.AsyncClient,
    stop: dict,
    route_coords: list[tuple[float, float]],
    town_coords: dict[str, tuple[float, float]],
) -> Optional[dict]:
    """Try Mapbox first, fall back to Overpass, return a dict shaped
    like VerifiedStop or None if neither succeeds."""
    name = (stop.get("name") or "").strip()
    town = (stop.get("town") or "").strip()
    if not name:
        return None

    # 1) Mapbox Search Box /forward.
    mb_hit = await _mapbox_forward(client, name, town, route_coords)
    if mb_hit:
        return _shape_verified(stop, mb_hit, source="mapbox")

    # 2) Overpass fallback — requires we have the town's centroid so we
    #    can constrain the search radius.
    town_key = town.lower().split(",")[0].strip()
    # Strip parentheticals: "San Francisco (Mission District)" -> "san francisco"
    town_key = re.sub(r"\([^)]*\)", "", town_key).strip()
    centroid = town_coords.get(town_key)
    if not centroid:
        logger.info(
            "poi_verifier: no town centroid for %r; can't Overpass-fallback for %r",
            town, name,
        )
        return None

    osm_hit = await _overpass_search(client, name, centroid, route_coords)
    if osm_hit:
        return _shape_verified(stop, osm_hit, source="osm")

    return None


def _shape_verified(stop: dict, hit: dict, *, source: str) -> dict:
    return {
        "name": stop.get("name"),
        "town": stop.get("town"),
        "category": stop.get("category", ""),
        "detail_matched": stop.get("detail_matched"),
        "tied_to_utterance": stop.get("tied_to_utterance"),
        "reason": stop.get("reason"),
        "lat": hit["lat"],
        "lng": hit["lng"],
        "place_formatted": hit.get("place_formatted"),
        "source": source,
        "distance_from_route_miles": hit["distance_miles"],
    }


# ---- Mapbox -------------------------------------------------------------

async def _mapbox_forward(
    client: httpx.AsyncClient,
    name: str,
    town: str,
    route_coords: list[tuple[float, float]],
) -> Optional[dict]:
    """Try the Mapbox Search Box /forward API. Returns hit dict or None.

    Constrains to country=us + proximity to a route midpoint so the
    geocoder doesn't return "Sacramento, Spain" for "Sacramento, CA".
    Filters for name + town match in the returned place_formatted.
    Enforces on-route distance.
    """
    token = os.getenv("MAPBOX_ACCESS_TOKEN")
    if not token:
        return None
    # Clean town: drop parentheticals + the trailing ", CA"-style suffix.
    clean_town = re.sub(r"\([^)]*\)", "", town).strip().split(",")[0].strip()
    query = f"{name} {clean_town}".strip()
    # Use route midpoint for proximity bias.
    if route_coords:
        mid = route_coords[len(route_coords) // 2]
        proximity = f"{mid[1]},{mid[0]}"
    else:
        proximity = "-98,39"  # rough US centroid fallback
    params = {
        "q": query,
        "limit": 5,
        "country": "us",
        "proximity": proximity,
        "access_token": token,
    }
    try:
        r = await client.get(_MAPBOX_FORWARD_URL, params=params, timeout=15.0)
        r.raise_for_status()
        feats = r.json().get("features") or []
    except Exception as e:
        logger.info("poi_verifier: mapbox query failed for %r: %r", query, e)
        return None
    if not feats:
        return None

    # Walk features in priority order: prefer name + town match, then
    # fall back to "town in place_formatted" weak matches.
    weak: Optional[dict] = None
    for f in feats:
        p = f.get("properties") or {}
        coords = (f.get("geometry") or {}).get("coordinates") or []
        if len(coords) < 2:
            continue
        f_name = (p.get("name") or "").lower()
        place_formatted = (p.get("place_formatted") or "").lower()
        # Name match — substring either way.
        name_match = name.lower() in f_name or f_name in name.lower()
        # Town match — either the town string appears in place_formatted
        # or we're at least in California / the right state.
        town_match = bool(clean_town) and clean_town.lower() in place_formatted
        dist = point_to_line_distance((coords[1], coords[0]), route_coords)
        if dist > ON_ROUTE_MAX_MILES:
            continue
        hit = {
            "lat": coords[1],
            "lng": coords[0],
            "place_formatted": p.get("place_formatted"),
            "distance_miles": dist,
        }
        if name_match and town_match:
            return hit
        # Save the strongest "weak" hit for fallback — better than nothing.
        if town_match and weak is None:
            weak = hit
    return weak  # may be None


# ---- OSM Overpass -------------------------------------------------------

# Be polite — Overpass is a free community service.
_OSM_USER_AGENT = "RouteWhisperCompanion/0.1 (research; respects fair use)"


async def _overpass_search(
    client: httpx.AsyncClient,
    name: str,
    centroid: tuple[float, float],
    route_coords: list[tuple[float, float]],
) -> Optional[dict]:
    """Look up the place in OSM via Overpass, returning the best hit
    that's both name-matching and on-route, or None.

    Query strategy: nodes/ways with a `name` tag matching the LLM-given
    name (case-insensitive, partial), within OVERPASS_RADIUS_M of the
    town's centroid. We use the regex variant so trailing whitespace
    or minor punctuation differences still match.
    """
    # Build a regex-safe query string. Trim to first 40 chars to keep
    # the Overpass query small; OSM names are usually shorter than this.
    safe_name = re.escape(name[:60]).replace(r"\ ", " ")
    lat, lng = centroid
    # Overpass QL: nodes AND ways with matching name within radius.
    ql = (
        f'[out:json][timeout:15];'
        f'('
        f'  node["name"~"{safe_name}",i](around:{OVERPASS_RADIUS_M},{lat},{lng});'
        f'  way["name"~"{safe_name}",i](around:{OVERPASS_RADIUS_M},{lat},{lng});'
        f');'
        f'out center 5;'
    )
    try:
        r = await client.post(
            _OVERPASS_URL,
            data={"data": ql},
            headers={"User-Agent": _OSM_USER_AGENT},
            timeout=20.0,
        )
        if r.status_code != 200:
            logger.info(
                "poi_verifier: overpass HTTP %d for %r near %s",
                r.status_code, name, centroid,
            )
            return None
        elements = r.json().get("elements") or []
    except Exception as e:
        logger.info("poi_verifier: overpass query failed for %r: %r", name, e)
        return None

    if not elements:
        return None

    # Pick the closest-to-route element.
    best: Optional[dict] = None
    for el in elements:
        if el.get("type") == "node":
            elat, elng = el.get("lat"), el.get("lon")
        else:
            # `way` results include a `center` when we requested `out center`.
            ctr = el.get("center") or {}
            elat, elng = ctr.get("lat"), ctr.get("lon")
        if elat is None or elng is None:
            continue
        dist = point_to_line_distance((elat, elng), route_coords)
        if dist > ON_ROUTE_MAX_MILES:
            continue
        tags = el.get("tags") or {}
        place_formatted = _format_osm_address(tags)
        candidate = {
            "lat": elat,
            "lng": elng,
            "place_formatted": place_formatted,
            "distance_miles": dist,
        }
        if best is None or candidate["distance_miles"] < best["distance_miles"]:
            best = candidate
    return best


def _format_osm_address(tags: dict) -> str:
    """Build a readable address from OSM tags. Not all tags are present
    on all elements; we degrade gracefully to whatever we have."""
    parts = []
    if tags.get("addr:housenumber") and tags.get("addr:street"):
        parts.append(f"{tags['addr:housenumber']} {tags['addr:street']}")
    elif tags.get("addr:street"):
        parts.append(tags["addr:street"])
    if tags.get("addr:city"):
        parts.append(tags["addr:city"])
    if tags.get("addr:state"):
        parts.append(tags["addr:state"])
    if tags.get("addr:postcode"):
        parts.append(tags["addr:postcode"])
    return ", ".join(parts) if parts else (tags.get("name", "") + " (OSM)")
