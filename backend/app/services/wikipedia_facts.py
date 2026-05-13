"""
Wikipedia GeoSearch source for RouteWhisper narration.

Given a route polyline, sample points along it, call Wikipedia's
`geosearch` API around each sample, dedupe by pageid, and fetch the
full plain-text extract for each article. Returns candidate facts —
opinionated *only* about how to find them. Ranking and LLM voice
shaping happen elsewhere in the pipeline.

Why Wikipedia first? It's the broadest single source of place-keyed
stories (towns, historic roads, bridges, old buildings, battlefields,
geological features, quirky Americana). Specialty sources (Atlas
Obscura, NRHP, OSM) layer on later — keeping the v1 source surface
small lets us test whether the whisper magic works at all.

See: ~/.claude/plans/breezy-gliding-mountain.md → "Fact source"
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from typing import Optional

import httpx

from app.utils.polyline import (
    TripScale,
    calculate_distance_miles,
    decode_polyline,
    detect_trip_scale,
)

logger = logging.getLogger(__name__)


# Wikipedia API constants. We always hit the public en.wikipedia.org
# endpoint — `User-Agent` is required by Wikimedia's policy. Without
# it, requests get rate-limited or rejected outright.
_WIKI_API = "https://en.wikipedia.org/w/api.php"
_USER_AGENT = "RouteWhisper/0.1 (https://github.com/lukesimmons/routewhisper; luke@mojotech.com)"

# GeoSearch radius (meters) around each sample point. 10km gives us
# overlap between consecutive samples so we don't miss articles on the
# seam. Higher than this and per-sample result count explodes; lower
# and we miss towns just off the highway.
_GEOSEARCH_RADIUS_M = 10_000

# Per-sample result cap. The Mediawiki geosearch API allows up to 500
# but 50 is plenty for our densities — the long tail is mostly
# uninteresting buildings.
_GEOSEARCH_LIMIT = 50

# Trip-scale-aware sampling stride along the polyline (miles between
# consecutive geosearch points). Tight strides for local trips where
# the corridor is short; loose for long trips where overlap from a
# 10km radius compensates.
_STRIDE_MILES = {
    TripScale.LOCAL: 1.0,
    TripScale.REGIONAL: 5.0,
    TripScale.LONG: 15.0,
}


@dataclass
class FactCandidate:
    """A Wikipedia article keyed to a coordinate along the route.

    `extract` is the raw plain-text article body (intro + later
    sections, no markup). The LLM summarizer turns this into a
    conversational primary + follow-ups; downstream consumers should
    not speak `extract` verbatim — it's encyclopedia prose, not
    friend voice.
    """
    wikipedia_pageid: int
    title: str
    lat: float
    lng: float
    distance_from_route_miles: float
    extract: str
    url: str

    @property
    def article_length(self) -> int:
        """Heuristic for article substance. Used by fact_ranker to
        demote stub articles ("X is a town in Y County") and prefer
        articles that genuinely have material worth talking about.
        """
        return len(self.extract)


class WikipediaFactsService:
    """Stateless service for Wikipedia GeoSearch + extract fetch.

    Holds an httpx.AsyncClient for connection reuse. Always call
    `close()` when done. The client is injectable so tests can pass
    a transport mock without monkey-patching httpx.
    """

    def __init__(self, client: Optional[httpx.AsyncClient] = None):
        # Custom client lets tests inject a mocked transport.
        self.client = client or httpx.AsyncClient(
            timeout=20.0,
            headers={"User-Agent": _USER_AGENT},
        )

    async def close(self) -> None:
        await self.client.aclose()

    async def geosearch_along_polyline(
        self,
        polyline: str,
        *,
        stride_miles: Optional[float] = None,
        radius_m: int = _GEOSEARCH_RADIUS_M,
    ) -> list[FactCandidate]:
        """Decode polyline, sample, geosearch each sample in parallel,
        dedupe by pageid. **Does not fetch article extracts** — the
        caller is responsible for calling `fetch_extract(pageid)` only
        for the candidates it intends to summarize (typically after the
        per-article POIContent cache check eliminates most of them).
        That keeps Wikipedia request volume proportional to *new* facts,
        not all facts on the route.

        Returns candidates in pageid-stable order (lowest first) so
        callers and tests don't need to depend on Wikipedia's
        ranking, which has shifted historically.
        """
        coords = decode_polyline(polyline)
        if not coords:
            return []

        scale = detect_trip_scale(coords)
        stride = stride_miles if stride_miles is not None else _STRIDE_MILES[scale]
        samples = _stride_sample(coords, stride_miles=stride)
        logger.info(
            "wikipedia: %d coords → %d samples (scale=%s, stride=%smi)",
            len(coords), len(samples), scale.value, stride,
        )

        # Parallel geosearch around each sample. Wikipedia rate-limits
        # bursts aggressively; 3 is conservative enough to never trip
        # the 429 even with ~30 samples on a long trip.
        sem = asyncio.Semaphore(3)

        async def _bounded_geosearch(point):
            async with sem:
                return await self._geosearch_point(point, radius_m=radius_m)

        per_point_results = await asyncio.gather(
            *[_bounded_geosearch(p) for p in samples]
        )

        # Dedupe by pageid; keep the smallest distance-from-route
        # for tie-breakers downstream.
        by_pageid: dict[int, dict] = {}
        for sample_point, results in zip(samples, per_point_results):
            for r in results:
                pageid = r["pageid"]
                # Distance from the *route polyline*, not from the
                # sample point — the sample is just a query origin,
                # not the answer to "how close to my route is this?".
                dist = _min_distance_to_route(
                    (r["lat"], r["lng"]), coords,
                )
                if pageid not in by_pageid or dist < by_pageid[pageid]["distance"]:
                    by_pageid[pageid] = {
                        "pageid": pageid,
                        "title": r["title"],
                        "lat": r["lat"],
                        "lng": r["lng"],
                        "distance": dist,
                    }

        if not by_pageid:
            return []

        # Build candidates from geosearch alone — extract is empty
        # until the orchestrator decides this candidate is worth
        # spending a Wikipedia request on.
        pageids = sorted(by_pageid.keys())
        out: list[FactCandidate] = []
        for pageid in pageids:
            meta = by_pageid[pageid]
            out.append(FactCandidate(
                wikipedia_pageid=pageid,
                title=meta["title"],
                lat=meta["lat"],
                lng=meta["lng"],
                distance_from_route_miles=meta["distance"],
                extract="",
                url=f"https://en.wikipedia.org/?curid={pageid}",
            ))
        logger.info("wikipedia: produced %d candidates (geosearch only)", len(out))
        return out

    async def fetch_extract(self, pageid: int) -> str:
        """Public wrapper around `_fetch_extract` so the orchestration
        layer can call it for cache-miss pageids only. Returns empty
        string on failure (including 429s)."""
        return await self._fetch_extract(pageid)

    async def _geosearch_point(
        self,
        point: tuple[float, float],
        *,
        radius_m: int,
    ) -> list[dict]:
        """One geosearch call. Returns list of {pageid, title, lat,
        lng} dicts. Errors are logged and swallowed (we'd rather
        return fewer candidates than abort the whole route)."""
        lat, lng = point
        params = {
            "action": "query",
            "list": "geosearch",
            "gscoord": f"{lat}|{lng}",
            "gsradius": str(radius_m),
            "gslimit": str(_GEOSEARCH_LIMIT),
            "format": "json",
        }
        try:
            response = await self.client.get(_WIKI_API, params=params)
            response.raise_for_status()
            data = response.json()
        except httpx.HTTPError as e:
            logger.warning("wikipedia geosearch failed at %s: %s", point, e)
            return []

        results = data.get("query", {}).get("geosearch", [])
        return [
            {
                "pageid": r["pageid"],
                "title": r["title"],
                "lat": r["lat"],
                "lng": r["lon"],
            }
            for r in results
        ]

    async def _fetch_extract(self, pageid: int) -> str:
        """Fetch plain-text article extract. We pull the whole article
        (not just intro) — the LLM summarizer can pick the best
        material from the full text, but if we truncate here we
        permanently throw away potentially-magical paragraphs.
        """
        params = {
            "action": "query",
            "prop": "extracts",
            "explaintext": "true",
            "pageids": str(pageid),
            "format": "json",
        }
        try:
            response = await self.client.get(_WIKI_API, params=params)
            response.raise_for_status()
            data = response.json()
        except httpx.HTTPError as e:
            logger.warning("wikipedia extract failed for pageid=%d: %s", pageid, e)
            return ""

        pages = data.get("query", {}).get("pages", {})
        page = pages.get(str(pageid), {})
        return page.get("extract", "") or ""


def _stride_sample(
    coords: list[tuple[float, float]],
    *,
    stride_miles: float,
) -> list[tuple[float, float]]:
    """Sample points along the polyline at ~stride_miles intervals.

    Walks consecutive coords summing haversine distances and emits
    a point whenever cumulative distance crosses the stride. Always
    includes first and last points so the route's start and end get
    geosearched. Identical inputs produce identical outputs, which
    matters for the polyline-hash cache key.
    """
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
    # Always include the last point if we haven't already (it likely
    # got skipped if the final segment was shorter than the stride).
    if samples[-1] != coords[-1]:
        samples.append(coords[-1])
    return samples


def _min_distance_to_route(
    point: tuple[float, float],
    route: list[tuple[float, float]],
) -> float:
    """Minimum distance in miles from a point to any vertex of the
    route. Cheap approximation — for our purposes (`is this article
    near the road or 30 miles off?`) the vertex-distance is plenty
    accurate. Don't use this for routing decisions.
    """
    if not route:
        return float("inf")
    return min(calculate_distance_miles(point, vertex) for vertex in route)
