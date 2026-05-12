"""
Score candidate POIs as proactive stop suggestions during navigation, or
as planning-time options before driving.

Designed against `docs/recommendations-brief.md`. The brief is the source
of truth for *why* each rule exists; this file is the *what*. If you find
yourself making changes here that aren't traceable to the brief, stop and
amend the brief first.

The engine has two stages:
  1. **Hard filters** — drop candidates that violate non-negotiable rules
     (quality bar per mode, detour cap, surface-specific silence rules).
  2. **Additive scoring** — each remaining candidate gets +/- contributions
     from each of the four core dimensions (trip scale, time-budget mode,
     user-state context, quality signal) plus personalization (interests
     and categories). The strongest contributor wins the displayed reason.

Weights are starting points for calibration, not constants. The brief's
"Calibration plan" describes how they get tuned against real-trip data.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Iterable, List, Optional

from app.models import POI, CATEGORY_DURATION_MAP, POICategory
from app.utils.polyline import TripScale


# =============================================================================
# Mode + invocation enums
# =============================================================================


class TimeBudgetMode(str, Enum):
    """Profile-level posture from `docs/recommendations-brief.md` →
    "Time-budget mode"."""
    HURRY = "hurry"
    MODERATE = "moderate"
    DISCOVERY = "discovery"


class Invocation(str, Enum):
    """Which surface called the engine. Drives surface-specific behavior —
    notably the auto-poll silence rules vs always-respond posture for
    user-initiated surfaces."""
    AUTO = "auto"           # in-nav background poll
    MANUAL = "manual"       # in-nav "Suggest a stop" FAB
    PLANNING = "planning"   # pre-trip planning canvas
    VOICE = "voice"         # future LLM-parsed natural-language ask


# =============================================================================
# Per-mode thresholds (brief: "Time-budget mode" table)
# =============================================================================


@dataclass(frozen=True)
class ModeThresholds:
    rating_floor: float            # POIs below this get filtered (when rating known)
    max_stop_minutes: int          # Filter POIs whose estimated stop exceeds this
    max_detour_miles: float        # Filter POIs further off-route than this
    practical_only: bool           # If True, drop non-practical categories
    min_score: float               # Score floor for a candidate to surface


_THRESHOLDS: dict[TimeBudgetMode, ModeThresholds] = {
    TimeBudgetMode.HURRY: ModeThresholds(
        rating_floor=4.5,
        max_stop_minutes=15,
        max_detour_miles=0.5,
        practical_only=True,
        min_score=0.30,
    ),
    TimeBudgetMode.MODERATE: ModeThresholds(
        rating_floor=4.0,
        max_stop_minutes=30,
        max_detour_miles=2.0,
        practical_only=False,
        min_score=0.15,
    ),
    TimeBudgetMode.DISCOVERY: ModeThresholds(
        rating_floor=3.5,
        max_stop_minutes=90,
        max_detour_miles=5.0,
        practical_only=False,
        min_score=0.05,
    ),
}


# Categories considered "practical" (need-based) rather than discretionary.
# Used by hurry mode and by the hours-since-last-stop bias.
_PRACTICAL = {"gas_station", "pharmacy", "hospital"}
# When the driver hasn't stopped in 2.5+ hours, food and coffee become
# practical too — they're no longer optional.
_PRACTICAL_WHEN_OVERDUE = _PRACTICAL | {"restaurant", "coffee"}

# Hours-since-last-stop threshold above which the system biases toward
# practical/food/coffee categories. Brief: "Hours-since-last-stop > 2.5".
_OVERDUE_HOURS = 2.5

# Categories considered "novel" for discovery-mode bonus. Currently the
# delight-leaning subset of Mapbox categories.
_NOVEL = {"scenic", "attraction", "museum", "park"}


# =============================================================================
# Scoring weights (the levers the calibration plan tunes)
# =============================================================================


_W_INTEREST_MATCH = 0.40   # heaviest personalization signal (brief)
_W_CATEGORY_MATCH = 0.20
_W_HISTORY_FAMILIAR = 0.15
_W_HOUR_PATTERN = 0.20
_W_OVERDUE_PRACTICAL = 0.25
_W_NOVEL_IN_DISCOVERY = 0.10
_W_DETOUR_PENALTY_PER_MILE = -0.05  # only applied for excess beyond 1 mi
_DETOUR_FREE_RADIUS = 1.0


# =============================================================================
# Engine data classes
# =============================================================================


@dataclass
class ScoredPOI:
    poi: POI
    score: float
    reason: str
    reasons: List[str] = field(default_factory=list)  # debug only


# =============================================================================
# Helpers
# =============================================================================


def _is_practical(category: str, hours_since_last_stop: Optional[float]) -> bool:
    """A category is practical if it's a need (gas, pharmacy, hospital), OR
    food/coffee when the driver is overdue for a stop."""
    if category in _PRACTICAL:
        return True
    if hours_since_last_stop is not None and hours_since_last_stop >= _OVERDUE_HOURS:
        return category in _PRACTICAL_WHEN_OVERDUE
    return False


def _hour_pattern_match(now_hour: int, by_hour: list[dict]) -> float:
    """Fraction of the user's historical stops within ±1 hr of now_hour.
    Returns 0.0 when there's not enough history (noise floor of 5 stops)."""
    if not by_hour:
        return 0.0
    counts = {row["hour"]: row["count"] for row in by_hour}
    total = sum(counts.values())
    if total < 5:
        return 0.0
    nearby = sum(counts.get(h, 0) for h in (now_hour - 1, now_hour, now_hour + 1))
    return nearby / total


def _interest_matches(poi: POI, interests: list[dict]) -> list[dict]:
    """Return interests whose mapbox_categories include this POI's category
    OR whose keywords appear in the POI's name. List-shaped because a single
    POI can satisfy multiple interests (each match contributes to the score
    independently, capped by the count to avoid runaway scores)."""
    if not interests:
        return []
    name_lower = (poi.name or "").lower()
    matches: list[dict] = []
    for interest in interests:
        mb_cats = interest.get("mapbox_categories") or []
        keywords = interest.get("keywords") or []
        if poi.category in mb_cats:
            matches.append(interest)
            continue
        if any(k.lower() in name_lower for k in keywords):
            matches.append(interest)
    return matches


def _estimated_duration(category_str: str) -> int:
    try:
        return CATEGORY_DURATION_MAP[POICategory(category_str)]
    except (ValueError, KeyError):
        return 30


# =============================================================================
# Hard filter (returns None if the POI should be dropped)
# =============================================================================


def _passes_hard_filters(
    poi: POI,
    *,
    thresholds: ModeThresholds,
    hours_since_last_stop: Optional[float],
    trip_scale: TripScale,
    invocation: Invocation,
) -> Optional[str]:
    """Return None if the POI passes; else a short reason string for why it
    was dropped (used for debug logging upstream)."""
    # Quality bar: rating floor (only when the rating is known — POIs with
    # no rating get a pass; we don't have enough info to reject them).
    if poi.rating is not None and poi.rating < thresholds.rating_floor:
        return f"rating {poi.rating} below {thresholds.rating_floor}"

    # Detour cap: hard filter beyond the mode's max.
    if poi.distance_from_route_miles > thresholds.max_detour_miles:
        return (
            f"detour {poi.distance_from_route_miles:.1f}mi exceeds "
            f"{thresholds.max_detour_miles:.1f}mi"
        )

    # Stop length cap. Use the POI's own estimated_duration_minutes
    # (set by the Mapbox/discovery pipeline), not the category default —
    # specific POIs can shorten/lengthen the generic category estimate.
    duration = poi.estimated_duration_minutes
    if duration > thresholds.max_stop_minutes:
        return f"duration {duration}min exceeds {thresholds.max_stop_minutes}min"

    # Practical-only mode (hurry, or local + auto-poll).
    practical_only = thresholds.practical_only or (
        trip_scale == TripScale.LOCAL and invocation == Invocation.AUTO
    )
    if practical_only and not _is_practical(poi.category, hours_since_last_stop):
        return f"non-practical category {poi.category} in restricted mode"

    return None


# =============================================================================
# Score (assumes the POI already passed hard filters)
# =============================================================================


def score_poi(
    poi: POI,
    *,
    profile_categories: Iterable[str],
    profile_interests: list[dict],
    category_averages: dict[str, dict],
    by_hour: list[dict],
    mode: TimeBudgetMode,
    hours_since_last_stop: Optional[float],
    now: datetime,
) -> ScoredPOI:
    """Additive scorer. Each dimension contributes independently; the
    strongest factor wins the displayed reason. See module docstring
    for the rule provenance."""
    score = 0.0
    reasons: list[tuple[float, str]] = []
    debug: list[str] = []

    # --- Layer 1: specific interests (heaviest weight) ---
    matched_interests = _interest_matches(poi, profile_interests)
    if matched_interests:
        # Cap stacking at 2 to avoid an unbalanced score from a POI that
        # incidentally matches several keywords. Brief mentions interests
        # carry heavier weight; doesn't license unbounded stacking.
        delta = _W_INTEREST_MATCH * min(len(matched_interests), 2)
        score += delta
        label = matched_interests[0].get("label") or "your interests"
        reasons.append((delta, f"Matches your interest in {label}"))
        debug.append(
            f"+{delta:.2f} interests ({[m.get('label') for m in matched_interests]})"
        )

    # --- Layer 2: broad categories ---
    if poi.category in set(profile_categories or []):
        score += _W_CATEGORY_MATCH
        reasons.append(
            (_W_CATEGORY_MATCH, f"You like {poi.category.replace('_', ' ')}s")
        )
        debug.append(f"+{_W_CATEGORY_MATCH:.2f} preferred category ({poi.category})")

    # --- Cross-trip history: category familiarity ---
    cat_avg = category_averages.get(poi.category) if category_averages else None
    if cat_avg and cat_avg.get("count", 0) > 0:
        avg_mins = round(cat_avg.get("avg_actual_minutes") or 0)
        score += _W_HISTORY_FAMILIAR
        reasons.append(
            (
                _W_HISTORY_FAMILIAR,
                f"You usually stay {avg_mins} min at "
                f"{poi.category.replace('_', ' ')}s",
            )
        )
        debug.append(
            f"+{_W_HISTORY_FAMILIAR:.2f} history ({cat_avg['count']} prior stops)"
        )

    # --- User-state context: hour-of-day pattern ---
    match = _hour_pattern_match(now.hour, by_hour)
    if match > 0.2:
        score += _W_HOUR_PATTERN
        reasons.append(
            (_W_HOUR_PATTERN, f"You often stop around {now.hour:02d}:00")
        )
        debug.append(f"+{_W_HOUR_PATTERN:.2f} hour-of-day match ({match:.2f})")

    # --- User-state context: hours-since-last-stop bias ---
    if (
        hours_since_last_stop is not None
        and hours_since_last_stop >= _OVERDUE_HOURS
        and poi.category in _PRACTICAL_WHEN_OVERDUE
    ):
        score += _W_OVERDUE_PRACTICAL
        reasons.append(
            (
                _W_OVERDUE_PRACTICAL,
                f"You've been driving {hours_since_last_stop:.1f}h — time for a break",
            )
        )
        debug.append(
            f"+{_W_OVERDUE_PRACTICAL:.2f} overdue ({hours_since_last_stop:.1f}h)"
        )

    # --- Mode-aware delight bonus: novel categories in Discovery ---
    if mode == TimeBudgetMode.DISCOVERY and poi.category in _NOVEL:
        score += _W_NOVEL_IN_DISCOVERY
        reasons.append(
            (_W_NOVEL_IN_DISCOVERY, f"Something to explore: {poi.category.replace('_', ' ')}")
        )
        debug.append(f"+{_W_NOVEL_IN_DISCOVERY:.2f} novel-in-discovery ({poi.category})")

    # --- Quality signal: detour penalty within mode's cap ---
    # Hard filter already rejected POIs beyond max_detour_miles. This
    # subtracts a small penalty for POIs that are off-route within the cap.
    excess = max(0.0, poi.distance_from_route_miles - _DETOUR_FREE_RADIUS)
    if excess > 0:
        delta = _W_DETOUR_PENALTY_PER_MILE * excess
        score += delta
        debug.append(
            f"{delta:+.2f} off-route ({poi.distance_from_route_miles:.1f}mi)"
        )

    if reasons:
        reasons.sort(key=lambda r: -r[0])
        reason = reasons[0][1]
    else:
        reason = "Suggested stop along your route"

    return ScoredPOI(poi=poi, score=score, reason=reason, reasons=debug)


# =============================================================================
# Top-level entry point
# =============================================================================


def rank_suggestions(
    pois: Iterable[POI],
    *,
    profile_categories: Iterable[str] = (),
    profile_interests: list[dict] = None,
    category_averages: dict[str, dict] = None,
    by_hour: list[dict] = None,
    mode: TimeBudgetMode = TimeBudgetMode.MODERATE,
    trip_scale: TripScale = TripScale.REGIONAL,
    invocation: Invocation = Invocation.AUTO,
    hours_since_last_stop: Optional[float] = None,
    now: Optional[datetime] = None,
    limit: int = 3,
) -> List[ScoredPOI]:
    """Apply hard filters, score what's left, return the top `limit` whose
    score clears the mode's `min_score` floor, best first.

    Manual / planning / voice invocations *always* respond (per brief),
    so the min_score floor is relaxed for them — even a mediocre best
    pick is better than silence when the user explicitly asked. Auto
    invocations enforce the floor strictly.
    """
    profile_interests = profile_interests or []
    category_averages = category_averages or {}
    by_hour = by_hour or []
    now = now or datetime.utcnow()
    thresholds = _THRESHOLDS[mode]

    survivors: list[POI] = []
    for poi in pois:
        drop_reason = _passes_hard_filters(
            poi,
            thresholds=thresholds,
            hours_since_last_stop=hours_since_last_stop,
            trip_scale=trip_scale,
            invocation=invocation,
        )
        if drop_reason is None:
            survivors.append(poi)

    scored = [
        score_poi(
            p,
            profile_categories=profile_categories,
            profile_interests=profile_interests,
            category_averages=category_averages,
            by_hour=by_hour,
            mode=mode,
            hours_since_last_stop=hours_since_last_stop,
            now=now,
        )
        for p in survivors
    ]

    # Surface-specific floor: auto-poll enforces the mode's min_score
    # strictly; user-initiated surfaces always return their best pick
    # if there is one, even below the floor (brief: "user-initiated
    # surfaces are always responsive").
    if invocation == Invocation.AUTO:
        scored = [s for s in scored if s.score >= thresholds.min_score]

    scored.sort(key=lambda s: -s.score)
    return scored[:limit]
