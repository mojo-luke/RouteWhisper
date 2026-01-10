"""
Mapbox Search API integration service
Uses Mapbox Search Box API v1 for POI discovery
"""

import os
import asyncio
import httpx
from typing import List, Optional, Tuple
import logging

from app.models import POI, POICategory, CATEGORY_DURATION_MAP

logger = logging.getLogger(__name__)


# Map our POI categories to Mapbox Search API categories
MAPBOX_CATEGORY_MAP = {
    POICategory.GAS_STATION: ["gas_station", "fuel"],
    POICategory.RESTAURANT: ["restaurant", "food", "dining"],
    POICategory.COFFEE: ["cafe", "coffee"],
    POICategory.HOTEL: ["hotel", "lodging", "accommodation"],
    POICategory.CAMPING: ["campground", "camping"],
    POICategory.ATTRACTION: ["tourist_attraction", "landmark", "attraction"],
    POICategory.SHOPPING: ["shopping", "mall", "store"],
    POICategory.SCENIC: ["park", "viewpoint", "scenic"],
    POICategory.MUSEUM: ["museum", "gallery", "art"],
    POICategory.PARK: ["park", "recreation"],
    POICategory.HOSPITAL: ["hospital", "medical", "emergency"],
    POICategory.PHARMACY: ["pharmacy", "drugstore"],
    POICategory.BANK: ["bank", "atm"],
    POICategory.GROCERY: ["grocery", "supermarket", "food_store"],
}


class MapboxSearchService:
    """
    Service for querying Mapbox Search API for POIs.

    Uses Mapbox Search Box API v1 for category-based searches.
    Documentation: https://docs.mapbox.com/api/search/search-box/
    """

    # Mapbox Search Box API endpoint
    BASE_URL = "https://api.mapbox.com/search/searchbox/v1"

    def __init__(self, access_token: Optional[str] = None):
        """
        Initialize Mapbox Search service.

        Args:
            access_token: Mapbox secret token with search:read scope.
                         If not provided, reads from MAPBOX_ACCESS_TOKEN env var.
        """
        self.access_token = access_token or os.getenv("MAPBOX_ACCESS_TOKEN")
        if not self.access_token:
            raise ValueError(
                "Mapbox access token required. Set MAPBOX_ACCESS_TOKEN env var "
                "or pass access_token parameter."
            )

        self.client = httpx.AsyncClient(timeout=30.0)
        logger.info("Mapbox Search service initialized")

    async def close(self):
        """Close the HTTP client."""
        await self.client.aclose()

    async def search_category(
        self,
        category: POICategory,
        proximity: Tuple[float, float],
        bbox: Optional[List[float]] = None,
        limit: int = 10
    ) -> List[POI]:
        """
        Search for POIs of a specific category near a location.

        Args:
            category: POI category to search for
            proximity: (latitude, longitude) for search centering
            bbox: Optional bounding box [minLng, minLat, maxLng, maxLat]
            limit: Maximum number of results (1-50)

        Returns:
            List of POI objects

        Example:
            >>> service = MapboxSearchService()
            >>> pois = await service.search_category(
            ...     POICategory.RESTAURANT,
            ...     proximity=(37.7749, -122.4194),
            ...     limit=10
            ... )
        """
        # Get Mapbox category strings for this POI category
        mapbox_categories = MAPBOX_CATEGORY_MAP.get(category, [category.value])

        all_pois = []

        # Search only the first Mapbox category to avoid rate limits
        for mapbox_category in mapbox_categories[:1]:  # Just use primary category
            try:
                pois = await self._search_single_category(
                    mapbox_category=mapbox_category,
                    proximity=proximity,
                    bbox=bbox,
                    limit=limit
                )

                # Convert to our POI model with correct category
                for poi_data in pois:
                    poi = self._convert_to_poi(poi_data, category)
                    if poi:
                        all_pois.append(poi)

            except Exception as e:
                logger.warning(
                    f"Failed to search Mapbox category '{mapbox_category}': {e}"
                )

        # Remove duplicates by ID
        seen_ids = set()
        unique_pois = []
        for poi in all_pois:
            if poi.mapbox_poi_id not in seen_ids:
                seen_ids.add(poi.mapbox_poi_id)
                unique_pois.append(poi)

        logger.info(
            f"Found {len(unique_pois)} unique POIs for category {category.value}"
        )
        return unique_pois[:limit]

    async def _search_single_category(
        self,
        mapbox_category: str,
        proximity: Tuple[float, float],
        bbox: Optional[List[float]] = None,
        limit: int = 10
    ) -> List[dict]:
        """
        Search a single Mapbox category string.

        Args:
            mapbox_category: Mapbox category string (e.g., "restaurant")
            proximity: (latitude, longitude) for search centering
            bbox: Optional bounding box
            limit: Maximum results

        Returns:
            List of raw POI dictionaries from Mapbox API
        """
        # Build query parameters
        params = {
            "access_token": self.access_token,
            "proximity": f"{proximity[1]},{proximity[0]}",  # Mapbox uses lng,lat
            "limit": min(limit, 50),  # Mapbox max is 50
        }

        # TODO: Investigate bbox issues - temporarily disabled
        # Add bounding box if provided
        # if bbox:
        #     params["bbox"] = ",".join(map(str, bbox))

        logger.debug(f"Searching {mapbox_category} with proximity={params['proximity']}")

        # Make request to Mapbox Search API
        url = f"{self.BASE_URL}/category/{mapbox_category}"

        try:
            response = await self.client.get(url, params=params)
            response.raise_for_status()
            data = response.json()

            features = data.get("features", [])
            logger.debug(
                f"Mapbox returned {len(features)} results for '{mapbox_category}'"
            )
            return features

        except httpx.HTTPStatusError as e:
            logger.error(
                f"Mapbox API error for category '{mapbox_category}': "
                f"{e.response.status_code} - {e.response.text}"
            )
            return []
        except Exception as e:
            logger.error(
                f"Unexpected error searching Mapbox category '{mapbox_category}': {e}"
            )
            return []

    def _convert_to_poi(self, mapbox_feature: dict, category: POICategory) -> Optional[POI]:
        """
        Convert Mapbox API feature to our POI model.

        Args:
            mapbox_feature: Raw feature from Mapbox API response
            category: Our POI category to assign

        Returns:
            POI object or None if conversion fails
        """
        try:
            properties = mapbox_feature.get("properties", {})
            geometry = mapbox_feature.get("geometry", {})
            coordinates = geometry.get("coordinates", [])

            if len(coordinates) != 2:
                return None

            # Extract data from Mapbox response
            lng, lat = coordinates
            name = properties.get("name", "Unknown")
            mapbox_id = properties.get("mapbox_id", "")
            full_address = properties.get("full_address")

            # Get estimated duration for this category
            duration = CATEGORY_DURATION_MAP.get(category, 30)

            # Create POI object
            poi = POI(
                id=f"poi_{mapbox_id[:12]}" if mapbox_id else f"poi_{name[:12]}",
                name=name,
                category=category,
                latitude=lat,
                longitude=lng,
                address=full_address,
                estimated_duration_minutes=duration,
                rating=None,  # Mapbox Search doesn't provide ratings
                distance_from_route_miles=0.0,  # Will be calculated later
                mapbox_poi_id=mapbox_id
            )

            return poi

        except Exception as e:
            logger.warning(f"Failed to convert Mapbox feature to POI: {e}")
            return None

    async def search_multiple_categories(
        self,
        categories: List[POICategory],
        proximity: Tuple[float, float],
        bbox: Optional[List[float]] = None,
        limit_per_category: int = 5
    ) -> List[POI]:
        """
        Search multiple POI categories in parallel.

        Uses asyncio.gather() to query all categories concurrently for
        better performance.

        Args:
            categories: List of POI categories to search
            proximity: (latitude, longitude) for search centering
            bbox: Optional bounding box [minLng, minLat, maxLng, maxLat]
            limit_per_category: Maximum POIs per category

        Returns:
            Combined list of POIs from all categories

        Example:
            >>> service = MapboxSearchService()
            >>> pois = await service.search_multiple_categories(
            ...     categories=[POICategory.RESTAURANT, POICategory.GAS_STATION],
            ...     proximity=(37.7749, -122.4194),
            ...     limit_per_category=5
            ... )
        """
        logger.info(
            f"Searching {len(categories)} categories in parallel near "
            f"{proximity}"
        )

        # Create search tasks for all categories
        tasks = [
            self.search_category(
                category=cat,
                proximity=proximity,
                bbox=bbox,
                limit=limit_per_category
            )
            for cat in categories
        ]

        # Execute all searches in parallel
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Combine results, handling any exceptions
        all_pois = []
        for category, result in zip(categories, results):
            if isinstance(result, Exception):
                logger.error(f"Failed to search category {category.value}: {result}")
            else:
                all_pois.extend(result)

        logger.info(f"Found total of {len(all_pois)} POIs across all categories")
        return all_pois
