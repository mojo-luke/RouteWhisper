"""
Route preview pipeline — a fast, text-only "here's what this drive is"
artifact shown during trip creation, before the user has picked a vibe
or committed to the trip.

Deliberately lighter than app.services.monologue_pipeline: no TTS, no
stop verification (hotspots are anchored to the nearest extracted town,
not individually geocoded), and cached by polyline alone rather than
(polyline, vibe) — generation must start the moment origin+destination
are known, before the wizard has collected narration themes.

The RoutePreview document doubles as the generation lock: start_preview
inserts it via an atomic upsert, so whichever caller performs the insert
owns the LLM call and everyone else just polls via get_preview.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
from datetime import datetime
from typing import Optional

from anthropic import AsyncAnthropic
from pymongo import ReturnDocument

from app.database import RouteMonologue, RoutePreview
from app.services.mapbox_directions import fetch_route
from app.services.monologue_pipeline import polyline_hash
from app.services.town_extractor import Town, extract_towns

logger = logging.getLogger(__name__)


AUTHOR_MODEL = "claude-sonnet-4-6"
PREVIEW_MAX_TOKENS = 2200

# Author 6 candidates; the wizard shows a curated ~4, keeping 2 as
# buffer for hotspots _anchor_hotspots drops (town name didn't match).
NUM_HOTSPOTS = 6

# A pending doc older than this is assumed to belong to a crashed/dead
# worker and gets retaken rather than polled forever.
_PENDING_TTL_SECONDS = 180

_CURATED_THEMES = {"history", "landscape", "food_culture", "quirky"}


PREVIEW_PROMPT = """You are a road-trip writer previewing a drive for
someone about to take it.

ROUTE: {route_label}
DISTANCE: {distance_miles:.0f} miles, roughly {duration_label} of driving
TOWNS ALONG THE WAY, in order: {town_list}
{grounding}{exclude}
Write TWO things as one JSON object.

1. "rundown" — 3 short paragraphs, second person, addressed to the
   driver. What this drive is actually like: the shape of it, what
   changes as they go, what kind of country they pass through, what
   the drive is about. Concrete and grounded. No itinerary, no bullet
   lists, no "you'll love it" filler. If this is a short or familiar-
   feeling drive, don't pad it into sounding grander than it is — find
   what's genuinely worth noticing instead.

2. "hotspots" — exactly {n} specific, real, interesting things tied to
   towns on the list above. Favor the historic, the odd, the genuinely
   specific over generic attractions. Spread them across themes and
   across the length of the route, not all clustered at one end. Each
   hotspot:
   - "town" MUST be exactly one of the town names listed above.
   - "theme" is one of: history, landscape, food_culture, quirky.
   - "title" is the thing itself, 2-6 words.
   - "blurb" is 40-70 words that makes someone want to look out the
     window or pull off. Say something specific, a date, a name, a
     detail. Never pad.
   - "detour_hint" is a rough sense of effort ("right off the
     highway", "a 15-minute detour", "you'll drive past it") or null.
   Never invent. If you're not confident it exists, leave it out and
   return fewer.

Return ONLY JSON, no preamble or fences:
{{"rundown": "...", "hotspots": [{{"title": "...", "town": "...",
"theme": "...", "blurb": "...", "detour_hint": "..."}}]}}
"""


# -------- Public API ------------------------------------------------

async def start_preview(
    origin_lat: float,
    origin_lng: float,
    dest_lat: float,
    dest_lng: float,
    route_label: str,
) -> Optional[RoutePreview]:
    """Fast path: one Directions call, then either return a cached ready
    doc, join an in-flight generation, or claim the lock and
    fire-and-forget `_generate(...)`.

    Returns the doc as it stands right now (status pending or ready), or
    None if Directions itself failed. Never blocks on the LLM.
    """
    route = await fetch_route(origin_lat, origin_lng, dest_lat, dest_lng)
    if not route:
        return None

    p_hash = polyline_hash(route.polyline)
    now = datetime.utcnow()
    collection = RoutePreview.get_motor_collection()

    prior = await collection.find_one_and_update(
        {"polyline_hash": p_hash},
        {
            "$setOnInsert": {
                "polyline_hash": p_hash,
                "polyline": route.polyline,
                "route_label": route_label,
                "status": "pending",
                "stage": "routing",
                "distance_miles": route.distance_miles,
                "duration_minutes": route.duration_minutes,
                "towns": [],
                "rundown": "",
                "hotspots": [],
                "error": None,
                "created_at": now,
                "updated_at": now,
            },
        },
        upsert=True,
        return_document=ReturnDocument.BEFORE,
    )

    if prior is None:
        # We performed the insert; we own generation.
        doc = await RoutePreview.find_one(RoutePreview.polyline_hash == p_hash)
        asyncio.create_task(_generate(doc.id, route.polyline, route_label))
        return doc

    if prior.get("status") == "pending" and _is_stale(prior.get("created_at")):
        # Optimistic retake: only succeeds if no one else already did.
        retaken = await collection.find_one_and_update(
            {"polyline_hash": p_hash, "created_at": prior.get("created_at")},
            {"$set": {"stage": "routing", "created_at": now, "updated_at": now}},
        )
        doc = await RoutePreview.find_one(RoutePreview.polyline_hash == p_hash)
        if retaken is not None:
            asyncio.create_task(_generate(doc.id, route.polyline, route_label))
        return doc

    return await RoutePreview.find_one(RoutePreview.polyline_hash == p_hash)


async def get_preview(polyline_hash_: str) -> Optional[RoutePreview]:
    """Poll. Plain cache read."""
    return await RoutePreview.find_one(RoutePreview.polyline_hash == polyline_hash_)


def _is_stale(created_at: Optional[datetime]) -> bool:
    if created_at is None:
        return True
    return (datetime.utcnow() - created_at).total_seconds() > _PENDING_TTL_SECONDS


# -------- Generation --------------------------------------------------

async def _generate(doc_id, polyline: str, route_label: str) -> None:
    doc = await RoutePreview.get(doc_id)
    if doc is None:
        return
    try:
        doc.stage = "towns"
        doc.updated_at = datetime.utcnow()
        await doc.save()

        towns = await extract_towns(polyline)
        if not towns:
            await _fail(doc, "no towns extracted")
            return

        doc.towns = [t.model_dump() for t in towns]
        doc.stage = "authoring"
        doc.updated_at = datetime.utcnow()
        await doc.save()

        ant_key = os.getenv("ANTHROPIC_API_KEY")
        if not ant_key:
            await _fail(doc, "no ANTHROPIC_API_KEY")
            return

        prior_characterization = await _find_prior_characterization(doc.polyline_hash)
        client = AsyncAnthropic(api_key=ant_key)
        artifact = await _author_preview(
            client,
            route_label=route_label,
            towns=towns,
            distance_miles=doc.distance_miles,
            duration_minutes=doc.duration_minutes,
            prior_characterization=prior_characterization,
            exclude_titles=[],
        )
        if not artifact:
            await _fail(doc, "authoring failed")
            return

        doc.rundown = (artifact.get("rundown") or "").strip()
        doc.hotspots = _anchor_hotspots(artifact.get("hotspots") or [], towns)
        doc.status = "ready"
        doc.stage = "done"
        doc.updated_at = datetime.utcnow()
        await doc.save()
        logger.info(
            "route_preview: ready p=%s towns=%d hotspots=%d",
            doc.polyline_hash[:8], len(towns), len(doc.hotspots),
        )
    except Exception as e:
        logger.error("route_preview: generation failed: %r", e)
        await _fail(doc, str(e)[:300])


async def _fail(doc: RoutePreview, error: str) -> None:
    doc.status = "failed"
    doc.error = error
    doc.updated_at = datetime.utcnow()
    try:
        await doc.save()
    except Exception as e:
        logger.error("route_preview: failed to persist failure state: %r", e)


async def _find_prior_characterization(p_hash: str) -> Optional[str]:
    """Free grounding: if the (unrelated, vibe-keyed) drive-monologue
    pipeline has already characterized this exact route for any vibe,
    reuse its prose as context rather than re-deriving route character
    from scratch. Characterization is vibe-independent."""
    existing = await RouteMonologue.find_one(RouteMonologue.polyline_hash == p_hash)
    return existing.characterization if existing else None


async def _author_preview(
    client: AsyncAnthropic,
    *,
    route_label: str,
    towns: list[Town],
    distance_miles: float,
    duration_minutes: int,
    prior_characterization: Optional[str],
    exclude_titles: list[str],
) -> Optional[dict]:
    town_list = ", ".join(t.name for t in towns)
    hours, mins = divmod(round(duration_minutes), 60)
    duration_label = f"{hours} hr {mins} min" if hours else f"{mins} min"

    grounding = (
        f"\nWHAT WE ALREADY KNOW ABOUT THIS ROUTE:\n{prior_characterization}\n"
        if prior_characterization else ""
    )
    exclude = (
        "\nALREADY SHOWN TO THIS TRAVELER — pick different subjects:\n"
        + "\n".join(f"- {t}" for t in exclude_titles) + "\n"
        if exclude_titles else ""
    )

    prompt = PREVIEW_PROMPT.format(
        route_label=route_label,
        distance_miles=distance_miles,
        duration_label=duration_label,
        town_list=town_list,
        grounding=grounding,
        exclude=exclude,
        n=NUM_HOTSPOTS,
    )

    try:
        resp = await client.messages.create(
            model=AUTHOR_MODEL,
            max_tokens=PREVIEW_MAX_TOKENS,
            messages=[{"role": "user", "content": prompt}],
        )
        text = resp.content[0].text.strip()
        # Sonnet occasionally wraps despite instructions; strip fences.
        if text.startswith("```"):
            text = text.split("```", 2)[1]
            if text.startswith("json"):
                text = text[4:]
            text = text.strip()
        parsed = json.loads(text)
        if "rundown" not in parsed:
            parsed["rundown"] = ""
        if "hotspots" not in parsed:
            parsed["hotspots"] = []
        return parsed
    except json.JSONDecodeError as e:
        logger.error("route_preview: author returned non-JSON: %s; head=%r",
                     e, text[:300] if "text" in locals() else "?")
        return None
    except Exception as e:
        logger.error("route_preview: author call failed: %r", e)
        return None


def _anchor_hotspots(raw: list[dict], towns: list[Town]) -> list[dict]:
    """Attach lat/lng by matching each hotspot's `town` against the
    extracted town list (case-insensitive). Drops hotspots whose town
    isn't on the route — the cheap hallucination guard that replaces
    stop verification for this feature. Assigns stable ids hs_1..hs_N.
    """
    by_name = {t.name.strip().lower(): t for t in towns}
    out: list[dict] = []
    for h in raw:
        town_name = (h.get("town") or "").strip()
        town = by_name.get(town_name.lower())
        title = (h.get("title") or "").strip()
        blurb = (h.get("blurb") or "").strip()
        if town is None or not title or not blurb:
            continue
        theme = (h.get("theme") or "").strip().lower()
        if theme not in _CURATED_THEMES:
            theme = "quirky"
        out.append({
            "id": f"hs_{len(out) + 1}",
            "title": title,
            "town": town.name,
            "lat": town.lat,
            "lng": town.lng,
            "theme": theme,
            "blurb": blurb,
            "detour_hint": h.get("detour_hint"),
        })
    return out
