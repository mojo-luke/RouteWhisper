"""
Unit tests for the rule-based stop-recommendation scorer.

We test the score function with concrete POIs and synthetic profiles /
history aggregates, not the FastAPI route — the wire layer is exercised
by integration tests once we add them. The goal here is to lock in the
weights and the reason-string selection.
"""

from datetime import datetime

import pytest

from app.models import POI
from app.services.stop_recommendations import (
    rank_suggestions,
    score_poi,
)


def _poi(*, id="p1", name="Test", category="restaurant",
         distance_from_route_miles=0.4, rating=4.0):
    return POI(
        id=id,
        name=name,
        category=category,
        latitude=37.5,
        longitude=-122.4,
        estimated_duration_minutes=30,
        rating=rating,
        distance_from_route_miles=distance_from_route_miles,
    )


_NOW = datetime(2026, 5, 11, 11, 0)  # 11:00 AM


class TestScorePoi:
    def test_no_signal_no_score(self):
        result = score_poi(
            _poi(),
            preferred_categories=[],
            category_averages={},
            by_hour=[],
            remaining_budget_minutes=None,
            now=_NOW,
        )
        # Within 1mi of route, no history, no prefs → effectively 0.
        assert result.score == 0.0
        assert "Suggested stop" in result.reason

    def test_preferred_category_boost(self):
        result = score_poi(
            _poi(category="restaurant"),
            preferred_categories=["restaurant"],
            category_averages={},
            by_hour=[],
            remaining_budget_minutes=None,
            now=_NOW,
        )
        assert result.score == 0.30
        assert "like" in result.reason.lower()

    def test_history_familiarity_adds(self):
        result = score_poi(
            _poi(category="coffee"),
            preferred_categories=[],
            category_averages={
                "coffee": {"count": 5, "avg_actual_minutes": 18.0}
            },
            by_hour=[],
            remaining_budget_minutes=None,
            now=_NOW,
        )
        assert result.score == 0.15
        assert "18 min" in result.reason

    def test_hour_pattern_match_above_threshold(self):
        # 6 of 8 historical stops happened in the 10–12 window — 75% match
        by_hour = [
            {"hour": 10, "count": 2},
            {"hour": 11, "count": 3},
            {"hour": 12, "count": 1},
            {"hour": 16, "count": 2},
        ]
        result = score_poi(
            _poi(),
            preferred_categories=[],
            category_averages={},
            by_hour=by_hour,
            remaining_budget_minutes=None,
            now=_NOW,  # hour=11
        )
        assert result.score == 0.20
        assert "11:00" in result.reason

    def test_hour_pattern_ignored_when_too_few_stops(self):
        # Only 3 total stops — below the noise floor of 5.
        by_hour = [{"hour": 11, "count": 3}]
        result = score_poi(
            _poi(),
            preferred_categories=[],
            category_averages={},
            by_hour=by_hour,
            remaining_budget_minutes=None,
            now=_NOW,
        )
        assert result.score == 0.0

    def test_fits_budget_adds_small_boost(self):
        # Restaurant default duration is 75 min; 100 min budget fits.
        result = score_poi(
            _poi(category="restaurant"),
            preferred_categories=[],
            category_averages={},
            by_hour=[],
            remaining_budget_minutes=100,
            now=_NOW,
        )
        assert result.score == 0.10

    def test_over_budget_demotes_strongly(self):
        # Restaurant 75min, budget only 30min → demoted.
        result = score_poi(
            _poi(category="restaurant"),
            preferred_categories=["restaurant"],  # would otherwise be +0.30
            category_averages={},
            by_hour=[],
            remaining_budget_minutes=30,
            now=_NOW,
        )
        # +0.30 preferred, -0.50 over budget = -0.20 net
        assert result.score == -0.20

    def test_off_route_distance_penalty(self):
        # 6mi off-route: penalty = (6 - 1) * -0.05 = -0.25
        result = score_poi(
            _poi(distance_from_route_miles=6.0),
            preferred_categories=[],
            category_averages={},
            by_hour=[],
            remaining_budget_minutes=None,
            now=_NOW,
        )
        assert result.score == -0.25

    def test_strongest_reason_wins(self):
        # Preferred (+0.30) > history (+0.15) — preferred is the reason.
        result = score_poi(
            _poi(category="restaurant"),
            preferred_categories=["restaurant"],
            category_averages={
                "restaurant": {"count": 3, "avg_actual_minutes": 50}
            },
            by_hour=[],
            remaining_budget_minutes=None,
            now=_NOW,
        )
        assert result.score == pytest.approx(0.45)  # 0.30 + 0.15
        assert "like" in result.reason.lower()  # preferred wins


class TestRankSuggestions:
    def test_filters_below_min_score(self):
        pois = [_poi(id="a"), _poi(id="b")]
        results = rank_suggestions(
            pois,
            preferred_categories=[],
            category_averages={},
            by_hour=[],
            remaining_budget_minutes=None,
            now=_NOW,
            min_score=0.15,
        )
        # Both score 0.0 — filtered out.
        assert results == []

    def test_orders_best_first(self):
        pois = [
            _poi(id="cold", category="hotel"),  # no signals → 0
            _poi(id="warm", category="coffee"),  # +0.15 history
            _poi(id="hot", category="restaurant"),  # +0.30 preferred + 0.15 history
        ]
        results = rank_suggestions(
            pois,
            preferred_categories=["restaurant"],
            category_averages={
                "coffee": {"count": 4, "avg_actual_minutes": 20},
                "restaurant": {"count": 4, "avg_actual_minutes": 60},
            },
            by_hour=[],
            remaining_budget_minutes=None,
            now=_NOW,
        )
        ids = [r.poi.id for r in results]
        assert ids == ["hot", "warm"]  # "cold" filtered by min_score

    def test_respects_limit(self):
        pois = [
            _poi(id=str(i), category="restaurant") for i in range(5)
        ]
        results = rank_suggestions(
            pois,
            preferred_categories=["restaurant"],
            category_averages={},
            by_hour=[],
            remaining_budget_minutes=None,
            now=_NOW,
            limit=2,
        )
        assert len(results) == 2
