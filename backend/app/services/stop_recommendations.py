"""
Score candidate POIs as potential proactive stop suggestions during navigation.

Inputs are POIs already produced by the discovery pipeline plus the user's
profile and stop history; output is a small ranked list with a human-readable
reason for each.

Scoring is rule-based (additive). Each factor independently nudges the score
and contributes a candidate reason string; the strongest factor wins the
displayed reason.

  +0.30 — POI category is in the user's preferred list
  +0.20 — current hour matches a time-of-day the user typically stops
  +0.15 — user has stopped at this category before (history familiarity)
  +0.10 — estimated stop duration fits remaining trip budget
  −0.50 — stop duration *exceeds* remaining budget (strong demotion)
  −0.05 — per mile of detour beyond 1 mile off-route

Intentionally simple: rules over ML so we can reason about behavior with
~zero history, debug per-user output, and ship without training data.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Iterable, List, Optional

from app.models import POI, CATEGORY_DURATION_MAP, POICategory


@dataclass
class ScoredPOI:
    poi: POI
    score: float
    reason: str
    # Kept for tests / debugging; not serialized to the wire by default.
    reasons: List[str] = field(default_factory=list)


def _estimated_duration(category_str: str) -> int:
    try:
        return CATEGORY_DURATION_MAP[POICategory(category_str)]
    except (ValueError, KeyError):
        return 30


def _hour_pattern_match(now_hour: int, by_hour: list[dict]) -> float:
    """Fraction of historical stops that happened within ±1 hour of `now_hour`.
    Returns 0.0 when there's not enough history to be meaningful.
    """
    if not by_hour:
        return 0.0
    counts = {row["hour"]: row["count"] for row in by_hour}
    total = sum(counts.values())
    if total < 5:  # noise floor — need at least 5 historical stops
        return 0.0
    nearby = sum(counts.get(h, 0) for h in (now_hour - 1, now_hour, now_hour + 1))
    return nearby / total


def score_poi(
    poi: POI,
    *,
    preferred_categories: Iterable[str],
    category_averages: dict[str, dict],
    by_hour: list[dict],
    remaining_budget_minutes: Optional[int],
    now: datetime,
) -> ScoredPOI:
    """Score one candidate POI.

    `category_averages` shape: `{ "restaurant": {"count": 4, "avg_actual_minutes": 47.5, ...}, ... }`
    `by_hour` shape: `[{"hour": 11, "count": 3}, ...]`
    """
    score = 0.0
    reasons: list[tuple[float, str]] = []
    debug: list[str] = []

    prefs = set(preferred_categories or [])
    if poi.category in prefs:
        score += 0.30
        reasons.append((0.30, f"You like {poi.category.replace('_', ' ')}s"))
        debug.append(f"+0.30 preferred ({poi.category})")

    cat_avg = category_averages.get(poi.category)
    if cat_avg and cat_avg.get("count", 0) > 0:
        score += 0.15
        avg_mins = round(cat_avg.get("avg_actual_minutes") or 0)
        reasons.append(
            (
                0.15,
                f"You usually stay {avg_mins} min at {poi.category.replace('_', ' ')}s",
            )
        )
        debug.append(f"+0.15 history ({cat_avg['count']} prior stops)")

    match = _hour_pattern_match(now.hour, by_hour)
    if match > 0.2:
        score += 0.20
        reasons.append((0.20, f"You often stop around {now.hour:02d}:00"))
        debug.append(f"+0.20 hour-of-day match ({match:.2f})")

    duration = _estimated_duration(poi.category)
    if remaining_budget_minutes is not None:
        if duration > remaining_budget_minutes:
            score -= 0.50
            debug.append(
                f"-0.50 over budget ({duration} > {remaining_budget_minutes})"
            )
        else:
            score += 0.10
            debug.append(f"+0.10 fits budget ({duration} <= {remaining_budget_minutes})")

    # Distance-off-route penalty: 0 within 1 mile, then -0.05/mile.
    excess = max(0.0, poi.distance_from_route_miles - 1.0)
    if excess > 0:
        delta = -0.05 * excess
        score += delta
        debug.append(f"{delta:+.2f} off-route ({poi.distance_from_route_miles:.1f}mi)")

    if reasons:
        reasons.sort(key=lambda r: -r[0])
        reason = reasons[0][1]
    else:
        reason = "Suggested stop along your route"

    return ScoredPOI(poi=poi, score=score, reason=reason, reasons=debug)


def rank_suggestions(
    pois: Iterable[POI],
    *,
    preferred_categories: Iterable[str],
    category_averages: dict[str, dict],
    by_hour: list[dict],
    remaining_budget_minutes: Optional[int],
    now: datetime,
    limit: int = 3,
    min_score: float = 0.15,
) -> List[ScoredPOI]:
    """Score every POI; return the top `limit` whose score >= `min_score`,
    best first. `min_score` keeps a totally-cold-start user (no history,
    no prefs) from getting noisy zero-score recommendations.
    """
    scored = [
        score_poi(
            poi,
            preferred_categories=preferred_categories,
            category_averages=category_averages,
            by_hour=by_hour,
            remaining_budget_minutes=remaining_budget_minutes,
            now=now,
        )
        for poi in pois
    ]
    scored = [s for s in scored if s.score >= min_score]
    scored.sort(key=lambda s: -s.score)
    return scored[:limit]
