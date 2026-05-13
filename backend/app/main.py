"""
RouteWhisper Backend API
Main FastAPI application entry point
"""

from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import redis.asyncio as aioredis
import os
import logging
from datetime import datetime
from typing import Optional
from dotenv import load_dotenv

from pydantic import BaseModel, Field

# Set up logging
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# Import POI models and services
from app.models import POIRequest, POIResponse, POICategory, WaypointStopHistory
from app.services.mapbox_search import MapboxSearchService
from app.services.poi_ranking import POIRankingService
from app.services.cache import POICacheService
from app.utils.polyline import (
    calculate_bounds,
    decode_polyline,
    detect_trip_scale,
    TripScale,
)

# Auth + persistence
from app.auth import CurrentUser, get_current_user
from app.database import (
    init_mongodb,
    POIContent,
    Trip,
    UserProfile,
    WaypointStopHistoryDoc,
)

# Recommendations
from app.services.stop_recommendations import (
    Invocation,
    TimeBudgetMode,
    rank_suggestions,
)

# Global Redis client
redis_client = None

async def get_redis():
    """Get Redis client"""
    global redis_client
    if redis_client is None:
        redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
        redis_client = await aioredis.from_url(redis_url, decode_responses=True)
        print(f"🔴 Connected to Redis at {redis_url}")
    return redis_client

# Create FastAPI instance
app = FastAPI(
    title="RouteWhisper API",
    description="Backend API for RouteWhisper - POI discovery service",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

@app.on_event("startup")
async def startup():
    """Initialize services on startup"""
    print("🚀 Starting RouteWhisper API...")
    await get_redis()
    print("✅ Redis initialized successfully!")
    if os.getenv("MONGODB_URL"):
        await init_mongodb()
        print("✅ MongoDB initialized successfully!")
    else:
        print("⚠️ MONGODB_URL not set; persistence endpoints will fail.")

@app.on_event("shutdown")
async def shutdown():
    """Cleanup on shutdown"""
    global redis_client
    if redis_client:
        await redis_client.close()
    print("🛑 Shutting down RouteWhisper API...")

# Configure CORS for Flutter app and mobile
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://127.0.0.1:3000",  # Flutter dev server
        "http://10.0.2.2:8000",    # Android emulator
        "http://localhost:8000",   # iOS simulator
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Health check endpoint
@app.get("/health")
async def health_check():
    """Health check endpoint"""

    # Test Redis connection
    redis_status = "connected"
    try:
        redis = await get_redis()
        await redis.ping()
    except Exception as e:
        redis_status = f"error: {str(e)}"

    return JSONResponse(
        status_code=200,
        content={
            "status": "healthy",
            "service": "RouteWhisper API",
            "redis": redis_status
        }
    )

# Root endpoint
@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "message": "Welcome to RouteWhisper API",
        "version": "1.0.0",
        "docs": "/docs",
        "endpoints": {
            "health": "/health",
            "poi_discovery": "/api/v1/route/pois"
        }
    }

# POI Discovery Endpoint (Step 3)
@app.post("/api/v1/route/pois", response_model=POIResponse)
async def discover_route_pois(
    request: POIRequest,
    user: CurrentUser = Depends(get_current_user),
):
    """
    Discover POIs along a route corridor.

    Process:
    1. Check Redis cache for existing results
    2. Decode polyline to route points
    3. Create corridor buffer around route
    4. Query Mapbox Search API for POIs
    5. Rank and filter POIs
    6. Cache results for 1 hour
    7. Return POI response

    Args:
        request: POI discovery request with encoded polyline and filters
        redis: Redis client dependency

    Returns:
        POIResponse with discovered POIs
    """
    import logging
    logger = logging.getLogger(__name__)

    logger.info(
        f"POI discovery request: {len(request.encoded_polyline)} chars polyline, "
        f"{len(request.categories) if request.categories else 'all'} categories, "
        f"{request.corridor_radius_miles} mile radius"
    )

    try:
        # Get Redis client
        redis = await get_redis()

        # Initialize services
        cache_service = POICacheService(redis)
        mapbox_service = MapboxSearchService()

        # Generate cache key
        category_strings = [cat.value for cat in request.categories] if request.categories else []
        cache_key = cache_service.generate_cache_key(
            request.encoded_polyline,
            category_strings,
            request.corridor_radius_miles
        )

        # Look up the caller's preference list — applied as a final stable
        # re-order after either cache hits or fresh computation, so the cache
        # stays shared across users.
        profile = await UserProfile.find_one(UserProfile.user_id == user.id)
        preferred_categories = profile.preferred_poi_types if profile else []

        # Check cache
        cached_pois = await cache_service.get_cached_pois(cache_key)
        if cached_pois:
            # Decode polyline for bounds calculation
            route_points = decode_polyline(request.encoded_polyline)
            bounds = calculate_bounds(route_points)

            logger.info(f"Cache hit! Returning {len(cached_pois)} cached POIs")
            cached_pois = POIRankingService.apply_preferences(
                cached_pois, preferred_categories
            )
            return POIResponse(
                pois=cached_pois,
                total_found=len(cached_pois),
                cached=True,
                corridor_bounds=bounds
            )

        # Cache miss - process request
        logger.info("Cache miss - querying Mapbox Search API")

        # Step 1: Decode polyline to route points
        route_points = decode_polyline(request.encoded_polyline)
        logger.info(f"Decoded polyline: {len(route_points)} route points")
        if len(route_points) > 0:
            logger.info(f"First point: {route_points[0]}, Last point: {route_points[-1]}")

        # Step 2: Calculate bounds for search
        bounds = calculate_bounds(route_points)
        logger.info(f"Route bounds: {bounds}")

        # Step 3: Calculate proximity center (midpoint of route)
        mid_idx = len(route_points) // 2
        proximity = route_points[mid_idx]  # (lat, lng)
        logger.info(f"Proximity center: lat={proximity[0]}, lng={proximity[1]}")

        # Validate coordinates
        if not (-90 <= proximity[0] <= 90 and -180 <= proximity[1] <= 180):
            logger.error(f"Invalid proximity coordinates: {proximity}")
            raise ValueError(f"Invalid proximity coordinates: lat={proximity[0]}, lng={proximity[1]}")

        # Step 4: Determine categories to search
        # Limit to high-priority categories to avoid rate limits
        if request.categories:
            categories = request.categories
        else:
            # Default to just 4 high-priority categories
            categories = [
                POICategory.GAS_STATION,
                POICategory.RESTAURANT,
                POICategory.COFFEE,
                POICategory.SCENIC
            ]
        logger.info(f"Searching {len(categories)} categories: {[c.value for c in categories]}")

        # Step 5: Query Mapbox Search API (parallel searches)
        pois = await mapbox_service.search_multiple_categories(
            categories=categories,
            proximity=proximity,
            bbox=bounds,
            limit_per_category=request.limit_per_category
        )

        logger.info(f"Mapbox returned {len(pois)} POIs")

        # Step 6: Rank and filter POIs
        final_pois = POIRankingService.filter_and_rank(
            pois=pois,
            route_points=route_points,
            max_results=15,  # Return top 15 POIs
            distribute=True
        )

        logger.info(f"After ranking/filtering: {len(final_pois)} POIs")

        # Step 7: Cache results (cache the pre-preference ranking so the
        # cache is shared across users; we re-order per-user below).
        await cache_service.cache_pois(cache_key, final_pois)

        # Step 8: Clean up
        await mapbox_service.close()

        # Step 9: Apply user-specific preference re-ordering.
        final_pois = POIRankingService.apply_preferences(
            final_pois, preferred_categories
        )

        # Return response
        return POIResponse(
            pois=final_pois,
            total_found=len(final_pois),
            cached=False,
            corridor_bounds=bounds
        )

    except Exception as e:
        logger.error(f"POI discovery failed: {e}", exc_info=True)
        # Return error response
        from fastapi import HTTPException
        raise HTTPException(status_code=500, detail=f"POI discovery failed: {str(e)}")

# Placeholder endpoints for future implementation
@app.get("/api/v1/route/analyze")
async def analyze_route():
    """Legacy route analysis endpoint - Use POST /api/v1/route/pois instead"""
    return {
        "message": "This endpoint is deprecated. Use POST /api/v1/route/pois instead",
        "new_endpoint": "/api/v1/route/pois"
    }

@app.get("/api/v1/search/geocode")
async def geocode_place(
    query: str,
    proximity: str = None,  # Optional: "lng,lat" format for biasing results
    limit: int = 5
):
    """
    Search for a place by name or address using Mapbox Geocoding API.

    Args:
        query: Search query (place name or address)
        proximity: Optional "lng,lat" to bias results near a location
        limit: Maximum number of results (default 5, max 10)

    Returns:
        List of search results with coordinates and details

    Example:
        GET /api/v1/search/geocode?query=Starbucks San Francisco&limit=5
    """
    import httpx

    try:
        mapbox_token = os.getenv("MAPBOX_ACCESS_TOKEN")
        if not mapbox_token:
            raise HTTPException(status_code=500, detail="Mapbox token not configured")

        # Build Mapbox Geocoding API request
        url = f"https://api.mapbox.com/geocoding/v5/mapbox.places/{query}.json"
        params = {
            "access_token": mapbox_token,
            "limit": min(limit, 10),
            "types": "poi,address,place"  # Search POIs, addresses, and places
        }

        if proximity:
            params["proximity"] = proximity

        # Make request to Mapbox
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(url, params=params)
            response.raise_for_status()
            data = response.json()

        # Parse results
        results = []
        for feature in data.get("features", []):
            coords = feature.get("geometry", {}).get("coordinates", [])
            if len(coords) == 2:
                lng, lat = coords
                results.append({
                    "name": feature.get("place_name", "Unknown"),
                    "address": feature.get("place_name"),
                    "latitude": lat,
                    "longitude": lng,
                    "place_type": feature.get("place_type", []),
                    "relevance": feature.get("relevance", 0.0),
                })

        return {
            "success": True,
            "query": query,
            "results": results,
            "count": len(results)
        }

    except httpx.HTTPStatusError as e:
        logger.error(f"Mapbox Geocoding API error: {e.response.status_code} - {e.response.text}")
        raise HTTPException(status_code=502, detail=f"Geocoding service error: {e.response.status_code}")
    except Exception as e:
        logger.error(f"Geocoding failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/waypoints/history")
async def record_waypoint_stop(
    history: WaypointStopHistory,
    user: CurrentUser = Depends(get_current_user),
):
    """Record one stop's history for the authenticated user.

    Persists to MongoDB so the analytics endpoints (`/category-averages`,
    `/time-patterns`) and Step 7's stop recommendations can read from it.
    """
    try:
        if history.duration_difference_minutes is None:
            history.duration_difference_minutes = (
                history.actual_duration_minutes - history.planned_duration_minutes
            )
        if history.day_of_week is None:
            history.day_of_week = history.arrival_time.weekday()
        if history.hour_of_day is None:
            history.hour_of_day = history.arrival_time.hour
        if history.is_weekend is None:
            history.is_weekend = history.day_of_week >= 5

        doc = WaypointStopHistoryDoc(
            user_id=user.id,
            waypoint_id=history.waypoint_id,
            waypoint_name=history.waypoint_name,
            waypoint_category=history.waypoint_category,
            latitude=history.latitude,
            longitude=history.longitude,
            planned_duration_minutes=history.planned_duration_minutes,
            actual_duration_minutes=history.actual_duration_minutes,
            duration_difference_minutes=history.duration_difference_minutes,
            arrival_time=history.arrival_time,
            departure_time=history.departure_time,
            day_of_week=history.day_of_week,
            hour_of_day=history.hour_of_day,
            is_weekend=history.is_weekend,
            is_automatic_departure=history.is_automatic_departure,
            waypoint_order=history.waypoint_order,
            total_waypoints=history.total_waypoints,
            recorded_at=datetime.utcnow(),
        )
        await doc.insert()

        logger.info(
            f"📊 Stop persisted: {history.waypoint_name} for user {user.id} "
            f"(planned: {history.planned_duration_minutes}min, "
            f"actual: {history.actual_duration_minutes}min)"
        )
        return {"success": True, "id": str(doc.id)}

    except Exception as e:
        logger.error(f"Failed to record stop history: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to record stop history: {str(e)}")


@app.get("/api/v1/waypoints/history")
async def list_waypoint_history(
    user: CurrentUser = Depends(get_current_user),
    limit: int = 100,
):
    """List the authenticated user's most recent stops, newest first."""
    docs = (
        await WaypointStopHistoryDoc.find(WaypointStopHistoryDoc.user_id == user.id)
        .sort(-WaypointStopHistoryDoc.recorded_at)
        .limit(limit)
        .to_list()
    )
    return {"count": len(docs), "items": [d.model_dump(mode="json") for d in docs]}


@app.get("/api/v1/waypoints/category-averages")
async def waypoint_category_averages(
    user: CurrentUser = Depends(get_current_user),
):
    """Mean planned & actual stop duration grouped by category, per user.

    Powers the frontend's `WaypointApiService.getCategoryAverages` stub —
    used downstream to show "you usually stay 45min at restaurants" hints.
    """
    pipeline = [
        {"$match": {"user_id": user.id, "waypoint_category": {"$ne": None}}},
        {
            "$group": {
                "_id": "$waypoint_category",
                "count": {"$sum": 1},
                "avg_planned_minutes": {"$avg": "$planned_duration_minutes"},
                "avg_actual_minutes": {"$avg": "$actual_duration_minutes"},
                "avg_diff_minutes": {"$avg": "$duration_difference_minutes"},
            }
        },
        {"$sort": {"count": -1}},
    ]
    rows = await WaypointStopHistoryDoc.aggregate(pipeline).to_list()
    return {
        "categories": [
            {
                "category": r["_id"],
                "count": r["count"],
                "avg_planned_minutes": round(r["avg_planned_minutes"] or 0, 1),
                "avg_actual_minutes": round(r["avg_actual_minutes"] or 0, 1),
                "avg_diff_minutes": round(r["avg_diff_minutes"] or 0, 1),
            }
            for r in rows
        ]
    }


@app.get("/api/v1/waypoints/time-patterns")
async def waypoint_time_patterns(
    user: CurrentUser = Depends(get_current_user),
):
    """Hour-of-day and day-of-week stop counts per user. Cheap and good
    enough for first-pass "you usually stop around 11am" hints.
    """
    by_hour = await WaypointStopHistoryDoc.aggregate(
        [
            {"$match": {"user_id": user.id, "hour_of_day": {"$ne": None}}},
            {"$group": {"_id": "$hour_of_day", "count": {"$sum": 1}}},
            {"$sort": {"_id": 1}},
        ]
    ).to_list()
    by_day = await WaypointStopHistoryDoc.aggregate(
        [
            {"$match": {"user_id": user.id, "day_of_week": {"$ne": None}}},
            {"$group": {"_id": "$day_of_week", "count": {"$sum": 1}}},
            {"$sort": {"_id": 1}},
        ]
    ).to_list()
    return {
        "by_hour": [{"hour": r["_id"], "count": r["count"]} for r in by_hour],
        "by_day_of_week": [{"day": r["_id"], "count": r["count"]} for r in by_day],
    }


# =============================================================================
# User profile
# =============================================================================

class InterestPayload(BaseModel):
    """Wire shape for a single user interest. See
    docs/recommendations-brief.md → 'Personalization vocabulary'.

    `label` is what the user typed or picked. `mapbox_categories` and
    `keywords` are what the engine uses for query expansion; they may
    be empty for raw free-text entries pending LLM normalization.
    """
    label: str
    mapbox_categories: list[str] = Field(default_factory=list)
    keywords: list[str] = Field(default_factory=list)


class UserProfilePayload(BaseModel):
    """Wire shape for GET/PUT /user/profile."""
    preferred_poi_types: list[str] = Field(default_factory=list)
    default_time_budget_minutes: Optional[int] = None
    dietary_restrictions: list[str] = Field(default_factory=list)

    # Specific interests — heavier personalization signal than categories.
    interests: list[InterestPayload] = Field(default_factory=list)

    # Recommendation surface controls.
    recommendations_enabled: bool = True
    recommendations_max_per_trip: int = 3
    recommendations_min_gap_minutes: int = 15

    # Voice controls.
    turn_by_turn_voice_enabled: bool = True


async def _get_or_create_profile(user_id: str) -> UserProfile:
    profile = await UserProfile.find_one(UserProfile.user_id == user_id)
    if profile is None:
        profile = UserProfile(user_id=user_id)
        await profile.insert()
    return profile


@app.get("/api/v1/user/profile", response_model=UserProfilePayload)
async def get_user_profile(user: CurrentUser = Depends(get_current_user)):
    """Read the caller's profile, creating an empty one on first request."""
    p = await _get_or_create_profile(user.id)
    return UserProfilePayload(
        preferred_poi_types=p.preferred_poi_types,
        default_time_budget_minutes=p.default_time_budget_minutes,
        dietary_restrictions=p.dietary_restrictions,
        interests=[InterestPayload(**i) for i in (p.interests or [])],
        recommendations_enabled=p.recommendations_enabled,
        recommendations_max_per_trip=p.recommendations_max_per_trip,
        recommendations_min_gap_minutes=p.recommendations_min_gap_minutes,
        turn_by_turn_voice_enabled=p.turn_by_turn_voice_enabled,
    )


@app.put("/api/v1/user/profile", response_model=UserProfilePayload)
async def update_user_profile(
    payload: UserProfilePayload,
    user: CurrentUser = Depends(get_current_user),
):
    """Replace the caller's profile fields with the supplied values."""
    p = await _get_or_create_profile(user.id)
    p.preferred_poi_types = payload.preferred_poi_types
    p.default_time_budget_minutes = payload.default_time_budget_minutes
    p.dietary_restrictions = payload.dietary_restrictions
    p.interests = [i.model_dump() for i in payload.interests]
    p.recommendations_enabled = payload.recommendations_enabled
    p.recommendations_max_per_trip = payload.recommendations_max_per_trip
    p.recommendations_min_gap_minutes = payload.recommendations_min_gap_minutes
    p.turn_by_turn_voice_enabled = payload.turn_by_turn_voice_enabled
    p.updated_at = datetime.utcnow()
    await p.save()
    return payload

# =============================================================================
# Trips — pre-trip planning persistence. See docs/trip-planning-brief.md.
# This slice (A) ships the skeleton: create, list, read, update, delete.
# Slices B+ add the wizard UX, canvas rendering, multi-day breaks, and
# lodging integration on top of this storage layer.
# =============================================================================


class TripPayload(BaseModel):
    """Wire shape for Trip create/read/update. The optional `id` is
    server-assigned and omitted on POST (create)."""
    id: Optional[str] = None
    name: str
    origin_name: str
    origin_lat: float
    origin_lng: float
    destination_name: str
    destination_lat: float
    destination_lng: float
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    arrival_time: Optional[str] = None
    daily_drive_cap_hours: int = 6
    time_budget_mode: str = "moderate"
    pins: list = Field(default_factory=list)
    days: list = Field(default_factory=list)
    notes: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None


def _trip_to_payload(trip: Trip) -> TripPayload:
    return TripPayload(
        id=str(trip.id),
        name=trip.name,
        origin_name=trip.origin_name,
        origin_lat=trip.origin_lat,
        origin_lng=trip.origin_lng,
        destination_name=trip.destination_name,
        destination_lat=trip.destination_lat,
        destination_lng=trip.destination_lng,
        start_date=trip.start_date,
        end_date=trip.end_date,
        arrival_time=trip.arrival_time,
        daily_drive_cap_hours=trip.daily_drive_cap_hours,
        time_budget_mode=trip.time_budget_mode,
        pins=trip.pins,
        days=trip.days,
        notes=trip.notes,
        created_at=trip.created_at.isoformat() if trip.created_at else None,
        updated_at=trip.updated_at.isoformat() if trip.updated_at else None,
    )


@app.post("/api/v1/trips", response_model=TripPayload)
async def create_trip(
    payload: TripPayload,
    user: CurrentUser = Depends(get_current_user),
):
    """Create a new trip owned by the caller."""
    now = datetime.utcnow()
    trip = Trip(
        user_id=user.id,
        name=payload.name,
        origin_name=payload.origin_name,
        origin_lat=payload.origin_lat,
        origin_lng=payload.origin_lng,
        destination_name=payload.destination_name,
        destination_lat=payload.destination_lat,
        destination_lng=payload.destination_lng,
        start_date=payload.start_date,
        end_date=payload.end_date,
        arrival_time=payload.arrival_time,
        daily_drive_cap_hours=payload.daily_drive_cap_hours,
        time_budget_mode=payload.time_budget_mode,
        pins=payload.pins,
        days=payload.days,
        notes=payload.notes,
        created_at=now,
        updated_at=now,
    )
    await trip.insert()
    return _trip_to_payload(trip)


@app.get("/api/v1/trips")
async def list_trips(user: CurrentUser = Depends(get_current_user)):
    """List the caller's trips, most recently updated first."""
    docs = (
        await Trip.find(Trip.user_id == user.id)
        .sort(-Trip.updated_at)
        .to_list()
    )
    return {"trips": [_trip_to_payload(t).model_dump() for t in docs]}


@app.get("/api/v1/trips/{trip_id}", response_model=TripPayload)
async def get_trip(
    trip_id: str,
    user: CurrentUser = Depends(get_current_user),
):
    """Read a single trip. 404s if it doesn't exist or belongs to someone
    else — we don't leak existence."""
    trip = await Trip.get(trip_id)
    if trip is None or trip.user_id != user.id:
        raise HTTPException(status_code=404, detail="Trip not found")
    return _trip_to_payload(trip)


@app.put("/api/v1/trips/{trip_id}", response_model=TripPayload)
async def update_trip(
    trip_id: str,
    payload: TripPayload,
    user: CurrentUser = Depends(get_current_user),
):
    """Replace the trip's fields. Server preserves user_id + created_at;
    everything else comes from the payload. Saves and returns canonical
    server state so the client doesn't drift on edge cases (timestamps)."""
    trip = await Trip.get(trip_id)
    if trip is None or trip.user_id != user.id:
        raise HTTPException(status_code=404, detail="Trip not found")
    trip.name = payload.name
    trip.origin_name = payload.origin_name
    trip.origin_lat = payload.origin_lat
    trip.origin_lng = payload.origin_lng
    trip.destination_name = payload.destination_name
    trip.destination_lat = payload.destination_lat
    trip.destination_lng = payload.destination_lng
    trip.start_date = payload.start_date
    trip.end_date = payload.end_date
    trip.arrival_time = payload.arrival_time
    trip.daily_drive_cap_hours = payload.daily_drive_cap_hours
    trip.time_budget_mode = payload.time_budget_mode
    trip.pins = payload.pins
    trip.days = payload.days
    trip.notes = payload.notes
    trip.updated_at = datetime.utcnow()
    await trip.save()
    return _trip_to_payload(trip)


@app.delete("/api/v1/trips/{trip_id}")
async def delete_trip(
    trip_id: str,
    user: CurrentUser = Depends(get_current_user),
):
    trip = await Trip.get(trip_id)
    if trip is None or trip.user_id != user.id:
        raise HTTPException(status_code=404, detail="Trip not found")
    await trip.delete()
    return {"success": True}


@app.get("/api/v1/poi/facts")
async def get_poi_facts():
    """Legacy stub from pre-Phase-1. The real narration endpoint is
    `/api/v1/route/facts` — see RouteFactsRequest below."""
    return {"message": "Use /api/v1/route/facts (Phase 1 narration)"}


class RouteFactsRequest(BaseModel):
    """Body for `/api/v1/route/facts`. Polyline is the Mapbox-encoded
    geometry of the planned drive (precision 6, as Mapbox Navigation
    SDK emits). `user_interests` defaults to the caller's profile when
    omitted — pass it explicitly for testing or to override."""
    polyline: str
    user_interests: Optional[list[dict]] = None


class RouteFact(BaseModel):
    """One whisper-ready fact returned to the client.

    `primary_audio_url` and `follow_up_audio_urls` point to mp3 files
    pre-synthesized by OpenAI TTS at trip-prep time. When present, the
    device plays the mp3 directly (premium voice). When null (synthesis
    failed or the env doesn't have OPENAI_API_KEY), the device falls
    back to local Android TTS using the text fields.
    """
    lat: float
    lng: float
    article_title: str
    article_url: str
    wikipedia_pageid: int
    primary: str
    primary_audio_url: Optional[str] = None
    follow_ups: list[str] = []
    follow_up_audio_urls: list[Optional[str]] = []
    is_thin: bool = False
    distance_from_route_miles: float
    ranked_score: float


# Redis TTL for the per-route response cache. Wikipedia content
# doesn't churn often; users re-driving the same trip within a week
# hit cache. After a week we let it expire just in case a referenced
# article was revised.
_ROUTE_FACTS_TTL_SECONDS = 7 * 24 * 60 * 60


@app.post("/api/v1/route/facts")
async def route_facts(
    body: RouteFactsRequest,
    user: CurrentUser = Depends(get_current_user),
):
    """Phase 1 narration endpoint.

    Pipeline:
      1. Decode polyline + Wikipedia GeoSearch around sample points
         (services/wikipedia_facts.py)
      2. Rank candidates and pick top-N (services/fact_ranker.py)
      3. For each kept article, check POIContent cache; if miss,
         call LLM summarizer and persist the result
         (services/llm_summarizer.py)
      4. Cache the assembled response in Redis keyed by polyline hash

    Returns a `{facts: [RouteFact, ...]}` envelope. The client's
    NarrationService consumes this and triggers narration on GPS
    proximity.
    """
    from app.services.wikipedia_facts import WikipediaFactsService
    from app.services.fact_ranker import rank_candidates
    from app.services.llm_summarizer import LLMSummarizer
    import hashlib
    import json
    import asyncio

    polyline = (body.polyline or "").strip()
    if not polyline:
        return {"facts": []}

    # Redis cache: per-route. Keyed by polyline hash + interests
    # hash, so a different user with different interests gets a
    # different cached envelope.
    interests = body.user_interests
    if interests is None:
        profile = await UserProfile.find_one(UserProfile.user_id == user.id)
        interests = list(profile.interests) if profile else []

    route_key = _route_facts_cache_key(polyline, interests)
    redis = await get_redis()
    cached = await redis.get(route_key)
    if cached:
        try:
            return {"facts": json.loads(cached)}
        except json.JSONDecodeError:
            # Corrupt cache — log and rebuild rather than fail.
            logger.warning("route facts cache corrupt for %s; rebuilding", route_key)

    # 1) Discovery
    wiki = WikipediaFactsService()
    try:
        candidates = await wiki.geosearch_along_polyline(polyline)
    finally:
        await wiki.close()
    if not candidates:
        await redis.set(route_key, "[]", ex=_ROUTE_FACTS_TTL_SECONDS)
        return {"facts": []}

    # 2) Rank + cap
    ranked = rank_candidates(candidates, user_interests=interests)
    if not ranked:
        await redis.set(route_key, "[]", ex=_ROUTE_FACTS_TTL_SECONDS)
        return {"facts": []}

    # 3) Per-article summarization + TTS synthesis with POIContent cache
    from app.services.openai_tts import TtsSynthesizer
    summarizer = LLMSummarizer()
    tts = TtsSynthesizer()
    # Reopen a wiki client for cache-miss extract fetches. We keep
    # the same instance for the whole batch so the connection pool
    # is reused and concurrency is shared with the existing geosearch
    # semaphore inside the service.
    wiki_for_extracts = WikipediaFactsService()
    facts_out: list[dict] = []
    # Summarize in parallel via to_thread (Anthropic + OpenAI SDKs are
    # both sync). Bounded concurrency so we don't spike costs or rate
    # limits.
    sem = asyncio.Semaphore(4)

    async def _process(ranked_fact):
        c = ranked_fact.candidate
        async with sem:
            bundle = await _get_or_summarize(summarizer, tts, wiki_for_extracts, c)
        return {
            "lat": c.lat,
            "lng": c.lng,
            "article_title": c.title,
            "article_url": c.url,
            "wikipedia_pageid": c.wikipedia_pageid,
            "primary": bundle["primary"],
            "primary_audio_url": bundle["primary_audio_url"],
            "follow_ups": bundle["follow_ups"],
            "follow_up_audio_urls": bundle["follow_up_audio_urls"],
            "is_thin": bundle["is_thin"],
            "distance_from_route_miles": c.distance_from_route_miles,
            "ranked_score": ranked_fact.score,
        }

    try:
        facts_out = await asyncio.gather(*[_process(r) for r in ranked])
    finally:
        await wiki_for_extracts.close()

    # Skip facts whose summarization failed entirely (no primary text).
    facts_out = [f for f in facts_out if f.get("primary")]

    # 4) Cache the assembled envelope
    await redis.set(
        route_key,
        json.dumps(facts_out),
        ex=_ROUTE_FACTS_TTL_SECONDS,
    )
    return {"facts": facts_out}


def _route_facts_cache_key(polyline: str, interests: list[dict]) -> str:
    """Redis key for the per-route response cache. Polyline hash +
    interests hash so users with different tastes get different
    cached responses for the same route."""
    import hashlib
    h = hashlib.sha1()
    h.update(polyline.encode())
    # Interests are dicts; canonical JSON makes the hash stable
    # regardless of dict key order.
    h.update(json.dumps(interests, sort_keys=True, default=str).encode()
             if interests else b"[]")
    # v2 forces a refresh after the TTS model bump so previously-
    # cached routes don't keep serving the old voice. Bump again on
    # any change that affects response shape.
    return f"route_facts:v2:{h.hexdigest()}"


# Bump this when the TTS model or prompt changes meaningfully. Old
# POIContent entries with a different version get treated as a
# cache miss, forcing re-synthesis with the current voice / model.
# Text content (primary/follow_ups) is preserved from cache when
# possible to avoid re-paying for the LLM summarization.
_TTS_VERSION = "v2-gpt4omini-nova"


async def _get_or_summarize(summarizer, tts, wiki, candidate) -> dict:
    """POIContent-level cache: keyed by wikipedia_pageid. Hits across
    users and routes. On miss, fetch the Wikipedia extract, call the
    LLM, synthesize TTS audio for primary + each follow-up, persist
    the whole bundle. The extract fetch is lazy — we only hit
    Wikipedia for articles whose text isn't already cached, which
    keeps us well below Wikipedia's bot rate limits on repeat trips.

    Returned dict shape includes both the text and the audio URLs
    (string paths the device prepends its base URL to). Audio URLs
    may be null if synthesis failed for a particular line — the
    device falls back to local TTS for those.
    """
    import asyncio
    from app.database import POIContent
    pageid = candidate.wikipedia_pageid

    existing = await POIContent.find_one(POIContent.poi_id == f"wiki:{pageid}")
    cached_primary: str | None = None
    cached_follow_ups: list[str] | None = None
    cached_is_thin: bool = False
    if existing and existing.facts:
        first = existing.facts[0] if isinstance(existing.facts[0], dict) else {}
        cached_primary = first.get("primary")
        cached_follow_ups = first.get("follow_ups")
        cached_is_thin = bool(first.get("is_thin", False))
        # Full cache hit: audio synthesized with current model AND
        # actual bytes present. Skip extract + LLM + TTS entirely.
        if (
            cached_primary
            and first.get("tts_version") == _TTS_VERSION
            and first.get("primary_audio")
        ):
            return _bundle_to_response(first, pageid)

    # Partial cache hit: text exists from a prior LLM run but audio
    # needs refreshing (TTS version bumped). Reuse text, skip the
    # Wikipedia + LLM round-trip, just re-synthesize.
    if cached_primary is not None and cached_follow_ups is not None:
        bundle = SimpleNamespaceLike(
            primary=cached_primary,
            follow_ups=cached_follow_ups,
            is_thin=cached_is_thin,
        )
    else:
        # Full miss: fetch the Wikipedia extract NOW (didn't fetch
        # upfront, only on demand) and summarize.
        extract = candidate.extract or await wiki.fetch_extract(pageid)
        if not extract:
            # Wikipedia 429'd or the article disappeared — produce
            # a placeholder bundle so the orchestration layer doesn't
            # blow up. The endpoint filters these out before
            # returning to the device.
            return {
                "primary": "",
                "primary_audio_url": None,
                "follow_ups": [],
                "follow_up_audio_urls": [],
                "is_thin": True,
            }
        bundle = await asyncio.to_thread(
            summarizer.summarize_article,
            candidate.title,
            extract,
        )

    # Synthesize audio for each text line. tts.synthesize returns
    # None on failure; we persist None and the response surfaces a
    # null audio_url so the device falls back to local TTS for
    # that specific line.
    primary_audio = await asyncio.to_thread(tts.synthesize, bundle.primary)
    follow_ups_audio = await asyncio.gather(*[
        asyncio.to_thread(tts.synthesize, fu) for fu in bundle.follow_ups
    ])

    stored = {
        "primary": bundle.primary,
        "primary_audio": primary_audio,
        "follow_ups": bundle.follow_ups,
        "follow_ups_audio": list(follow_ups_audio),
        "is_thin": bundle.is_thin,
        "tts_version": _TTS_VERSION,
    }

    # Persist back to POIContent for future trips.
    doc = existing or POIContent(
        poi_id=f"wiki:{pageid}",
        name=candidate.title,
        category="wikipedia",
        latitude=candidate.lat,
        longitude=candidate.lng,
        metadata={"source": "wikipedia", "pageid": pageid, "url": candidate.url},
    )
    doc.facts = [stored]
    doc.metadata = {**(doc.metadata or {}), "wikipedia_pageid": pageid}
    await doc.save()

    return _bundle_to_response(stored, pageid)


class SimpleNamespaceLike:
    """Tiny shim so the cached-text fast path can produce something
    with the same `.primary` / `.follow_ups` / `.is_thin` attributes
    the LLM summarizer returns. Avoids importing SummaryBundle here
    just to repackage cached strings."""
    def __init__(self, primary: str, follow_ups: list, is_thin: bool):
        self.primary = primary
        self.follow_ups = list(follow_ups)
        self.is_thin = is_thin


def _bundle_to_response(stored: dict, pageid: int) -> dict:
    """Convert the POIContent-stored bundle into the response shape the
    device consumes. Replaces the raw audio bytes with audio URLs
    pointing at `/api/v1/audio/{audio_id}` — the device fetches the
    bytes on demand rather than receiving them inline (keeps the
    /route/facts JSON small).
    """
    primary_audio_url = (
        f"/api/v1/audio/wiki-{pageid}-primary"
        if stored.get("primary_audio") else None
    )
    follow_ups = stored.get("follow_ups", []) or []
    follow_ups_audio = stored.get("follow_ups_audio", []) or []
    follow_up_audio_urls = []
    for i in range(len(follow_ups)):
        has_audio = (
            i < len(follow_ups_audio)
            and follow_ups_audio[i] is not None
            and len(follow_ups_audio[i]) > 0
        )
        follow_up_audio_urls.append(
            f"/api/v1/audio/wiki-{pageid}-fu-{i}" if has_audio else None
        )
    return {
        "primary": stored.get("primary", ""),
        "primary_audio_url": primary_audio_url,
        "follow_ups": follow_ups,
        "follow_up_audio_urls": follow_up_audio_urls,
        "is_thin": bool(stored.get("is_thin", False)),
    }


@app.get("/api/v1/audio/wiki-{pageid}-primary")
async def audio_primary(pageid: int):
    """Serve the pre-synthesized mp3 for a Wikipedia article's primary
    narration. Stored in POIContent.facts[0].primary_audio. No auth
    on this endpoint — audio URLs are not secret and gating them
    would force the device to attach an auth header to MediaPlayer
    which complicates Android playback. The audio is the same content
    as the public Wikipedia article, just spoken."""
    return await _serve_audio(pageid, "primary")


@app.get("/api/v1/audio/wiki-{pageid}-fu-{index}")
async def audio_follow_up(pageid: int, index: int):
    """Serve the pre-synthesized mp3 for the Nth follow-up of a
    Wikipedia article's narration. Mirror of /primary above; same
    rationale for no auth."""
    return await _serve_audio(pageid, "fu", index=index)


async def _serve_audio(pageid: int, kind: str, *, index: int = -1):
    """Look up the cached mp3 bytes in POIContent and return them with
    audio/mpeg content type. 404 if the page or audio doesn't exist."""
    from fastapi.responses import Response
    doc = await POIContent.find_one(POIContent.poi_id == f"wiki:{pageid}")
    if doc is None or not doc.facts:
        raise HTTPException(status_code=404, detail="No audio for that pageid")
    first = doc.facts[0] if isinstance(doc.facts[0], dict) else {}
    audio: Optional[bytes] = None
    if kind == "primary":
        audio = first.get("primary_audio")
    elif kind == "fu":
        fus = first.get("follow_ups_audio") or []
        if 0 <= index < len(fus):
            audio = fus[index]
    if not audio:
        raise HTTPException(status_code=404, detail="No audio bytes")
    return Response(
        content=bytes(audio),
        media_type="audio/mpeg",
        # Browsers / MediaPlayer cache aggressively — narration content
        # never changes once synthesized.
        headers={"Cache-Control": "public, max-age=86400"},
    )


class GeocodeCandidate(BaseModel):
    name: str
    full_address: Optional[str] = None
    lat: float
    lng: float
    place_type: Optional[str] = None
    mapbox_id: str = ""


@app.get("/api/v1/geocode")
async def geocode(
    q: str,
    proximity_lat: Optional[float] = None,
    proximity_lng: Optional[float] = None,
    limit: int = 5,
    user: CurrentUser = Depends(get_current_user),
):
    """Forward-geocode a free-text query into address candidates.

    Used by the trip-planner wizard's origin/destination pickers.
    `proximity_lat`/`proximity_lng` bias results toward the user's region;
    omit them and Mapbox falls back to global ranking. Authed so we keep
    the geocode quota tied to logged-in users.
    """
    q = (q or "").strip()
    if not q:
        return {"candidates": []}

    proximity = None
    if proximity_lat is not None and proximity_lng is not None:
        proximity = (proximity_lat, proximity_lng)

    service = MapboxSearchService()
    try:
        results = await service.forward_geocode(q, proximity=proximity, limit=limit)
    finally:
        await service.close()
    return {"candidates": [GeocodeCandidate(**r).model_dump() for r in results]}

class EngineContext(BaseModel):
    """Per-request context describing *where and when* the call is happening.
    See docs/recommendations-brief.md → 'Engine interface'."""
    route_polyline: Optional[str] = None
    current_location: Optional[list[float]] = None  # [lat, lng]
    minutes_into_trip: Optional[int] = None
    minutes_remaining: Optional[int] = None
    hours_since_last_stop: Optional[float] = None
    fuel_state: Optional[str] = None  # placeholder
    time_budget_mode: str = "moderate"  # hurry | moderate | discovery
    # `trip_scale` is optional in the request; the backend derives it from
    # `route_polyline` if missing.
    trip_scale: Optional[str] = None


class EngineIntent(BaseModel):
    """What the caller is asking for. Defaults express a passive auto-poll
    invocation; manual / planning / voice callers MUST set `invocation`."""
    invocation: str = "auto"  # auto | manual | planning | voice
    desired_categories: Optional[list[str]] = None
    desired_interests: Optional[list[dict]] = None
    constraints: Optional[dict] = None
    natural_language_query: Optional[str] = None


class EngineRequest(BaseModel):
    """Top-level engine request envelope."""
    context: EngineContext
    intent: EngineIntent = Field(default_factory=EngineIntent)


@app.post("/api/v1/recommendations/stops")
async def get_stop_recommendations(
    request: EngineRequest,
    user: CurrentUser = Depends(get_current_user),
):
    """Proactive stop suggestions following the engine interface defined
    in docs/recommendations-brief.md.

    Pipeline:
      1. Derive trip scale (use request value if supplied, else from route).
      2. Pull profile (preferred categories + interests).
      3. Determine which Mapbox categories to search (intent override >
         profile interests > profile categories > defaults).
      4. Run POI discovery along the route.
      5. Pull stop-history aggregates from MongoDB.
      6. Score with the four-dimension engine.
      7. Return top suggestions.
    """
    if request.context.route_polyline is None:
        return {"suggestions": []}

    profile = await UserProfile.find_one(UserProfile.user_id == user.id)
    preferred_categories = profile.preferred_poi_types if profile else []
    profile_interests = profile.interests if profile else []

    # Derive trip scale.
    route_points = decode_polyline(request.context.route_polyline)
    if not route_points:
        return {"suggestions": []}
    try:
        trip_scale = (
            TripScale(request.context.trip_scale)
            if request.context.trip_scale
            else detect_trip_scale(route_points)
        )
    except ValueError:
        trip_scale = detect_trip_scale(route_points)

    # Determine which Mapbox categories to search.
    # Priority: explicit intent > profile interests > profile categories > defaults.
    explicit = request.intent.desired_categories or []
    if explicit:
        category_strs = explicit
    else:
        # Fan out interest mapbox_categories first, then add broad categories.
        interest_cats: list[str] = []
        for i in profile_interests or []:
            interest_cats.extend(i.get("mapbox_categories") or [])
        category_strs = interest_cats + (preferred_categories or [])
    # Map any that fit our POICategory enum; ignore the rest (they'd need
    # future Mapbox-subcategory query expansion to actually search).
    categories = [
        POICategory(c) for c in category_strs
        if c in POICategory._value2member_map_
    ]
    if not categories:
        categories = [
            POICategory.GAS_STATION,
            POICategory.RESTAURANT,
            POICategory.COFFEE,
            POICategory.SCENIC,
        ]

    # POI discovery (no cache; recs are personalized).
    mid_idx = len(route_points) // 2
    proximity = route_points[mid_idx]
    bounds = calculate_bounds(route_points)
    mapbox_service = MapboxSearchService()
    try:
        pois = await mapbox_service.search_multiple_categories(
            categories=categories,
            proximity=proximity,
            bbox=bounds,
            limit_per_category=10,  # 3 was too few; scorer needs a pool
        )
    finally:
        await mapbox_service.close()
    pois = POIRankingService.filter_and_rank(
        pois=pois,
        route_points=route_points,
        max_results=30,  # 20 was too tight for the engine's hard filters
        distribute=True,
    )

    # History aggregates (two-query fan-out).
    cat_avg_rows = await WaypointStopHistoryDoc.aggregate(
        [
            {"$match": {"user_id": user.id, "waypoint_category": {"$ne": None}}},
            {
                "$group": {
                    "_id": "$waypoint_category",
                    "count": {"$sum": 1},
                    "avg_actual_minutes": {"$avg": "$actual_duration_minutes"},
                }
            },
        ]
    ).to_list()
    category_averages = {
        r["_id"]: {
            "count": r["count"],
            "avg_actual_minutes": r["avg_actual_minutes"] or 0,
        }
        for r in cat_avg_rows
    }
    hour_rows = await WaypointStopHistoryDoc.aggregate(
        [
            {"$match": {"user_id": user.id, "hour_of_day": {"$ne": None}}},
            {"$group": {"_id": "$hour_of_day", "count": {"$sum": 1}}},
        ]
    ).to_list()
    by_hour = [{"hour": r["_id"], "count": r["count"]} for r in hour_rows]

    # Map the wire enums to the scorer's enums.
    try:
        mode = TimeBudgetMode(request.context.time_budget_mode)
    except ValueError:
        mode = TimeBudgetMode.MODERATE
    try:
        invocation = Invocation(request.intent.invocation)
    except ValueError:
        invocation = Invocation.AUTO

    ranked = rank_suggestions(
        pois,
        profile_categories=preferred_categories,
        profile_interests=profile_interests or [],
        category_averages=category_averages,
        by_hour=by_hour,
        mode=mode,
        trip_scale=trip_scale,
        invocation=invocation,
        hours_since_last_stop=request.context.hours_since_last_stop,
        now=datetime.utcnow(),
        limit=3,
    )

    return {
        "suggestions": [
            {
                "poi": s.poi.model_dump(mode="json"),
                "score": round(s.score, 3),
                "reason": s.reason,
            }
            for s in ranked
        ]
    }

@app.get("/api/v1/collaboration/status")
async def get_collaboration_status():
    """Get real-time collaboration status - TODO: Implement in Step 9"""
    return {"message": "Collaboration status endpoint - Coming in Step 9"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True) 