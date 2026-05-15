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

from app.database import RouteMonologue
from app.services.town_extractor import Town, extract_towns

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
        utterances=artifact.get("monologue", []),
        stops=artifact.get("stops", []),
    )
    await doc.insert()
    logger.info(
        "monologue_pipeline: persisted p=%s v=%s towns=%d utt=%d stops=%d",
        p_hash[:8], v_hash[:8],
        len(towns), len(doc.utterances), len(doc.stops),
    )
    return doc


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
