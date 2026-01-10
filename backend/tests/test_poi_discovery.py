"""
Unit tests for POI discovery functionality
Tests polyline decoding, corridor extraction, ranking, and caching
"""

import pytest
from typing import List, Tuple

from app.models import POI, POICategory
from app.utils.polyline import (
    decode_polyline,
    create_corridor_buffer,
    calculate_distance_miles,
    calculate_bounds,
    simplify_route_points
)
from app.services.poi_ranking import POIRankingService


class TestPolylineDecoding:
    """Test polyline encoding/decoding utilities."""

    def test_decode_simple_polyline(self):
        """Test decoding a simple Google-encoded polyline."""
        # This polyline represents 3 points
        polyline = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
        points = decode_polyline(polyline)

        assert len(points) == 3
        assert all(isinstance(p, tuple) and len(p) == 2 for p in points)

        # First point should be around (38.5, -120.2)
        assert 38.0 < points[0][0] < 39.0
        assert -121.0 < points[0][1] < -120.0

    def test_decode_empty_polyline(self):
        """Test decoding empty polyline returns empty list."""
        points = decode_polyline("")
        assert points == []

    def test_calculate_bounds(self):
        """Test bounding box calculation."""
        points = [
            (37.7749, -122.4194),  # San Francisco
            (34.0522, -118.2437),  # Los Angeles
        ]

        bounds = calculate_bounds(points)

        # Should return [minLng, minLat, maxLng, maxLat]
        assert len(bounds) == 4
        assert bounds[0] == -122.4194  # minLng
        assert bounds[1] == 34.0522     # minLat
        assert bounds[2] == -118.2437   # maxLng
        assert bounds[3] == 37.7749     # maxLat

    def test_simplify_route_points(self):
        """Test route simplification."""
        # Create 200 points
        points = [(i * 0.1, i * 0.1) for i in range(200)]

        # Simplify to 50
        simplified = simplify_route_points(points, max_points=50)

        assert len(simplified) <= 51  # May include last point
        assert simplified[0] == points[0]  # First point preserved
        assert simplified[-1] == points[-1]  # Last point preserved


class TestDistanceCalculations:
    """Test distance calculation functions."""

    def test_haversine_distance_sf_to_la(self):
        """Test Haversine distance calculation."""
        sf = (37.7749, -122.4194)
        la = (34.0522, -118.2437)

        distance = calculate_distance_miles(sf, la)

        # SF to LA is approximately 347 miles
        assert 340 < distance < 355

    def test_distance_same_point(self):
        """Test distance between same point is zero."""
        point = (37.7749, -122.4194)
        distance = calculate_distance_miles(point, point)

        assert distance < 0.001  # Essentially zero

    def test_distance_nearby_points(self):
        """Test distance between nearby points."""
        p1 = (37.7749, -122.4194)
        p2 = (37.7750, -122.4195)  # Very close

        distance = calculate_distance_miles(p1, p2)

        assert distance < 0.1  # Less than 0.1 miles


class TestPOIRanking:
    """Test POI ranking and filtering."""

    def create_test_poi(
        self,
        name: str,
        category: POICategory,
        lat: float,
        lng: float,
        rating: float = None,
        distance: float = 0.0
    ) -> POI:
        """Helper to create test POI."""
        return POI(
            id=f"poi_{name}",
            name=name,
            category=category,
            latitude=lat,
            longitude=lng,
            estimated_duration_minutes=30,
            rating=rating,
            distance_from_route_miles=distance
        )

    def test_filter_duplicates(self):
        """Test duplicate POI filtering."""
        pois = [
            self.create_test_poi("Restaurant A", POICategory.RESTAURANT, 37.7749, -122.4194),
            self.create_test_poi("Restaurant B", POICategory.RESTAURANT, 37.7750, -122.4195),  # Duplicate
            self.create_test_poi("Restaurant C", POICategory.RESTAURANT, 37.8000, -122.4000),  # Different
        ]

        filtered = POIRankingService.filter_duplicates(pois, distance_threshold_miles=0.1)

        # Should filter out Restaurant B (too close to A)
        assert len(filtered) == 2
        assert filtered[0].name == "Restaurant A"
        assert filtered[1].name == "Restaurant C"

    def test_rank_pois_by_category(self):
        """Test POI ranking by category priority."""
        pois = [
            self.create_test_poi("Museum", POICategory.MUSEUM, 37.7749, -122.4194, distance=1.0),
            self.create_test_poi("Gas Station", POICategory.GAS_STATION, 37.7750, -122.4195, distance=1.0),
            self.create_test_poi("Restaurant", POICategory.RESTAURANT, 37.7751, -122.4196, distance=1.0),
        ]

        ranked = POIRankingService.rank_pois(pois)

        # Gas station should rank higher (priority 10) than restaurant (7) than museum (2)
        assert ranked[0].category == POICategory.GAS_STATION
        assert ranked[1].category == POICategory.RESTAURANT
        assert ranked[2].category == POICategory.MUSEUM

    def test_rank_pois_by_distance(self):
        """Test POI ranking by distance from route."""
        pois = [
            self.create_test_poi("Far", POICategory.RESTAURANT, 37.7749, -122.4194, distance=10.0),
            self.create_test_poi("Close", POICategory.RESTAURANT, 37.7750, -122.4195, distance=0.5),
            self.create_test_poi("Medium", POICategory.RESTAURANT, 37.7751, -122.4196, distance=5.0),
        ]

        ranked = POIRankingService.rank_pois(pois)

        # Closer POIs should rank higher
        assert ranked[0].name == "Close"
        assert ranked[1].name == "Medium"
        assert ranked[2].name == "Far"

    def test_rank_pois_by_rating(self):
        """Test POI ranking considers ratings."""
        pois = [
            self.create_test_poi("Low Rated", POICategory.RESTAURANT, 37.7749, -122.4194, rating=2.0, distance=1.0),
            self.create_test_poi("High Rated", POICategory.RESTAURANT, 37.7750, -122.4195, rating=5.0, distance=1.0),
            self.create_test_poi("Medium Rated", POICategory.RESTAURANT, 37.7751, -122.4196, rating=3.5, distance=1.0),
        ]

        ranked = POIRankingService.rank_pois(pois)

        # Higher rated should rank higher (all else equal)
        assert ranked[0].name == "High Rated"
        assert ranked[1].name == "Medium Rated"
        assert ranked[2].name == "Low Rated"


class TestCorridorBuffer:
    """Test route corridor buffer creation."""

    def test_create_corridor_simple(self):
        """Test creating a corridor buffer around points."""
        points = [
            (37.7749, -122.4194),
            (37.8049, -122.4394),
        ]

        corridor = create_corridor_buffer(points, radius_miles=5.0)

        assert corridor is not None
        assert corridor.is_valid
        assert corridor.area > 0

    def test_create_corridor_empty_points_raises_error(self):
        """Test that empty points list raises error."""
        with pytest.raises(ValueError, match="Cannot create corridor from empty points"):
            create_corridor_buffer([], radius_miles=5.0)


@pytest.mark.asyncio
class TestCacheService:
    """Test POI caching service."""

    async def test_cache_key_generation(self):
        """Test consistent cache key generation."""
        from app.services.cache import POICacheService
        from unittest.mock import MagicMock

        redis_mock = MagicMock()
        cache = POICacheService(redis_mock)

        # Same inputs should generate same key
        key1 = cache.generate_cache_key("polyline1", ["restaurant", "gas_station"], 5.0)
        key2 = cache.generate_cache_key("polyline1", ["gas_station", "restaurant"], 5.0)  # Different order

        # Keys should be equal (categories are sorted)
        assert key1 == key2

        # Different inputs should generate different keys
        key3 = cache.generate_cache_key("polyline2", ["restaurant", "gas_station"], 5.0)
        assert key1 != key3


# Integration-style test (requires running server)
@pytest.mark.skip(reason="Requires running backend server")
class TestPOIEndpoint:
    """Integration tests for POI discovery endpoint."""

    async def test_poi_endpoint_with_valid_polyline(self):
        """Test POI endpoint with valid request."""
        # This would require httpx client and running server
        pass

    async def test_poi_endpoint_caching(self):
        """Test that second request uses cache."""
        # This would test cache hit behavior
        pass


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
