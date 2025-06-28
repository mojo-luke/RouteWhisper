"""
RouteWhisper Backend API
Main FastAPI application entry point with hybrid database setup
"""

from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager

# Import database initialization functions
from database import init_mongodb, init_redis, create_tables, get_db, get_redis

# Lifespan context manager for startup/shutdown events
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    print("🚀 Starting RouteWhisper API...")
    
    # Initialize PostgreSQL tables
    print("📊 Creating PostgreSQL tables...")
    create_tables()
    
    # Initialize MongoDB connection
    print("🍃 Connecting to MongoDB Atlas...")
    await init_mongodb()
    
    # Initialize Redis connection
    print("🔴 Connecting to Redis...")
    await init_redis()
    
    print("✅ All databases initialized successfully!")
    
    yield
    
    # Shutdown
    print("🛑 Shutting down RouteWhisper API...")

# Create FastAPI instance with lifespan
app = FastAPI(
    title="RouteWhisper API",
    description="Backend API for RouteWhisper - The intelligent road trip companion with hybrid database architecture",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan
)

# Configure CORS for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],  # Flutter dev server
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Health check endpoint
@app.get("/health")
async def health_check(db=Depends(get_db), redis=Depends(get_redis)):
    """Health check endpoint with database connectivity"""
    
    # Test PostgreSQL connection
    postgres_status = "connected"
    try:
        db.execute("SELECT 1")
    except Exception as e:
        postgres_status = f"error: {str(e)}"
    
    # Test Redis connection
    redis_status = "connected"
    try:
        await redis.ping()
    except Exception as e:
        redis_status = f"error: {str(e)}"
    
    return JSONResponse(
        status_code=200,
        content={
            "status": "healthy", 
            "service": "RouteWhisper API",
            "databases": {
                "postgresql": postgres_status,
                "mongodb": "connected",  # Beanie handles connection
                "redis": redis_status
            }
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
        "architecture": "Hybrid Database (PostgreSQL + MongoDB Atlas + Redis)"
    }

# Placeholder endpoints for future implementation
@app.get("/api/v1/route/analyze")
async def analyze_route():
    """Analyze route and return POI data - TODO: Implement in Step 3"""
    return {"message": "Route analysis endpoint - Coming in Step 3"}

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