"""
Turn an encyclopedic Wikipedia extract into friend-voice narration.

This is the LLM's *only* job in Phase 1 of the companion product:
take a long Wikipedia article text and emit a short, conversational
`primary` line plus an ordered list of `follow_ups`. The `is_thin`
flag lets us be honest when an article doesn't support further
material — the narration card says "that's all I've got on this one"
rather than letting the model invent filler.

Runs at trip-prep time (when the user is in the parking lot with
full signal), never on the live driving path. Output is cached by
Wikipedia pageid in POIContent so repeat-trips and overlapping
routes cost zero LLM tokens.

See: ~/.claude/plans/breezy-gliding-mountain.md → "Cohesion (LLM)"
"""

from __future__ import annotations

import json
import logging
import os
from typing import Optional

from anthropic import Anthropic, AnthropicError, AsyncAnthropic
from pydantic import BaseModel, Field, ValidationError

logger = logging.getLogger(__name__)


# Model + prompt. Haiku is fast and cheap; this prompt is the
# load-bearing piece of the whisper voice. Anything that touches
# how the app *sounds* lives here, not scattered across the codebase.
_MODEL = "claude-haiku-4-5-20251001"
_MAX_TOKENS = 800
_SYSTEM_PROMPT = (
    "You are riding shotgun on a road trip. Your friend is driving and "
    "you've just passed a place. Tell them about it the way a curious, "
    "well-read friend would — specific, conversational, never reciting "
    "an encyclopedia. Skip dates and lat/longs unless they're genuinely "
    "what's interesting about the place. Never invent — only use facts "
    "from the Wikipedia article provided.\n\n"
    "CRITICAL: The `primary` line MUST start by naming the place "
    "naturally — so the listener immediately knows what you're "
    "pointing at. Examples of good openers: 'That's Coit Tower — Art "
    "Deco, built in 1933...', 'The Ferry Building's 245-foot clock "
    "tower...', 'Bimbo's 365 Club started as a speakeasy...'. Bad "
    "openers (DON'T do this): 'So that 245-foot clock tower...' "
    "(listener doesn't know what you mean), 'This place was a Gold "
    "Rush boomtown...' (which place?). The place's name comes first, "
    "every time.\n\n"
    "ALSO REQUIRED: classify the article into one `feature_kind` "
    "from this exact set:\n"
    "  - \"landmark\": a single visible thing at a specific point "
    "(building, monument, ship, tower, statue, single restaurant). "
    "Off-route distance matters — listener has to be near it to see it.\n"
    "  - \"city\" or \"town\": a settlement. The article's coord is "
    "a center reference; the city extends outward, so the listener "
    "may be inside it even if the coord is a few miles away.\n"
    "  - \"river\", \"road\", \"coast\": a linear feature. Coordinate "
    "is arbitrary along its length; off-route distance is meaningless.\n"
    "  - \"region\": a county, valley, district, neighborhood, park, "
    "or any areal feature. Listener is likely inside it; coord is a "
    "reference point.\n"
    "  - \"event_only\": the article is about something that "
    "*happened* nearby but no physical landmark exists at the coord "
    "(a battle field that's now an empty lot, a historic meeting in "
    "a building that's gone, etc.). These are interesting but the "
    "passenger has nothing to see — we won't narrate them.\n"
    "When uncertain, default to \"landmark\" — strictest filter, "
    "least likely to play in confusing contexts.\n\n"
    "Return JSON with this shape:\n"
    "{\n"
    "  \"primary\": <35-45 word string opening with the location's "
    "name, said conversationally>,\n"
    "  \"follow_ups\": <list of 0-3 additional 35-45 word strings, "
    "ordered most-to-least interesting; each a distinct angle. "
    "Follow-ups can be more free-form since the listener already "
    "knows where you are>,\n"
    "  \"is_thin\": <true if the article genuinely doesn't support "
    "more than the primary; false if you held back follow-ups "
    "because of word budget>,\n"
    "  \"feature_kind\": <one of: landmark, city, town, river, road, "
    "coast, region, event_only>\n"
    "}\n"
    "Output ONLY the JSON object — no preamble, no markdown fences."
)

# Hard cap on extract size to keep token usage bounded. Wikipedia
# extracts can run to many thousands of words for big-city articles;
# the first 4000 chars give the LLM the lede + the most-edited
# (highest-quality) paragraphs.
_MAX_EXTRACT_CHARS = 4000


# Allowed feature_kind values. Anything outside this set falls back
# to "landmark" — the strictest filter, used as the safe default.
ALLOWED_FEATURE_KINDS = {
    "landmark",
    "city",
    "town",
    "river",
    "road",
    "coast",
    "region",
    "event_only",
}


class SummaryBundle(BaseModel):
    """The structured contract between the LLM and everything
    downstream. `primary` is the whisper text; `follow_ups` feed the
    'tell me more' button; `is_thin` lets the UI be honest;
    `feature_kind` lets the ranker filter by article type (a city
    extends past its center coord; a landmark doesn't).
    """
    primary: str
    follow_ups: list[str] = Field(default_factory=list)
    is_thin: bool = False
    feature_kind: str = "landmark"


class LLMSummarizer:
    """Thin wrapper around the Anthropic client.

    Production callers should pass nothing and let it pick up
    `ANTHROPIC_API_KEY` from the env. Tests can pass a sync client
    via `client=` (for `summarize_article`) or an async one via
    `async_client=` (for `summarize_article_async`).

    Two API surfaces: the sync `summarize_article` (used by tests)
    and an async `summarize_article_async` (used by fact_prep so
    the event loop can actually parallelize at our concurrency
    semaphore's width — `asyncio.to_thread` would bottleneck on the
    default 8-wide thread pool).
    """

    def __init__(
        self,
        client: Optional[Anthropic] = None,
        async_client: Optional[AsyncAnthropic] = None,
    ):
        self._client = client
        self._async_client = async_client

    @property
    def client(self) -> Anthropic:
        if self._client is None:
            self._client = Anthropic()
        return self._client

    @property
    def async_client(self) -> AsyncAnthropic:
        if self._async_client is None:
            self._async_client = AsyncAnthropic()
        return self._async_client

    def summarize_article(self, title: str, extract: str) -> SummaryBundle:
        """One LLM call → SummaryBundle. Synchronous variant — used
        by tests. Production code paths should prefer the async
        variant to avoid thread-pool bottlenecking.

        Always returns a bundle. On any failure (network, parse,
        validation), falls back to a first-paragraph primary with
        `is_thin=True` so callers can keep going.
        """
        extract = (extract or "").strip()
        if not extract:
            return _fallback(title, "")

        trimmed = extract[:_MAX_EXTRACT_CHARS]
        user_msg = (
            f"Wikipedia article: {title}\n\n"
            f"Article text:\n{trimmed}"
        )
        try:
            response = self.client.messages.create(
                model=_MODEL,
                max_tokens=_MAX_TOKENS,
                system=_SYSTEM_PROMPT,
                messages=[{"role": "user", "content": user_msg}],
            )
        except AnthropicError as e:
            logger.warning("LLM summarize failed for '%s': %s", title, e)
            return _fallback(title, extract)

        text = _extract_text(response)
        return _parse_or_fallback(text, title, extract)

    async def summarize_article_async(
        self, title: str, extract: str,
    ) -> SummaryBundle:
        """Async variant. Same contract as the sync version but uses
        the async Anthropic client so asyncio can actually run many
        calls in parallel without thread-pool bottleneck. Fact prep
        orchestration uses this to keep cold-cache times in the
        15-30s range instead of minutes.
        """
        extract = (extract or "").strip()
        if not extract:
            return _fallback(title, "")

        trimmed = extract[:_MAX_EXTRACT_CHARS]
        user_msg = (
            f"Wikipedia article: {title}\n\n"
            f"Article text:\n{trimmed}"
        )
        try:
            response = await self.async_client.messages.create(
                model=_MODEL,
                max_tokens=_MAX_TOKENS,
                system=_SYSTEM_PROMPT,
                messages=[{"role": "user", "content": user_msg}],
            )
        except AnthropicError as e:
            logger.warning("LLM summarize failed for '%s': %s", title, e)
            return _fallback(title, extract)
        text = _extract_text(response)
        return _parse_or_fallback(text, title, extract)


def _extract_text(response) -> str:
    """Pull the first text block out of an Anthropic Messages response.
    The SDK wraps content in a list of blocks; we always emit one."""
    try:
        for block in response.content:
            if getattr(block, "type", None) == "text":
                return block.text
    except (AttributeError, TypeError):
        pass
    return ""


def _parse_or_fallback(text: str, title: str, extract: str) -> SummaryBundle:
    """LLM output is JSON-claimed but reality varies — sometimes
    they wrap in ```json fences despite the prompt, sometimes they
    add a paragraph of explanation. Strip fences, locate the first
    JSON object, parse, validate. Fall back gracefully if any step
    breaks."""
    if not text:
        return _fallback(title, extract)

    candidate = _strip_fences(text)
    try:
        obj = json.loads(candidate)
    except json.JSONDecodeError:
        obj = _first_json_object(candidate)
        if obj is None:
            logger.warning("LLM returned non-JSON for '%s': %s", title, text[:120])
            return _fallback(title, extract)

    try:
        bundle = SummaryBundle.model_validate(obj)
    except ValidationError as e:
        logger.warning("LLM JSON failed schema for '%s': %s", title, e)
        return _fallback(title, extract)
    # Defensive: if the LLM returns an out-of-set feature_kind
    # (typo, prompt drift), normalize to the safe default rather
    # than letting downstream filters fail on it.
    if bundle.feature_kind not in ALLOWED_FEATURE_KINDS:
        logger.warning(
            "LLM returned unknown feature_kind=%r for '%s'; defaulting to landmark",
            bundle.feature_kind, title,
        )
        bundle = bundle.model_copy(update={"feature_kind": "landmark"})
    return bundle


def _strip_fences(text: str) -> str:
    """Strip ```json ... ``` wrappers that some models add despite
    being told not to."""
    text = text.strip()
    if text.startswith("```"):
        # Drop the first line (which is the fence) and the closing fence
        lines = text.splitlines()
        if lines and lines[-1].strip().startswith("```"):
            lines = lines[:-1]
        if lines and lines[0].strip().startswith("```"):
            lines = lines[1:]
        text = "\n".join(lines).strip()
    return text


def _first_json_object(text: str) -> Optional[dict]:
    """Locate the first {...} block in `text` and try to parse it as
    JSON. Handles cases where the model adds a sentence before/after
    the JSON despite the instruction."""
    start = text.find("{")
    if start == -1:
        return None
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(text[start : i + 1])
                except json.JSONDecodeError:
                    return None
    return None


def _fallback(title: str, extract: str) -> SummaryBundle:
    """Best-effort bundle when the LLM is unreachable or
    misbehaving. The first sentence of the Wikipedia lede is
    usually a definitional one ("X is a town in Y County") — not
    magical, but at least factually safe. We mark `is_thin=True`
    so the UI doesn't promise follow-ups we don't have.
    """
    first_sentence = ""
    if extract:
        # Naive first-sentence split — good enough for fallback.
        for delimiter in (". ", ".\n"):
            idx = extract.find(delimiter)
            if idx != -1:
                first_sentence = extract[: idx + 1].strip()
                break
        if not first_sentence:
            first_sentence = extract[:240].strip()
    if not first_sentence:
        first_sentence = f"There's a place called {title} along your route."
    return SummaryBundle(
        primary=first_sentence,
        follow_ups=[],
        is_thin=True,
        feature_kind="landmark",  # strictest default — see prompt
    )
