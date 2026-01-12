"""
POI Data Models for RouteWhisper
Pydantic models for POI discovery API requests and responses
"""

from pydantic import BaseModel, Field
from typing import List, Optional
from enum import Enum
from datetime import datetime


class POICategory(str, Enum):
    """POI categories matching salvaged code from commit 9b95a3a"""
    GAS_STATION = "gas_station"
    RESTAURANT = "restaurant"
    COFFEE = "coffee"
    HOTEL = "hotel"
    CAMPING = "camping"
    ATTRACTION = "attraction"
    SHOPPING = "shopping"
    SCENIC = "scenic"
    MUSEUM = "museum"
    PARK = "park"
    HOSPITAL = "hospital"
    PHARMACY = "pharmacy"
    BANK = "bank"
    GROCERY = "grocery"


class POIRequest(BaseModel):
    """Request model for POI discovery along a route"""
    encoded_polyline: str = Field(
        ...,
        description="Google-encoded polyline from Mapbox route geometry"
    )
    categories: Optional[List[POICategory]] = Field(
        default=None,
        description="Filter by specific POI categories (defaults to all)"
    )
    corridor_radius_miles: float = Field(
        default=5.0,
        ge=0.1,
        le=25.0,
        description="Search radius from route in miles (default 5.0)"
    )
    limit_per_category: int = Field(
        default=5,
        ge=1,
        le=20,
        description="Maximum POIs to return per category (default 5)"
    )

    class Config:
        json_schema_extra = {
            "example": {
                "encoded_polyline": "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
                "categories": ["restaurant", "gas_station", "scenic"],
                "corridor_radius_miles": 5.0,
                "limit_per_category": 5
            }
        }


class POI(BaseModel):
    """Individual POI response model"""
    id: str = Field(..., description="Unique POI identifier")
    name: str = Field(..., description="POI name")
    category: POICategory = Field(..., description="POI category")
    latitude: float = Field(..., ge=-90, le=90, description="Latitude coordinate")
    longitude: float = Field(..., ge=-180, le=180, description="Longitude coordinate")
    address: Optional[str] = Field(default=None, description="Full address if available")
    estimated_duration_minutes: int = Field(
        default=30,
        ge=5,
        description="Estimated time to spend at this POI (minutes)"
    )
    rating: Optional[float] = Field(
        default=None,
        ge=0.0,
        le=5.0,
        description="User rating (0-5 scale)"
    )
    distance_from_route_miles: float = Field(
        ...,
        ge=0.0,
        description="Distance from route corridor in miles"
    )
    mapbox_poi_id: Optional[str] = Field(
        default=None,
        description="Original Mapbox POI ID for reference"
    )

    class Config:
        json_schema_extra = {
            "example": {
                "id": "poi_123abc",
                "name": "In-N-Out Burger",
                "category": "restaurant",
                "latitude": 37.8044,
                "longitude": -122.4156,
                "address": "333 Jefferson St, San Francisco, CA 94133",
                "estimated_duration_minutes": 30,
                "rating": 4.5,
                "distance_from_route_miles": 0.3,
                "mapbox_poi_id": "dXJuOm1ieHBvaTpjMTI..."
            }
        }


class POIResponse(BaseModel):
    """Response model for POI discovery endpoint"""
    pois: List[POI] = Field(..., description="List of discovered POIs")
    total_found: int = Field(..., ge=0, description="Total number of POIs found")
    cached: bool = Field(default=False, description="Whether results were cached")
    corridor_bounds: List[float] = Field(
        ...,
        min_length=4,
        max_length=4,
        description="Bounding box of route corridor [minLng, minLat, maxLng, maxLat]"
    )

    class Config:
        json_schema_extra = {
            "example": {
                "pois": [
                    {
                        "id": "poi_123",
                        "name": "In-N-Out Burger",
                        "category": "restaurant",
                        "latitude": 37.8044,
                        "longitude": -122.4156,
                        "address": "333 Jefferson St, San Francisco, CA 94133",
                        "estimated_duration_minutes": 30,
                        "rating": 4.5,
                        "distance_from_route_miles": 0.3,
                        "mapbox_poi_id": "dXJuOm1ieHBvaTpjMTI..."
                    }
                ],
                "total_found": 15,
                "cached": False,
                "corridor_bounds": [-122.5, 37.7, -122.3, 37.9]
            }
        }


class WaypointStopHistory(BaseModel):
    """Historical data about user stops at waypoints for personalization"""
    user_id: Optional[str] = Field(default=None, description="User ID for future personalization")
    waypoint_id: str = Field(..., description="Unique waypoint identifier")
    waypoint_name: str = Field(..., description="Waypoint name")
    waypoint_category: Optional[str] = Field(default=None, description="POI category if applicable")
    latitude: float = Field(..., ge=-90, le=90, description="Waypoint latitude")
    longitude: float = Field(..., ge=-180, le=180, description="Waypoint longitude")

    # Planned vs Actual
    planned_duration_minutes: int = Field(..., ge=0, description="User's planned stop duration")
    actual_duration_minutes: int = Field(..., ge=0, description="Actual stop duration")
    duration_difference_minutes: Optional[int] = Field(default=None, description="Actual - planned duration")

    # Timestamps
    arrival_time: datetime = Field(..., description="Timestamp of arrival at waypoint")
    departure_time: datetime = Field(..., description="Timestamp of departure from waypoint")

    # Context for analytics
    day_of_week: Optional[int] = Field(default=None, ge=0, le=6, description="0=Monday, 6=Sunday")
    hour_of_day: Optional[int] = Field(default=None, ge=0, le=23, description="Hour of arrival (0-23)")
    is_weekend: Optional[bool] = Field(default=None, description="Whether stop was on weekend")
    is_automatic_departure: Optional[bool] = Field(default=False, description="True if departure was auto-detected")

    # Trip context
    waypoint_order: int = Field(..., ge=0, description="Position in route (0-based)")
    total_waypoints: Optional[int] = Field(default=None, ge=0, description="Total waypoints in trip")

    class Config:
        json_schema_extra = {
            "example": {
                "waypoint_id": "wp_123abc",
                "waypoint_name": "In-N-Out Burger",
                "waypoint_category": "restaurant",
                "latitude": 37.8044,
                "longitude": -122.4156,
                "planned_duration_minutes": 30,
                "actual_duration_minutes": 45,
                "arrival_time": "2026-01-10T12:00:00",
                "departure_time": "2026-01-10T12:45:00",
                "is_automatic_departure": False,
                "waypoint_order": 1,
                "total_waypoints": 3
            }
        }


# Estimated duration mapping by category (in minutes)
CATEGORY_DURATION_MAP = {
    POICategory.GAS_STATION: 10,
    POICategory.RESTAURANT: 75,
    POICategory.COFFEE: 20,
    POICategory.HOTEL: 15,  # Just for checking in
    POICategory.CAMPING: 45,
    POICategory.ATTRACTION: 60,
    POICategory.SHOPPING: 45,
    POICategory.SCENIC: 20,
    POICategory.MUSEUM: 90,
    POICategory.PARK: 30,
    POICategory.HOSPITAL: 15,
    POICategory.PHARMACY: 10,
    POICategory.BANK: 5,
    POICategory.GROCERY: 30,
}


# Category priority for ranking (higher = more important)
CATEGORY_PRIORITY_MAP = {
    POICategory.GAS_STATION: 10,  # Highest priority - practical need
    POICategory.HOSPITAL: 9,
    POICategory.PHARMACY: 8,
    POICategory.RESTAURANT: 7,
    POICategory.COFFEE: 6,
    POICategory.GROCERY: 5,
    POICategory.BANK: 5,
    POICategory.HOTEL: 4,
    POICategory.ATTRACTION: 3,
    POICategory.SCENIC: 3,
    POICategory.MUSEUM: 2,
    POICategory.SHOPPING: 2,
    POICategory.CAMPING: 2,
    POICategory.PARK: 1,
}
