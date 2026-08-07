"""
Server-side Mapbox Directions client.

Used by the trip-prewarm flow to compute a polyline at trip-create
time, so background fact prep can run against the same geometry the
device will eventually navigate. The native Mapbox Navigation SDK
computes its own polyline at drive-time too; the two are usually
identical or near-identical for a fresh route (minor differences
from real-time traffic don't affect the cache — POIContent is
keyed by pageid globally, not by polyline).
"""

from __future__ import annotations

import logging
import os
from typing import Optional

import httpx
from pydantic import BaseModel

logger = logging.getLogger(__name__)


_DIRECTIONS_URL = (
    "https://api.mapbox.com/directions/v5/mapbox/driving/"
)


class RouteGeometry(BaseModel):
    """Geometry + real trip stats from one Mapbox Directions call."""

    polyline: str  # precision-6, same as fetch_polyline returns
    duration_seconds: float  # driving profile, no live traffic
    distance_meters: float

    @property
    def duration_minutes(self) -> int:
        return round(self.duration_seconds / 60)

    @property
    def distance_miles(self) -> float:
        return self.distance_meters / 1609.344


async def fetch_route(
    origin_lat: float,
    origin_lng: float,
    dest_lat: float,
    dest_lng: float,
    *,
    client: Optional[httpx.AsyncClient] = None,
) -> Optional[RouteGeometry]:
    """Return the precision-6 encoded polyline plus duration/distance for
    the driving route from origin to destination, or None on failure. We
    always use precision 6 to match what the Mapbox Navigation SDK emits
    on the device — this keeps the polyline cache key identical between
    pre-warm and trip-start.
    """
    token = os.getenv("MAPBOX_ACCESS_TOKEN")
    if not token:
        logger.warning("mapbox_directions: no MAPBOX_ACCESS_TOKEN; skipping")
        return None

    url = f"{_DIRECTIONS_URL}{origin_lng},{origin_lat};{dest_lng},{dest_lat}"
    params = {
        "access_token": token,
        "geometries": "polyline6",
        "overview": "full",
        # We don't need turn-by-turn directions for prefetch — just
        # the geometry. Skipping `steps` halves the response size.
        "steps": "false",
    }
    own_client = client is None
    c = client or httpx.AsyncClient(timeout=20.0)
    try:
        response = await c.get(url, params=params)
        response.raise_for_status()
        data = response.json()
        routes = data.get("routes") or []
        if not routes:
            logger.warning("mapbox_directions: no routes for %s,%s → %s,%s",
                           origin_lat, origin_lng, dest_lat, dest_lng)
            return None
        route = routes[0]
        geometry = route.get("geometry")
        if not geometry:
            return None
        return RouteGeometry(
            polyline=geometry,
            duration_seconds=route.get("duration", 0.0),
            distance_meters=route.get("distance", 0.0),
        )
    except httpx.HTTPError as e:
        logger.warning("mapbox_directions HTTP error: %s", e)
        return None
    except Exception as e:
        logger.error("mapbox_directions unexpected error: %s", e)
        return None
    finally:
        if own_client:
            await c.aclose()


async def fetch_polyline(
    origin_lat: float,
    origin_lng: float,
    dest_lat: float,
    dest_lng: float,
    *,
    client: Optional[httpx.AsyncClient] = None,
) -> Optional[str]:
    """Backwards-compatible wrapper over fetch_route for callers that only
    need the geometry."""
    route = await fetch_route(
        origin_lat, origin_lng, dest_lat, dest_lng, client=client
    )
    return route.polyline if route else None
