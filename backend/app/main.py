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
    p.updated_at = datetime.utcnow()
    await p.save()
    return payload

@app.get("/api/v1/poi/facts")
async def get_poi_facts():
    """Get facts for specific POI - TODO: Implement in Step 4"""
    return {"message": "POI facts endpoint - Coming in Step 4"}

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