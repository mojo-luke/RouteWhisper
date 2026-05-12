"""
Unit tests for trip-scale detection and route length calculation.

Locks in the thresholds from `docs/recommendations-brief.md` →
"Trip scale": local < 20 mi, regional 20–100 mi, long ≥ 100 mi. The
threshold values themselves are calibration targets, but encoding
them in tests means a future weights tweak doesn't silently shift the
local/regional/long buckets without test failures.
"""

from app.utils.polyline import (
    TripScale,
    detect_trip_scale,
    route_length_miles,
)


class TestRouteLengthMiles:
    def test_empty_route_is_zero(self):
        assert route_length_miles([]) == 0.0

    def test_single_point_is_zero(self):
        assert route_length_miles([(37.7749, -122.4194)]) == 0.0

    def test_two_points_haversine(self):
        # SF to LA — well-known ~347 mi great-circle.
        miles = route_length_miles([
            (37.7749, -122.4194),  # SF
            (34.0522, -118.2437),  # LA
        ])
        assert 340 < miles < 360

    def test_chained_segments_sum(self):
        # A → B → C should be sum of A→B and B→C, not A→C.
        # Three points making an L-shape so the sum is meaningfully > straight line.
        sf = (37.7749, -122.4194)
        portland = (45.5152, -122.6784)
        seattle = (47.6062, -122.3321)
        sf_to_portland = route_length_miles([sf, portland])
        portland_to_seattle = route_length_miles([portland, seattle])
        sf_to_seattle_via_portland = route_length_miles([sf, portland, seattle])
        # within rounding
        assert (
            abs(sf_to_seattle_via_portland
                - (sf_to_portland + portland_to_seattle))
            < 0.1
        )


class TestDetectTripScale:
    def test_empty_route_is_local(self):
        assert detect_trip_scale([]) == TripScale.LOCAL

    def test_well_under_20mi_is_local(self):
        # Two points ~5 mi apart.
        assert detect_trip_scale([
            (37.7749, -122.4194),
            (37.8444, -122.4194),  # ~5 mi due north
        ]) == TripScale.LOCAL

    def test_just_under_20mi_is_local(self):
        # ~18 mi.
        assert detect_trip_scale([
            (37.7749, -122.4194),
            (38.0349, -122.4194),
        ]) == TripScale.LOCAL

    def test_25mi_is_regional(self):
        # ~25 mi due north.
        assert detect_trip_scale([
            (37.7749, -122.4194),
            (38.1359, -122.4194),
        ]) == TripScale.REGIONAL

    def test_75mi_is_regional(self):
        # ~75 mi.
        assert detect_trip_scale([
            (37.7749, -122.4194),
            (38.8589, -122.4194),
        ]) == TripScale.REGIONAL

    def test_sf_to_la_is_long(self):
        # ~347 mi well into long.
        assert detect_trip_scale([
            (37.7749, -122.4194),
            (34.0522, -118.2437),
        ]) == TripScale.LONG

    def test_boundary_at_100_is_long(self):
        # Just over 100 mi.
        assert detect_trip_scale([
            (37.7749, -122.4194),
            (39.2249, -122.4194),  # ~100 mi north
        ]) == TripScale.LONG

    def test_winding_route_counts_route_distance_not_straight_line(self):
        # Three points that form a loop: 10 mi north, 10 mi east, 10 mi south.
        # Straight-line origin→end is ~10 mi (local), but route distance is
        # ~30 mi (regional). The classifier must use the route.
        a = (37.7749, -122.4194)
        b = (37.9199, -122.4194)  # 10 mi north
        c = (37.9199, -122.2900)  # ~10 mi east of b at this latitude
        d = (37.7749, -122.2900)  # 10 mi south of c
        scale = detect_trip_scale([a, b, c, d])
        assert scale == TripScale.REGIONAL
