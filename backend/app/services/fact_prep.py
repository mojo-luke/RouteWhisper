"""
Shared narration prep pipeline.

Two entry points share the same per-pageid cache logic:
  - `prepare_for_polyline` is what /api/v1/route/facts uses at trip-
    start (and what the trip-prewarm background task uses).
  - `prepare_for_area` warms a circular region around a point (used
    by /api/v1/narration/prewarm-area for ad-hoc / home-area prep).

The point of factoring this out is twofold:

  1. **Per-pageid cache is global** — keyed by `wikipedia_pageid` in
     POIContent, never per-user. Once any user (or any background
     task) has paid the LLM + TTS cost for an article, every future
     trip past it costs nothing. The two entry points feed the same
     cache, so pre-warming an area benefits all future routes that
     touch it.

  2. **Single source of truth for the pipeline** — discovery → rank
     → summarize → synthesize → persist. If the prompt, ranking
     weights, or cache versioning changes, there's one place to
     update.

See: ~/.claude/plans/breezy-gliding-mountain.md → Phase 1.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Optional

from app.services.fact_ranker import rank_candidates
from app.services.llm_summarizer import LLMSummarizer
from app.services.openai_tts import TtsSynthesizer
from app.services.wikipedia_facts import (
    FactCandidate,
    WikipediaFactsService,
)
from app.utils.polyline import (
    TripScale,
    calculate_distance_miles,
    decode_polyline,
    detect_trip_scale,
)

logger = logging.getLogger(__name__)


# Concurrency for the LLM + TTS inner loop. 12 is comfortable below
# both Anthropic and OpenAI rate limits at our scale (~30-100 articles
# per call) and small enough that a typical pipeline completes in
# 15-30s. Higher numbers don't help much — Anthropic / OpenAI per-call
# latency dominates.
_INNER_CONCURRENCY = 12

# Top-N cap for area pre-warming. Bounds runaway cost in dense places
# (downtown SF has many Wikipedia articles within 30 miles); doesn't
# bound the cap for trip prep, which uses fact_ranker's own DEFAULT_TOP_N.
_AREA_TOP_N = 100


# ============================================================
# Public entry points
# ============================================================


async def prepare_for_polyline(
    polyline: str,
    *,
    user_interests: Optional[list[dict]] = None,
    top_n: Optional[int] = None,
    return_response: bool = True,
) -> list[dict]:
    """Run the prep pipeline against a Mapbox polyline.

    When called by /api/v1/route/facts (return_response=True), returns
    the assembled list of fact dicts ready for the device.

    When called by a background prewarm task (return_response=False),
    we still run the same pipeline but skip building the response
    payload — the side effect (POIContent gets warmed) is what we
    care about.
    """
    polyline = (polyline or "").strip()
    if not polyline:
        return []

    wiki = WikipediaFactsService()
    try:
        candidates = await wiki.geosearch_along_polyline(polyline)
        if not candidates:
            return []
        ranked = rank_candidates(
            candidates,
            user_interests=user_interests or [],
            top_n=top_n if top_n is not None else 30,
        )
        if not ranked:
            return []
        bundles = await _summarize_in_parallel(
            wiki,
            [r.candidate for r in ranked],
        )
    finally:
        await wiki.close()

    if not return_response:
        return []

    facts: list[dict] = []
    for ranked_fact, bundle in zip(ranked, bundles):
        if not bundle or not bundle.get("primary"):
            continue
        c = ranked_fact.candidate
        facts.append({
            "lat": c.lat,
            "lng": c.lng,
            "article_title": c.title,
            "article_url": c.url,
            "wikipedia_pageid": c.wikipedia_pageid,
            "primary": bundle["primary"],
            "primary_audio_url": bundle["primary_audio_url"],
            "follow_ups": bundle["follow_ups"],
            "follow_up_audio_urls": bundle["follow_up_audio_urls"],
            "is_thin": bundle["is_thin"],
            "distance_from_route_miles": c.distance_from_route_miles,
            "ranked_score": ranked_fact.score,
        })
    return facts


async def prepare_for_area(
    lat: float,
    lng: float,
    *,
    radius_miles: float = 30.0,
    user_interests: Optional[list[dict]] = None,
    top_n: int = _AREA_TOP_N,
) -> int:
    """Warm POIContent for a circular area around a point.

    Unlike `prepare_for_polyline`, this doesn't return a response
    payload — its only purpose is to fill the cache so that future
    trips through this area land on warm pageids. Returns the number
    of candidates summarized so callers can log meaningful telemetry.

    The implementation: build a degenerate "polyline" with a few
    sample points around the seed (current location), reuse
    geosearch's per-point query, then run the same summarization
    loop. Geosearch's 10km radius means ~30mi corridor sweep is well-
    covered by ~10 sample points arranged in a star pattern around
    the seed.
    """
    # Build a star pattern of sample points around the seed. 8 points
    # at radius/2, plus the seed itself. Combined with geosearch's
    # 10km per-point radius, this gives near-complete coverage of a
    # 30-mile disk without burning N² geosearch calls.
    samples = _star_samples(lat, lng, radius_miles=radius_miles)
    wiki = WikipediaFactsService()
    try:
        # Reuse the per-point geosearch via the existing method by
        # building a fake polyline... actually simpler to call the
        # private path directly. Make geosearch_point accessible.
        per_point: list[list[dict]] = await asyncio.gather(*[
            wiki._geosearch_point(p, radius_m=10_000) for p in samples
        ])
        # Dedupe by pageid.
        by_pageid: dict[int, dict] = {}
        for results in per_point:
            for r in results:
                pageid = r["pageid"]
                if pageid in by_pageid:
                    continue
                by_pageid[pageid] = {
                    "pageid": pageid,
                    "title": r["title"],
                    "lat": r["lat"],
                    "lng": r["lng"],
                }
        if not by_pageid:
            return 0
        # Build skeleton candidates (no extract; we fetch on cache miss).
        candidates = [
            FactCandidate(
                wikipedia_pageid=meta["pageid"],
                title=meta["title"],
                lat=meta["lat"],
                lng=meta["lng"],
                # No route here, so "distance from route" is just the
                # distance from the seed. Used only as a tie-breaker
                # by the ranker; for area prewarm, uniqueness +
                # interest fit do most of the work.
                distance_from_route_miles=calculate_distance_miles(
                    (meta["lat"], meta["lng"]), (lat, lng),
                ),
                extract="",
                url=f"https://en.wikipedia.org/?curid={meta['pageid']}",
            )
            for meta in by_pageid.values()
        ]
        ranked = rank_candidates(
            candidates,
            user_interests=user_interests or [],
            top_n=top_n,
        )
        await _summarize_in_parallel(wiki, [r.candidate for r in ranked])
        return len(ranked)
    finally:
        await wiki.close()


# ============================================================
# Inner pipeline (shared by both entry points)
# ============================================================


async def _summarize_in_parallel(
    wiki: WikipediaFactsService,
    candidates: list[FactCandidate],
) -> list[Optional[dict]]:
    """Run the per-candidate summarization + TTS synthesis loop with
    bounded concurrency. Returns one bundle dict per candidate (or
    None for failures). The actual cache write happens inside
    `_get_or_summarize`.
    """
    summarizer = LLMSummarizer()
    tts = TtsSynthesizer()
    sem = asyncio.Semaphore(_INNER_CONCURRENCY)

    # `_get_or_summarize` lives in main.py for now (depends on the
    # version constants there). Late import to avoid a circular
    # dependency between fact_prep.py and main.py.
    from app.main import _get_or_summarize

    async def _process(c: FactCandidate) -> Optional[dict]:
        async with sem:
            try:
                return await _get_or_summarize(summarizer, tts, wiki, c)
            except Exception as e:
                logger.warning(
                    "fact_prep: failed to summarize pageid=%d (%s): %s",
                    c.wikipedia_pageid, c.title, e,
                )
                return None

    return await asyncio.gather(*[_process(c) for c in candidates])


# ============================================================
# Background-task helpers
# ============================================================


def fire_and_forget_prepare_polyline(
    polyline: str,
    *,
    user_interests: Optional[list[dict]] = None,
    label: str = "",
) -> None:
    """Kick off `prepare_for_polyline` as a fire-and-forget task and
    log its outcome. Use from endpoints that want to warm a cache
    without blocking the response.

    `label` is included in logs to disambiguate concurrent warm-ups
    (e.g., "trip=abc123" vs "trip=xyz999").
    """
    async def _run():
        try:
            await prepare_for_polyline(
                polyline,
                user_interests=user_interests,
                return_response=False,
            )
            logger.info("fact_prep: prewarmed polyline (%s)", label)
        except Exception as e:
            logger.warning("fact_prep: polyline prewarm failed (%s): %s", label, e)

    asyncio.create_task(_run())


def fire_and_forget_prepare_area(
    lat: float,
    lng: float,
    *,
    radius_miles: float = 30.0,
    user_interests: Optional[list[dict]] = None,
    label: str = "",
) -> None:
    """Fire-and-forget variant of `prepare_for_area`."""
    async def _run():
        try:
            count = await prepare_for_area(
                lat, lng,
                radius_miles=radius_miles,
                user_interests=user_interests,
            )
            logger.info(
                "fact_prep: prewarmed area (%s) — %d candidates processed",
                label, count,
            )
        except Exception as e:
            logger.warning("fact_prep: area prewarm failed (%s): %s", label, e)

    asyncio.create_task(_run())


def _star_samples(
    lat: float, lng: float, *, radius_miles: float,
) -> list[tuple[float, float]]:
    """Sample 8 compass points at half-radius around (lat, lng), plus
    the seed itself. Cheap proxy for "interesting articles inside
    this disk." Approximation: convert miles to degrees at the
    seed's latitude (1 degree latitude ≈ 69 miles; longitude scales
    by cos(lat))."""
    import math
    out: list[tuple[float, float]] = [(lat, lng)]
    half = radius_miles / 2.0
    d_lat = half / 69.0
    d_lng = half / (69.0 * max(0.1, math.cos(math.radians(lat))))
    for bearing_deg in range(0, 360, 45):
        rad = math.radians(bearing_deg)
        out.append((
            lat + d_lat * math.cos(rad),
            lng + d_lng * math.sin(rad),
        ))
    return out
