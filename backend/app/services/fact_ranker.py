"""
Rank Wikipedia fact candidates and pick the top-N to summarize.

This runs *between* discovery (`wikipedia_facts.py`) and LLM voice
shaping (`llm_summarizer.py`). Its job is to spend LLM tokens on
the candidates most likely to produce a magical 15-second whisper,
and to throw away the ones that would only ever generate stub prose
("Smithville is a town in Y County.").

Per `Overview.md` and the companion plan, the score is a weighted
sum of:
  - Uniqueness (article length proxy — quirky/specific beats stubs)
  - Local relevance (close-to-route beats far-off)
  - Interest fit (matches user's UserProfile.interests when present)

We deliberately do NOT score brevity here — the LLM produces brevity
itself, and rewarding short Wikipedia articles would push us toward
stubs, which is the opposite of what we want.

See: ~/.claude/plans/breezy-gliding-mountain.md → "fact_ranker.py"
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

from app.services.wikipedia_facts import FactCandidate

logger = logging.getLogger(__name__)


# Scoring weights. The defaults express the editorial bias:
# substance first, then relevance, then personalization. Tune
# against real routes when we have a feel-test signal.
_W_UNIQUENESS = 0.50
_W_LOCAL_RELEVANCE = 0.30
_W_INTEREST_FIT = 0.20

# Articles below this length are nearly always stubs ("X is a town
# in Y County. Population 1,200."). Demote hard.
_STUB_CHAR_THRESHOLD = 600

# Distance bands for local relevance. Anything within `_NEAR_ROUTE_MI`
# gets the full local-relevance bonus; the score decays linearly to
# zero by `_FAR_ROUTE_MI`. Beyond that, it's noise.
_NEAR_ROUTE_MI = 1.0
_FAR_ROUTE_MI = 10.0

# Per-trip cap on how many candidates we forward to the LLM. Cost
# control: ~30 articles × Haiku call ≈ ~$0.03 per first-time route.
# Most users will re-drive familiar routes, hitting the per-pageid
# cache and paying nothing thereafter.
DEFAULT_TOP_N = 30


@dataclass
class RankedFact:
    """A candidate enriched with its ranking score. Order of fields
    matters — `score` first so sorted() naturally descends by score
    when reversed."""
    candidate: FactCandidate
    score: float
    score_breakdown: dict


def rank_candidates(
    candidates: list[FactCandidate],
    *,
    user_interests: list[dict] | None = None,
    top_n: int = DEFAULT_TOP_N,
) -> list[RankedFact]:
    """Score every candidate, sort by score desc, return top-N.

    `user_interests` follows the `UserProfile.interests` shape:
    list of `{label, mapbox_categories, keywords}`. The label and
    keywords get matched (case-insensitive substring) against the
    article title + extract; matches lift the candidate.
    """
    if not candidates:
        return []

    interests_normalized = _normalize_interests(user_interests or [])
    ranked: list[RankedFact] = []
    for c in candidates:
        breakdown = {
            "uniqueness": _score_uniqueness(c),
            "local_relevance": _score_local_relevance(c),
            "interest_fit": _score_interest_fit(c, interests_normalized),
        }
        total = (
            _W_UNIQUENESS * breakdown["uniqueness"]
            + _W_LOCAL_RELEVANCE * breakdown["local_relevance"]
            + _W_INTEREST_FIT * breakdown["interest_fit"]
        )
        ranked.append(RankedFact(
            candidate=c,
            score=total,
            score_breakdown=breakdown,
        ))

    ranked.sort(key=lambda r: r.score, reverse=True)
    return ranked[:top_n]


def _score_uniqueness(c: FactCandidate) -> float:
    """Article-length proxy. Stubs get hammered; longer articles
    (more substance, more interesting tangents available to the
    LLM) get rewarded.

    Returns 0.0 to 1.0. The curve is intentionally non-linear:
    big jump above the stub threshold, gentle slope after.
    """
    length = c.article_length
    if length < _STUB_CHAR_THRESHOLD:
        # Stub. Hard demotion — barely above zero.
        return length / (_STUB_CHAR_THRESHOLD * 4)
    # Above stub: ramps from 0.25 toward 1.0 as length grows,
    # plateauing around 8000 chars (typical mid-quality article).
    above = length - _STUB_CHAR_THRESHOLD
    return min(1.0, 0.25 + 0.75 * (above / 8000))


def _score_local_relevance(c: FactCandidate) -> float:
    """1.0 when within `_NEAR_ROUTE_MI`, decays linearly to 0.0
    at `_FAR_ROUTE_MI`. Far-off articles still get a chance
    because some big-deal landmarks (a national park visitor
    center, a historic town) are worth a small detour."""
    d = c.distance_from_route_miles
    if d <= _NEAR_ROUTE_MI:
        return 1.0
    if d >= _FAR_ROUTE_MI:
        return 0.0
    return 1.0 - (d - _NEAR_ROUTE_MI) / (_FAR_ROUTE_MI - _NEAR_ROUTE_MI)


def _score_interest_fit(
    c: FactCandidate,
    interests_normalized: list[set[str]],
) -> float:
    """0.0 when the user has no interests or none match; 1.0 when at
    least one interest token appears in the article. The full
    binary jump is deliberate — even a single match is significant
    signal, and we don't want to spend cycles weighting partial
    matches against each other."""
    if not interests_normalized:
        return 0.0
    haystack = (c.title + " " + c.extract).lower()
    for interest_tokens in interests_normalized:
        if any(token in haystack for token in interest_tokens):
            return 1.0
    return 0.0


def _normalize_interests(interests: list[dict]) -> list[set[str]]:
    """Flatten the user interests list into one set of lowercase
    tokens per interest. Each interest contributes its label plus
    its keywords; mapbox_categories are skipped because they don't
    appear in prose (e.g. 'tourist_attraction' won't match an
    article body)."""
    out: list[set[str]] = []
    for interest in interests:
        if not isinstance(interest, dict):
            continue
        tokens: set[str] = set()
        label = interest.get("label")
        if isinstance(label, str) and label.strip():
            tokens.add(label.lower().strip())
        kws = interest.get("keywords") or []
        for kw in kws:
            if isinstance(kw, str) and kw.strip():
                tokens.add(kw.lower().strip())
        if tokens:
            out.append(tokens)
    return out
