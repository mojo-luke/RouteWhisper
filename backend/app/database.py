"""
Hybrid Database configuration for RouteWhisper
- PostgreSQL: Structured data (users, trips, relationships)
- MongoDB: Flexible content (POI facts, external API data)
- Redis: Caching and session management
"""

import os
from datetime import datetime
from typing import Optional

# PostgreSQL imports
from sqlalchemy import Column, Integer, String, Float, Text, DateTime, Boolean, ForeignKey, create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship, sessionmaker

# MongoDB imports
from motor.motor_asyncio import AsyncIOMotorClient
from beanie import Document, init_beanie
import pymongo

# Redis imports
import redis.asyncio as redis

# Environment
from dotenv import load_dotenv

load_dotenv()

# =============================================================================
# PostgreSQL Setup (Structured Data)
# =============================================================================

# Database URL from environment
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./routewhisper.db")

# Create engine
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Base class for models
Base = declarative_base()

# PostgreSQL Models (Structured Data)

class User(Base):
    """User accounts and preferences"""
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)
    username = Column(String, unique=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # User preferences
    preferred_poi_types = Column(Text)  # JSON string of preferred POI categories
    time_budget_default = Column(String, default="moderate")  # hurry, moderate, plenty
    
    # Relationships
    trips = relationship("Trip", back_populates="user")

class Trip(Base):
    """Individual trips/routes"""
    __tablename__ = "trips"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    
    # Trip details
    name = Column(String)
    start_location = Column(String)
    end_location = Column(String)
    start_coords = Column(String)  # "lat,lng"
    end_coords = Column(String)    # "lat,lng"
    
    # Trip settings
    time_budget = Column(String, default="moderate")
    trip_type = Column(String)  # "local", "regional", "long_distance"
    total_distance_miles = Column(Float)
    estimated_duration_hours = Column(Float)
    
    # Multi-day planning
    planned_days = Column(Integer, default=1)
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    started_at = Column(DateTime)
    completed_at = Column(DateTime)
    
    # Relationships
    user = relationship("User", back_populates="trips")
    trip_stops = relationship("TripStop", back_populates="trip")

class TripStop(Base):
    """Planned stops along the route"""
    __tablename__ = "trip_stops"
    
    id = Column(Integer, primary_key=True, index=True)
    trip_id = Column(Integer, ForeignKey("trips.id"))
    
    # Stop details
    name = Column(String)
    category = Column(String)  # restaurant, gas, hotel, attraction, etc.
    
    # Location
    latitude = Column(Float)
    longitude = Column(Float)
    address = Column(Text)
    
    # Planning
    planned_arrival = Column(DateTime)
    estimated_duration_minutes = Column(Integer)
    stop_order = Column(Integer)  # Order in the trip
    
    # Status
    added_by_user = Column(Boolean, default=True)  # vs. system suggestion
    completed = Column(Boolean, default=False)
    
    # External integration
    booking_reference = Column(String)  # For hotels, restaurants, etc.
    
    # Relationships
    trip = relationship("Trip", back_populates="trip_stops")

# =============================================================================
# MongoDB Setup (Flexible Content)
# =============================================================================

# MongoDB connection
MONGODB_URL = os.getenv("MONGODB_URL")
MONGODB_DATABASE = os.getenv("MONGODB_DATABASE", "routewhisper_content")

class POIContent(Document):
    """Points of Interest and their facts (MongoDB)"""
    
    # Basic POI info
    poi_id: str  # Reference to POI in PostgreSQL or external ID
    name: str
    category: str  # landmark, restaurant, gas_station, etc.
    subcategory: Optional[str] = None
    
    # Location
    latitude: float
    longitude: float
    address: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    country: str = "US"
    
    # Flexible content structure
    facts: list = []  # Array of fact objects
    external_data: dict = {}  # Data from Yelp, Google Places, etc.
    metadata: dict = {}  # Source info, timestamps, etc.
    
    # For trip context
    trip_contexts: list = []  # Different contexts this POI appears in
    
    class Settings:
        name = "poi_content"
        # NOTE: the previous compound geo index (`latitude`, `longitude` both
        # GEO2D) was rejected by MongoDB ("can't have 2 geo fields") and
        # prevented the whole app from starting once init_mongodb() began
        # running on boot. When POIContent is actually used (Step 4 narration),
        # add a single 2dsphere index on a proper GeoJSON `location` field.
        indexes = [
            "category",
            "poi_id",
        ]

class TripCollaboration(Document):
    """Real-time trip collaboration data (MongoDB)"""
    
    trip_id: str
    participants: list = []  # User IDs
    current_suggestions: list = []
    pending_decisions: list = []
    shared_state: dict = {}
    last_updated: datetime
    
    class Settings:
        name = "trip_collaboration"

class CachedAPIResponse(Document):
    """Cache external API responses (MongoDB)"""

    api_source: str  # "yelp", "google_places", "wikipedia", etc.
    query_hash: str  # Hash of the query parameters
    response_data: dict
    cached_at: datetime
    expires_at: datetime

    class Settings:
        name = "cached_api_responses"
        indexes = ["api_source", "query_hash", "expires_at"]


class WaypointStopHistoryDoc(Document):
    """Persisted waypoint stop history, keyed by Supabase user id.

    Mirrors the wire-format `WaypointStopHistory` Pydantic model in
    `app/models.py` but adds the authenticated user id and the document
    indexes the analytics endpoints rely on. Don't import this in API
    request signatures — keep request shapes in `models.py`, persist via
    this class.
    """

    user_id: str
    waypoint_id: str
    waypoint_name: str
    waypoint_category: Optional[str] = None
    latitude: float
    longitude: float

    planned_duration_minutes: int
    actual_duration_minutes: int
    duration_difference_minutes: Optional[int] = None

    arrival_time: datetime
    departure_time: datetime

    day_of_week: Optional[int] = None
    hour_of_day: Optional[int] = None
    is_weekend: Optional[bool] = None
    is_automatic_departure: Optional[bool] = False

    waypoint_order: int
    total_waypoints: Optional[int] = None

    recorded_at: datetime = datetime.utcnow()

    class Settings:
        name = "waypoint_stop_history"
        indexes = [
            "user_id",
            [("user_id", 1), ("waypoint_category", 1)],
            [("user_id", 1), ("hour_of_day", 1)],
        ]


class UserProfile(Document):
    """Per-user preferences. One document per Supabase user, looked up by
    `user_id` — that's the unique index on the collection. We keep the
    Supabase id in a normal field rather than as `_id` so we don't have to
    fight Beanie's default ObjectId primary key.
    """

    user_id: str
    preferred_poi_types: list = []
    default_time_budget_minutes: Optional[int] = None
    dietary_restrictions: list = []

    # Step 7 — recommendation surface settings. Defaults match the
    # frontend `_default*` constants for the production build; users can
    # adjust each independently in the preferences screen.
    recommendations_enabled: bool = True
    recommendations_max_per_trip: int = 3
    recommendations_min_gap_minutes: int = 15

    updated_at: datetime = datetime.utcnow()

    class Settings:
        name = "user_profiles"
        indexes = [
            [("user_id", 1)],  # unique enforced at app layer to keep schema simple
        ]

# =============================================================================
# Redis Setup (Caching & Sessions)
# =============================================================================

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
REDIS_TTL = int(os.getenv("REDIS_TTL", 3600))

# Redis client (will be initialized in FastAPI startup)
redis_client: Optional[redis.Redis] = None

# =============================================================================
# Database Dependencies and Initialization
# =============================================================================

# PostgreSQL dependency for FastAPI
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# MongoDB initialization
async def init_mongodb():
    client = AsyncIOMotorClient(MONGODB_URL)
    await init_beanie(
        database=client[MONGODB_DATABASE],
        document_models=[
            POIContent,
            TripCollaboration,
            CachedAPIResponse,
            WaypointStopHistoryDoc,
            UserProfile,
        ],
    )

# Redis initialization
async def init_redis():
    global redis_client
    redis_client = redis.from_url(REDIS_URL)

# Create PostgreSQL tables
def create_tables():
    Base.metadata.create_all(bind=engine)

# Get Redis client
def get_redis():
    return redis_client 