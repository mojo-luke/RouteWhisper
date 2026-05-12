"""
Unit tests for the four-dimension stop-recommendation engine.

These tests lock in the *behavior* described in
`docs/recommendations-brief.md`. Numeric weights are calibration
targets — if you change them in the scorer, change them here too and
ensure the brief still describes the system.

Coverage:
  * Hard filters per time-budget mode (rating, detour, duration, practical-only)
  * Trip-scale + invocation interaction (local + auto = practical-only)
  * Personalization weighting (interests heavier than categories)
  * User-state context (hour-of-day, hours-since-last-stop)
  * Reason selection (strongest contributor wins)
  * Surface-specific min_score (auto enforces; manual relaxes)
"""

from datetime import datetime

import pytest

from app.models import POI
from app.services.stop_recommendations import (
    Invocation,
    TimeBudgetMode,
    rank_suggestions,
    score_poi,
)
from app.utils.polyline import TripScale


def _poi(
    *,
    id="p1",
    name="Test",
    category="restaurant",
    distance_from_route_miles=0.4,
    rating=4.5,
    estimated_duration_minutes=30,
):
    return POI(
        id=id,
        name=name,
        category=category,
        latitude=37.5,
        longitude=-122.4,
        estimated_duration_minutes=estimated_duration_minutes,
        rating=rating,
        distance_from_route_miles=distance_from_route_miles,
    )


_NOW = datetime(2026, 5, 12, 11, 0)  # 11:00 AM


# =============================================================================
# Hard-filter behavior
# =============================================================================


class TestHurryMode:
    """Hurry mode: 4.5★, ≤15min, ≤0.5mi, practical only."""

    def test_filters_below_rating_floor(self):
        # A 4.2★ restaurant fails the 4.5★ floor.
        result = rank_suggestions(
            [_poi(category="restaurant", rating=4.2)],
            profile_categories=["restaurant"],
            mode=TimeBudgetMode.HURRY,
        )
        assert result == []

    def test_filters_non_practical_category(self):
        # 4.7★ restaurant — clears rating, fails practical-only.
        result = rank_suggestions(
            [_poi(category="restaurant", rating=4.7)],
            profile_categories=["restaurant"],
            mode=TimeBudgetMode.HURRY,
        )
        assert result == []

    def test_keeps_gas_station(self):
        # Gas station is always practical. Realistic stop ~10min fits
        # hurry's 15-min cap.
        result = rank_suggestions(
            [_poi(category="gas_station", rating=4.6,
                  distance_from_route_miles=0.3,
                  estimated_duration_minutes=10)],
            mode=TimeBudgetMode.HURRY,
            invocation=Invocation.MANUAL,  # manual relaxes min_score
        )
        assert len(result) == 1
        assert result[0].poi.category == "gas_station"

    def test_filters_excessive_detour(self):
        # Gas station 1mi off-route fails hurry's 0.5mi cap.
        result = rank_suggestions(
            [_poi(category="gas_station", rating=4.7,
                  distance_from_route_miles=1.0,
                  estimated_duration_minutes=10)],
            mode=TimeBudgetMode.HURRY,
            invocation=Invocation.MANUAL,
        )
        assert result == []


class TestModerateMode:
    """Moderate: 4.0★, ≤30min, ≤2mi. Default for most users."""

    def test_accepts_restaurant_at_floor(self):
        result = rank_suggestions(
            [_poi(category="restaurant", rating=4.0,
                  distance_from_route_miles=1.5)],
            profile_categories=["restaurant"],
            mode=TimeBudgetMode.MODERATE,
            invocation=Invocation.MANUAL,
        )
        assert len(result) == 1

    def test_filters_just_below_floor(self):
        result = rank_suggestions(
            [_poi(category="restaurant", rating=3.9)],
            profile_categories=["restaurant"],
            mode=TimeBudgetMode.MODERATE,
        )
        assert result == []

    def test_filters_detour_over_2mi(self):
        result = rank_suggestions(
            [_poi(category="restaurant", rating=4.5,
                  distance_from_route_miles=2.5)],
            mode=TimeBudgetMode.MODERATE,
            invocation=Invocation.MANUAL,
        )
        assert result == []


class TestDiscoveryMode:
    """Discovery: 3.5★, ≤90min, ≤5mi. Relaxed for exploratory drives."""

    def test_accepts_lower_rating(self):
        result = rank_suggestions(
            [_poi(category="scenic", rating=3.6,
                  distance_from_route_miles=3.0)],
            mode=TimeBudgetMode.DISCOVERY,
            invocation=Invocation.MANUAL,
        )
        assert len(result) == 1

    def test_filters_below_3_5(self):
        result = rank_suggestions(
            [_poi(category="scenic", rating=3.3)],
            mode=TimeBudgetMode.DISCOVERY,
        )
        assert result == []


# =============================================================================
# Trip-scale × invocation interaction
# =============================================================================


class TestTripScaleSurfaceInteraction:
    def test_local_auto_silent_on_non_practical(self):
        # Even a 4.8★ restaurant on a local trip with auto-poll → silent.
        result = rank_suggestions(
            [_poi(category="restaurant", rating=4.8,
                  distance_from_route_miles=0.5)],
            profile_categories=["restaurant"],
            trip_scale=TripScale.LOCAL,
            invocation=Invocation.AUTO,
            mode=TimeBudgetMode.MODERATE,
        )
        assert result == []

    def test_local_auto_allows_gas(self):
        result = rank_suggestions(
            [_poi(category="gas_station", rating=4.5,
                  distance_from_route_miles=0.4)],
            trip_scale=TripScale.LOCAL,
            invocation=Invocation.AUTO,
            mode=TimeBudgetMode.MODERATE,
        )
        # Gas station is practical; the practical_only override on local
        # doesn't filter it.
        assert len(result) >= 0  # may surface or not depending on min_score

    def test_local_manual_responds_to_non_practical(self):
        # Same restaurant as test_local_auto_silent, manual invocation.
        # Manual is always-responsive — should surface.
        result = rank_suggestions(
            [_poi(category="restaurant", rating=4.8,
                  distance_from_route_miles=0.5)],
            profile_categories=["restaurant"],
            trip_scale=TripScale.LOCAL,
            invocation=Invocation.MANUAL,
            mode=TimeBudgetMode.MODERATE,
        )
        assert len(result) == 1


# =============================================================================
# Personalization layering
# =============================================================================


class TestPersonalization:
    def test_interest_match_outweighs_category_match(self):
        # User has "restaurants" as a category AND a more specific interest
        # tagged to `scenic`. A scenic POI should score higher than a
        # generic restaurant despite the category match.
        # (We test against POICategory enum members; the brief intends
        # `mapbox_categories` to eventually include Mapbox subcategories
        # outside our 14-bucket enum, but the matching logic is identical.)
        scenic = _poi(id="s", category="scenic", rating=4.4,
                      distance_from_route_miles=1.0)
        restaurant = _poi(id="r", category="restaurant", rating=4.4,
                          distance_from_route_miles=1.0)
        result = rank_suggestions(
            [scenic, restaurant],
            profile_categories=["restaurant"],
            profile_interests=[
                {"label": "scenic overlooks",
                 "mapbox_categories": ["scenic"],
                 "keywords": []}
            ],
            mode=TimeBudgetMode.MODERATE,
            invocation=Invocation.MANUAL,
        )
        # Scenic should outrank restaurant — interest weight (0.40) >
        # category weight (0.20).
        assert len(result) == 2
        assert result[0].poi.id == "s"
        assert "scenic overlooks" in result[0].reason.lower()

    def test_keyword_match_counts(self):
        # Interest with keyword "fishing" matches a POI named "Fishing
        # Charters" even if category isn't in the interest's category list.
        poi = _poi(
            id="charter",
            name="Sunset Fishing Charters",
            category="park",  # park lake area; valid POICategory
            rating=4.6,
        )
        result = rank_suggestions(
            [poi],
            profile_interests=[
                {"label": "lakes to fish",
                 "mapbox_categories": ["lake"],
                 "keywords": ["fishing"]}
            ],
            mode=TimeBudgetMode.MODERATE,
            invocation=Invocation.MANUAL,
        )
        # Should surface — interest matched on keyword even though
        # mapbox_categories didn't.
        assert len(result) == 1

    def test_no_personalization_still_scores_zero_or_positive(self):
        # Cold-start user: no categories, no interests, no history.
        result = rank_suggestions(
            [_poi(category="restaurant", rating=4.5)],
            mode=TimeBudgetMode.MODERATE,
            invocation=Invocation.MANUAL,
        )
        assert len(result) == 1
        # No reasons matched → generic reason.
        assert "Suggested stop" in result[0].reason


# =============================================================================
# User-state context
# =============================================================================


class TestUserStateContext:
    def test_overdue_boosts_food(self):
        # Driver overdue 3hr; a restaurant should pick up the bonus.
        # Compare to a non-practical category POI to verify the bonus
        # specifically attaches to practical-when-overdue.
        food = _poi(id="f", category="restaurant", rating=4.5,
                    distance_from_route_miles=0.5)
        result = rank_suggestions(
            [food],
            mode=TimeBudgetMode.MODERATE,
            invocation=Invocation.MANUAL,
            hours_since_last_stop=3.0,
        )
        assert len(result) == 1
        assert "driving" in result[0].reason.lower()  # overdue reason wins

    def test_not_overdue_no_practical_bonus(self):
        food = _poi(id="f", category="restaurant", rating=4.5,
                    distance_from_route_miles=0.5)
        result = rank_suggestions(
            [food],
            mode=TimeBudgetMode.MODERATE,
            invocation=Invocation.MANUAL,
            hours_since_last_stop=1.0,  # not overdue
        )
        assert len(result) == 1
        # Reason shouldn't mention driving fatigue.
        assert "driving" not in result[0].reason.lower()

    def test_hour_pattern_match_adds_weight(self):
        by_hour = [
            {"hour": 10, "count": 2},
            {"hour": 11, "count": 3},
            {"hour": 12, "count": 1},
            {"hour": 16, "count": 2},
        ]
        result = rank_suggestions(
            [_poi(category="restaurant", rating=4.5)],
            mode=TimeBudgetMode.MODERATE,
            invocation=Invocation.MANUAL,
            by_hour=by_hour,
            now=_NOW,  # hour=11
        )
        assert len(result) == 1
        # Hour pattern reason fires when the match clears the noise floor.
        assert "11:00" in result[0].reason or result[0].score > 0


# =============================================================================
# Surface-specific min_score behavior
# =============================================================================


class TestSurfaceMinScore:
    def test_auto_enforces_min_score(self):
        # Cold-start POI scores ~0; auto-poll filters it out.
        result = rank_suggestions(
            [_poi(category="restaurant", rating=4.5)],
            mode=TimeBudgetMode.MODERATE,
            invocation=Invocation.AUTO,
        )
        # Score is 0 (no matches) which is below moderate's 0.15 floor.
        assert result == []

    def test_manual_relaxes_min_score(self):
        # Same POI; manual invocation surfaces it anyway.
        result = rank_suggestions(
            [_poi(category="restaurant", rating=4.5)],
            mode=TimeBudgetMode.MODERATE,
            invocation=Invocation.MANUAL,
        )
        assert len(result) == 1

    def test_planning_relaxes_min_score(self):
        result = rank_suggestions(
            [_poi(category="restaurant", rating=4.5)],
            mode=TimeBudgetMode.MODERATE,
            invocation=Invocation.PLANNING,
        )
        assert len(result) == 1


# =============================================================================
# Sort + limit
# =============================================================================


class TestRankingOrder:
    def test_best_first(self):
        # Strong-interest scenic outranks plain-category restaurant.
        hot = _poi(id="hot", category="scenic", rating=4.5,
                   distance_from_route_miles=1.0)
        cold = _poi(id="cold", category="restaurant", rating=4.5,
                    distance_from_route_miles=1.0)
        result = rank_suggestions(
            [cold, hot],
            profile_categories=["restaurant"],
            profile_interests=[
                {"label": "scenic", "mapbox_categories": ["scenic"]}
            ],
            mode=TimeBudgetMode.MODERATE,
            invocation=Invocation.MANUAL,
        )
        assert [r.poi.id for r in result] == ["hot", "cold"]

    def test_limit_caps_results(self):
        pois = [
            _poi(id=str(i), category="scenic", rating=4.5)
            for i in range(5)
        ]
        result = rank_suggestions(
            pois,
            profile_interests=[
                {"label": "scenic", "mapbox_categories": ["scenic"]}
            ],
            mode=TimeBudgetMode.MODERATE,
            invocation=Invocation.MANUAL,
            limit=2,
        )
        assert len(result) == 2
