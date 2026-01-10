"""
Redis caching service for POI queries
Implements caching with TTL to reduce Mapbox API calls
"""

import hashlib
import json
import logging
from typing import Optional, List

from redis.asyncio import Redis

from app.models import POI

logger = logging.getLogger(__name__)


class POICacheService:
    """
    Redis caching service for POI discovery results.

    Caches POI query results with 1-hour TTL to reduce API calls
    and improve response times.
    """

    def __init__(self, redis_client: Redis, ttl: int = 3600):
        """
        Initialize cache service.

        Args:
            redis_client: Redis async client instance
            ttl: Time-to-live in seconds (default 1 hour)
        """
        self.redis = redis_client
        self.ttl = ttl
        logger.info(f"POI cache service initialized with TTL={ttl}s")

    def generate_cache_key(
        self,
        polyline: str,
        categories: List[str],
        radius: float
    ) -> str:
        """
        Generate consistent cache key from request parameters.

        Uses MD5 hash of parameters to create a fixed-length key.

        Args:
            polyline: Encoded route polyline
            categories: List of category strings
            radius: Search radius in miles

        Returns:
            Cache key string

        Example:
            >>> service = POICacheService(redis)
            >>> key = service.generate_cache_key(
            ...     "_p~iF~ps|U_ulLnnqC",
            ...     ["restaurant", "gas_station"],
            ...     5.0
            ... )
            >>> key
            'poi:route:a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6'
        """
        # Sort categories for consistency
        sorted_categories = sorted(categories)

        # Create data string
        data = f"{polyline}:{','.join(sorted_categories)}:{radius}"

        # Generate MD5 hash
        hash_obj = hashlib.md5(data.encode())
        hash_hex = hash_obj.hexdigest()

        # Create prefixed key
        cache_key = f"poi:route:{hash_hex}"

        logger.debug(f"Generated cache key: {cache_key}")
        return cache_key

    async def get_cached_pois(self, cache_key: str) -> Optional[List[POI]]:
        """
        Retrieve cached POI list from Redis.

        Args:
            cache_key: Cache key to look up

        Returns:
            List of POI objects if found, None if cache miss
        """
        try:
            cached_data = await self.redis.get(cache_key)

            if cached_data is None:
                logger.debug(f"Cache miss for key: {cache_key}")
                return None

            # Deserialize JSON to POI objects
            pois_data = json.loads(cached_data)
            pois = [POI(**poi_dict) for poi_dict in pois_data]

            logger.info(f"Cache hit for key: {cache_key} ({len(pois)} POIs)")
            return pois

        except json.JSONDecodeError as e:
            logger.error(f"Failed to decode cached POIs: {e}")
            # Delete corrupted cache entry
            await self.redis.delete(cache_key)
            return None
        except Exception as e:
            logger.error(f"Error retrieving cached POIs: {e}")
            return None

    async def cache_pois(
        self,
        cache_key: str,
        pois: List[POI]
    ) -> bool:
        """
        Cache POI list in Redis with TTL.

        Args:
            cache_key: Cache key to store under
            pois: List of POI objects to cache

        Returns:
            True if caching succeeded, False otherwise
        """
        try:
            # Serialize POIs to JSON
            pois_data = [poi.model_dump() for poi in pois]
            json_data = json.dumps(pois_data)

            # Store with TTL
            await self.redis.setex(
                cache_key,
                self.ttl,
                json_data
            )

            logger.info(
                f"Cached {len(pois)} POIs under key: {cache_key} "
                f"(TTL={self.ttl}s)"
            )
            return True

        except Exception as e:
            logger.error(f"Failed to cache POIs: {e}")
            return False

    async def invalidate_cache(self, cache_key: str) -> bool:
        """
        Manually invalidate (delete) a cache entry.

        Args:
            cache_key: Cache key to invalidate

        Returns:
            True if deletion succeeded, False otherwise
        """
        try:
            deleted = await self.redis.delete(cache_key)
            if deleted:
                logger.info(f"Invalidated cache key: {cache_key}")
            else:
                logger.debug(f"Cache key not found for invalidation: {cache_key}")
            return bool(deleted)

        except Exception as e:
            logger.error(f"Failed to invalidate cache: {e}")
            return False

    async def get_cache_stats(self) -> dict:
        """
        Get cache statistics (for monitoring/debugging).

        Returns:
            Dictionary with cache statistics
        """
        try:
            # Count POI-related keys
            keys = await self.redis.keys("poi:route:*")
            num_keys = len(keys)

            # Get Redis info
            info = await self.redis.info("stats")
            total_keys = info.get("db0", {}).get("keys", 0)

            stats = {
                "poi_cache_keys": num_keys,
                "total_redis_keys": total_keys,
                "ttl_seconds": self.ttl,
            }

            logger.debug(f"Cache stats: {stats}")
            return stats

        except Exception as e:
            logger.error(f"Failed to get cache stats: {e}")
            return {}
