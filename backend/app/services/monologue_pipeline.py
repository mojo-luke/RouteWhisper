"""
Monologue pipeline — characterize a route, author its companion
monologue, optionally include stop suggestions tied to specific
utterances.

Stage layout matches docs/companion-monologue-v1-plan.md sections 1-3
(town extraction is its own service; here we orchestrate everything
that runs at trip-save time except verification + TTS, which are
later slices).

The output is a `RouteMonologue` Beanie document that downstream
consumers (audio synth, frontend) read.

The artifact is cached globally by (polyline_hash, vibe_hash) so two
users on the same route+vibe pay the LLM cost only once. Volatile
data (per-stop business_status, hours) is NOT stored here — that's
fetched fresh at trip-start time in a future slice.
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import os
from typing import Optional

from anthropic import AsyncAnthropic

from app.database import MonologueAudio, RouteMonologue
from app.services.openai_tts import TtsSynthesizer
from app.services.poi_verifier import verify_stops
from app.services.town_extractor import Town, extract_towns
from app.utils.polyline import decode_polyline

logger = logging.getLogger(__name__)


# Models. Sonnet authors; Haiku-level reliability is insufficient for
# the voice quality we proved in the spikes. See spike_drive_monologue
# results.
AUTHOR_MODEL = "claude-sonnet-4-6"

# Author parameters. Tuned in spikes — characterization is short prose,
# the combined monologue+stops is a structured JSON object.
CHARACTERIZE_MAX_TOKENS = 900
COMBINED_MAX_TOKENS = 2800

# How many utterances and stops to ask the author for. Tuned in
# `spike_monologue_with_stops.py`; bumping these requires retesting
# voice consistency across the longer output.
NUM_UTTERANCES = 10
STOPS_PER_INTEREST = 3


# -------- Prompts ---------------------------------------------------

CHARACTERIZE_PROMPT = """You are a travel writer who knows American
road trips intimately. In 3-4 short paragraphs, characterize this
route as a place with identity: its history, the story arc of the
drive, themes a traveler might follow. Stay grounded — only mention
real places.

Route: {route_label}
"""


COMBINED_PROMPT = """You are a road-trip companion riding along with
the driver. You wrote the characterization below.

ROUTE CHARACTERIZATION:
{characterization}

TOWNS THE ROUTE PASSES THROUGH (in order):
{town_list}

THE DRIVER'S NARRATION INTERESTS for this trip:
{themes_section}

{stops_section}

Now write TWO things in one response, as a single JSON object:

1. A "monologue" of exactly {n_utt} short utterances you'd speak during
   the drive. Each utterance:
   - 25-40 words. Aim for ~15 seconds of speech.
   - Sounds like a friend in the passenger seat, NOT a tour guide.
   - Is anchored to one of the towns above, or to a specific landmark
     along that stretch.
   - Builds on the previous ones as a connected narrative.
   - Tilts toward the narration interests listed above. Don't force
     every utterance to hit every theme; let the route's character lead.
   - Never invents. If unsure, omit.

{stops_instruction}

Return ONLY a JSON object, no preamble or markdown fences:

{{
  "monologue": [
    {{"i": 1, "anchor": "town", "utterance": "..."}}
  ],
  "stops": [
    {{"category": "food", "name": "...", "town": "...",
      "detail_matched": "Mexican, hole-in-the-wall",
      "tied_to_utterance": 1, "reason": "..."}}
  ]
}}

If the driver requested no stop interests, the "stops" array must be
empty. Do NOT fabricate stops.
"""


STOPS_INSTRUCTION_WITH = """2. A "stops" list. For EACH stop interest the
driver declared above, propose up to {n_stops} real places that match.
Each stop must:
   - Be a REAL place (only list places you're confident exist).
   - Match the requested category AND any free-text detail given.
   - Be along this route's corridor, not 50 miles off.
   - Reference exactly one utterance index it ties to (the moment in
     the narration where it would naturally come up).
   - Include the town it's in.

If you can't confidently produce any matches for a given stop interest,
return fewer than {n_stops} for that interest. Better to skip than
fabricate."""


STOPS_INSTRUCTION_WITHOUT = """2. Leave the "stops" array EMPTY ([]).
The driver declared no stop interests for this trip."""


# -------- Public API ------------------------------------------------

async def generate_monologue(
    polyline: str,
    route_label: str,
    narration_themes: list[str],
    stop_interests: list[dict],
) -> Optional[RouteMonologue]:
    """End-to-end authoring of a route monologue.

    Returns the cached RouteMonologue if (polyline, vibe) was
    previously generated; otherwise calls the LLM, persists, and
    returns. Returns None if the polyline doesn't decode to any
    towns (no monologue possible).

    `narration_themes` items should be from the curated set
    ("history", "landscape", "food_culture", "quirky"); we don't
    enforce that at this layer to keep the LLM open to evolving
    the set without code changes.

    `stop_interests` items are dicts with `{category, detail}`
    (see app.database.StopInterest). Empty list is valid — the
    monologue is then pure narration, no stops.
    """
    ant_key = os.getenv("ANTHROPIC_API_KEY")
    if not ant_key:
        logger.error("monologue_pipeline: no ANTHROPIC_API_KEY; cannot author")
        return None

    p_hash = polyline_hash(polyline)
    v_hash = vibe_hash(narration_themes, stop_interests)

    # Cache check
    cached = await RouteMonologue.find_one(
        RouteMonologue.polyline_hash == p_hash,
        RouteMonologue.vibe_hash == v_hash,
    )
    if cached:
        logger.info(
            "monologue_pipeline: cache hit p=%s v=%s",
            p_hash[:8], v_hash[:8],
        )
        return cached

    # Stage 1: towns
    towns = await extract_towns(polyline)
    if not towns:
        logger.warning("monologue_pipeline: no towns extracted; skipping author")
        return None
    town_list = ", ".join(t.name for t in towns)

    client = AsyncAnthropic(api_key=ant_key)

    # Stage 2: characterize the route
    characterization = await _characterize_route(client, route_label)
    if not characterization:
        logger.warning("monologue_pipeline: characterization failed")
        return None

    # Stage 3: monologue + stops in one call
    artifact = await _author_monologue_and_stops(
        client,
        characterization=characterization,
        town_list=town_list,
        narration_themes=narration_themes,
        stop_interests=stop_interests,
    )
    if not artifact:
        logger.warning("monologue_pipeline: authoring returned no artifact")
        return None

    # Stage 4 (Slice B): TTS-synthesize each utterance, populate
    # audio_url. Each utterance is content-addressed by sha256(text)
    # so identical lines across routes share an mp3.
    utterances = artifact.get("monologue", []) or []
    await _attach_audio_urls(utterances)

    # Stage 5 (Slice C): Verify each LLM-proposed stop against
    # Mapbox Search Box (with OSM Overpass fallback). Drop anything
    # we can't pin to real coords on the route. The monologue's
    # narrative references to places stay intact regardless — only
    # the tappable stop cards are gated by verification.
    proposed_stops = artifact.get("stops", []) or []
    if proposed_stops:
        route_coords = decode_polyline(polyline)
        verified_stops = await verify_stops(
            proposed_stops, route_coords,
            [t.model_dump() for t in towns],
        )
    else:
        verified_stops = []

    # Persist and return
    canonical_interests = _canonicalize_stop_interests(stop_interests)
    canonical_themes = sorted(set(narration_themes))
    doc = RouteMonologue(
        polyline_hash=p_hash,
        vibe_hash=v_hash,
        narration_themes=canonical_themes,
        stop_interests=canonical_interests,
        towns=[t.model_dump() for t in towns],
        characterization=characterization,
        utterances=utterances,
        stops=verified_stops,
    )
    await doc.insert()
    audio_count = sum(1 for u in utterances if u.get("audio_url"))
    logger.info(
        "monologue_pipeline: persisted p=%s v=%s towns=%d utt=%d audio=%d "
        "stops=%d (verified from %d proposed)",
        p_hash[:8], v_hash[:8],
        len(towns), len(doc.utterances), audio_count,
        len(doc.stops), len(proposed_stops),
    )
    return doc


# -------- Fire-and-forget wrapper for trip-save prewarm -------------

def fire_and_forget_generate_monologue(
    polyline: str,
    route_label: str,
    narration_themes: list[str],
    stop_interests: list[dict],
    *,
    label: str = "",
) -> None:
    """Kick off generate_monologue as a background task. Use from
    trip-create / trip-update endpoints to warm the cache so the
    device hits a ready artifact at trip-start instead of waiting
    30+ seconds for the LLM authoring + TTS synthesis.

    Idempotent in spirit (cache hit on repeat). Errors are logged
    and swallowed — narration is not load-bearing for the trip
    itself.

    `label` shows up in logs to disambiguate concurrent prewarms
    (e.g., "trip=abc" vs "trip=xyz").
    """
    async def _run():
        try:
            doc = await generate_monologue(
                polyline=polyline,
                route_label=route_label,
                narration_themes=narration_themes,
                stop_interests=stop_interests,
            )
            if doc:
                logger.info(
                    "monologue_pipeline: prewarmed monologue (%s) "
                    "utt=%d stops=%d",
                    label, len(doc.utterances), len(doc.stops),
                )
            else:
                logger.info("monologue_pipeline: prewarm produced nothing (%s)", label)
        except Exception as e:
            logger.warning("monologue_pipeline: prewarm failed (%s): %r", label, e)

    asyncio.create_task(_run())


# -------- Cache-key helpers -----------------------------------------

def polyline_hash(polyline: str) -> str:
    """Stable hash of the polyline string. Routing-engine output is
    deterministic for the same origin/destination, so this works as
    a cache key."""
    return hashlib.sha256(polyline.encode("utf-8")).hexdigest()


def vibe_hash(narration_themes: list[str], stop_interests: list[dict]) -> str:
    """Stable hash of the canonical-form vibe object.

    Canonical form: themes sorted ascending; stop interests sorted by
    (category, detail). Empty detail strings are normalized to "".
    This makes ["history"] + [] hash identically every time, regardless
    of incoming ordering.
    """
    canonical = {
        "themes": sorted(set(narration_themes)),
        "stops": _canonicalize_stop_interests(stop_interests),
    }
    blob = json.dumps(canonical, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def _canonicalize_stop_interests(interests: list[dict]) -> list[dict]:
    cleaned = [
        {
            "category": (i.get("category") or "").strip().lower(),
            "detail": (i.get("detail") or "").strip(),
        }
        for i in interests
        if (i.get("category") or "").strip()
    ]
    return sorted(cleaned, key=lambda x: (x["category"], x["detail"]))


# -------- Author stages ---------------------------------------------

async def _characterize_route(
    client: AsyncAnthropic, route_label: str,
) -> Optional[str]:
    try:
        resp = await client.messages.create(
            model=AUTHOR_MODEL,
            max_tokens=CHARACTERIZE_MAX_TOKENS,
            messages=[{
                "role": "user",
                "content": CHARACTERIZE_PROMPT.format(route_label=route_label),
            }],
        )
        return resp.content[0].text.strip()
    except Exception as e:
        logger.error("monologue_pipeline: characterize failed: %r", e)
        return None


# -------- Audio synthesis ------------------------------------------

# Bounded concurrency for TTS calls. OpenAI rate-limits TTS at a few
# hundred per minute; 4 in parallel is comfortably under that while
# still finishing 10 utterances in ~3-4 seconds wall clock.
_TTS_CONCURRENCY = 4


async def _attach_audio_urls(utterances: list[dict]) -> None:
    """Synthesize an mp3 for each utterance (or fetch from cache) and
    set `audio_url` on the utterance dict.

    Mutates the input list in place. Missing TTS (no key, transient
    failure) sets `audio_url=None` so the device can fall back to its
    own local TTS without breaking the response shape.
    """
    if not os.getenv("OPENAI_API_KEY"):
        logger.warning("monologue_pipeline: no OPENAI_API_KEY; skipping TTS")
        for u in utterances:
            u["audio_url"] = None
        return

    synth = TtsSynthesizer()
    sem = asyncio.Semaphore(_TTS_CONCURRENCY)

    async def _one(u: dict) -> None:
        text = (u.get("utterance") or "").strip()
        if not text:
            u["audio_url"] = None
            return
        text_hash = hashlib.sha256(text.encode("utf-8")).hexdigest()
        # Cache check — same text across any number of routes shares
        # one stored mp3 keyed by its sha256.
        existing = await MonologueAudio.find_one(
            MonologueAudio.text_sha256 == text_hash,
        )
        if existing:
            u["audio_url"] = f"/api/v1/audio/monologue/{text_hash}"
            return
        async with sem:
            try:
                audio = await synth.synthesize_async(text)
            except Exception as e:
                logger.warning("monologue_pipeline: TTS failed for utt: %r", e)
                u["audio_url"] = None
                return
        if not audio:
            u["audio_url"] = None
            return
        # Persist; ignore duplicate-key races (two routes hit same text
        # at the same time — one wins, both get the URL).
        try:
            await MonologueAudio(
                text_sha256=text_hash,
                audio_bytes=audio,
                char_count=len(text),
            ).insert()
        except Exception as e:
            logger.info("monologue_pipeline: MonologueAudio insert raced: %r", e)
        u["audio_url"] = f"/api/v1/audio/monologue/{text_hash}"

    await asyncio.gather(*[_one(u) for u in utterances])


async def _author_monologue_and_stops(
    client: AsyncAnthropic,
    *,
    characterization: str,
    town_list: str,
    narration_themes: list[str],
    stop_interests: list[dict],
) -> Optional[dict]:
    themes_section = (
        "- " + "\n- ".join(narration_themes)
        if narration_themes else "(no specific themes; default to noticing what's interesting)"
    )

    has_stops = len(stop_interests) > 0
    if has_stops:
        stops_section = "STOP INTERESTS:\n" + "\n".join(
            f"- {si['category']}"
            + (f": {si['detail']}" if si.get("detail") else " (any kind)")
            for si in stop_interests
        )
        stops_instruction = STOPS_INSTRUCTION_WITH.format(n_stops=STOPS_PER_INTEREST)
    else:
        stops_section = "STOP INTERESTS:\n(none — the driver wants narration only)"
        stops_instruction = STOPS_INSTRUCTION_WITHOUT

    prompt = COMBINED_PROMPT.format(
        characterization=characterization,
        town_list=town_list,
        themes_section=themes_section,
        stops_section=stops_section,
        n_utt=NUM_UTTERANCES,
        stops_instruction=stops_instruction,
    )

    try:
        resp = await client.messages.create(
            model=AUTHOR_MODEL,
            max_tokens=COMBINED_MAX_TOKENS,
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
        # Light shape validation — the LLM occasionally drops keys.
        if "monologue" not in parsed:
            parsed["monologue"] = []
        if "stops" not in parsed:
            parsed["stops"] = []
        return parsed
    except json.JSONDecodeError as e:
        logger.error("monologue_pipeline: author returned non-JSON: %s; head=%r",
                     e, text[:300] if "text" in locals() else "?")
        return None
    except Exception as e:
        logger.error("monologue_pipeline: author call failed: %r", e)
        return None
