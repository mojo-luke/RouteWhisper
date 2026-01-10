"""
RouteWhisper Backend API
Main FastAPI application entry point
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import redis.asyncio as aioredis
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Import POI models and services
from app.models import POIRequest, POIResponse, POICategory
from app.services.mapbox_search import MapboxSearchService
from app.services.poi_ranking import POIRankingService
from app.services.cache import POICacheService
from app.utils.polyline import decode_polyline, calculate_bounds

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
async def discover_route_pois(request: POIRequest):
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

        # Check cache
        cached_pois = await cache_service.get_cached_pois(cache_key)
        if cached_pois:
            # Decode polyline for bounds calculation
            route_points = decode_polyline(request.encoded_polyline)
            bounds = calculate_bounds(route_points)

            logger.info(f"Cache hit! Returning {len(cached_pois)} cached POIs")
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

        # Step 7: Cache results
        await cache_service.cache_pois(cache_key, final_pois)

        # Step 8: Clean up
        await mapbox_service.close()

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

@app.get("/api/v1/poi/facts")
async def get_poi_facts():
    """Get facts for specific POI - TODO: Implement in Step 4"""
    return {"message": "POI facts endpoint - Coming in Step 4"}

@app.get("/api/v1/recommendations/stops")
async def get_stop_recommendations():
    """Get stop recommendations along route - TODO: Implement in Step 7"""
    return {"message": "Stop recommendations endpoint - Coming in Step 7"}

@app.get("/api/v1/collaboration/status")
async def get_collaboration_status():
    """Get real-time collaboration status - TODO: Implement in Step 9"""
    return {"message": "Collaboration status endpoint - Coming in Step 9"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True) 