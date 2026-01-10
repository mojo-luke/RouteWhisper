"""
POI ranking and filtering service
Ranks POIs based on distance, rating, category priority, and distribution
"""

import logging
from typing import List, Tuple, Optional

from app.models import POI, CATEGORY_PRIORITY_MAP
from app.utils.polyline import calculate_distance_miles, point_to_line_distance

logger = logging.getLogger(__name__)


class POIRankingService:
    """Service for ranking and filtering POIs based on various criteria."""

    @staticmethod
    def calculate_poi_distances(
        pois: List[POI],
        route_points: List[Tuple[float, float]]
    ) -> List[POI]:
        """
        Calculate distance from each POI to the route.

        Updates the distance_from_route_miles field for each POI.

        Args:
            pois: List of POIs to calculate distances for
            route_points: List of (latitude, longitude) tuples forming the route

        Returns:
            Same list of POIs with updated distances
        """
        for poi in pois:
            poi_point = (poi.latitude, poi.longitude)
            distance = point_to_line_distance(poi_point, route_points)
            poi.distance_from_route_miles = distance

        logger.debug(f"Calculated distances for {len(pois)} POIs")
        return pois

    @staticmethod
    def rank_pois(
        pois: List[POI],
        route_points: Optional[List[Tuple[float, float]]] = None
    ) -> List[POI]:
        """
        Rank POIs by distance, rating, and category priority.

        Ranking formula:
        - Distance weight: 50% (closer = better)
        - Category priority: 30% (practical needs ranked higher)
        - Rating weight: 20% (higher rating = better, if available)

        Args:
            pois: List of POIs to rank
            route_points: Optional route points for distance calculation

        Returns:
            Sorted list of POIs (best first)
        """
        if not pois:
            return []

        # Calculate distances if route points provided
        if route_points:
            pois = POIRankingService.calculate_poi_distances(pois, route_points)

        # Calculate score for each POI
        def calculate_score(poi: POI) -> float:
            """Calculate ranking score (higher = better)."""
            # Distance score (inverse - closer is better)
            # Normalize to 0-1 scale assuming max 25 miles from route
            distance_score = max(0, 1 - (poi.distance_from_route_miles / 25.0))

            # Category priority score (0-1 scale)
            category_priority = CATEGORY_PRIORITY_MAP.get(poi.category, 1)
            category_score = category_priority / 10.0  # Max priority is 10

            # Rating score (0-1 scale)
            rating_score = (poi.rating / 5.0) if poi.rating else 0.5

            # Weighted total
            total_score = (
                distance_score * 0.5 +
                category_score * 0.3 +
                rating_score * 0.2
            )

            return total_score

        # Sort by score (descending)
        ranked = sorted(pois, key=calculate_score, reverse=True)

        logger.info(f"Ranked {len(ranked)} POIs")
        return ranked

    @staticmethod
    def filter_duplicates(
        pois: List[POI],
        distance_threshold_miles: float = 0.1
    ) -> List[POI]:
        """
        Remove duplicate POIs that are very close to each other.

        Keeps the higher-ranked POI when duplicates are found.

        Args:
            pois: List of POIs (should be pre-ranked)
            distance_threshold_miles: Distance threshold for considering duplicates

        Returns:
            Filtered list with duplicates removed
        """
        if not pois:
            return []

        filtered = []
        for poi in pois:
            is_duplicate = False

            for existing in filtered:
                distance = calculate_distance_miles(
                    (poi.latitude, poi.longitude),
                    (existing.latitude, existing.longitude)
                )

                if distance < distance_threshold_miles:
                    is_duplicate = True
                    logger.debug(
                        f"Filtering duplicate: {poi.name} is {distance:.3f} mi "
                        f"from {existing.name}"
                    )
                    break

            if not is_duplicate:
                filtered.append(poi)

        logger.info(
            f"Filtered {len(pois) - len(filtered)} duplicates, "
            f"keeping {len(filtered)} POIs"
        )
        return filtered

    @staticmethod
    def distribute_along_route(
        pois: List[POI],
        route_points: List[Tuple[float, float]],
        max_pois: int = 20,
        min_spacing_miles: float = 10.0
    ) -> List[POI]:
        """
        Ensure POIs are distributed along the route, not clustered.

        Divides route into segments and selects best POI from each segment
        to ensure good distribution along the entire journey.

        Args:
            pois: List of ranked POIs
            route_points: List of (latitude, longitude) tuples forming the route
            max_pois: Maximum number of POIs to return
            min_spacing_miles: Minimum miles between selected POIs

        Returns:
            Distributed list of POIs along the route
        """
        if not pois or not route_points:
            return pois[:max_pois]

        # Calculate total route distance
        total_distance = 0.0
        for i in range(len(route_points) - 1):
            total_distance += calculate_distance_miles(
                route_points[i],
                route_points[i + 1]
            )

        logger.debug(f"Total route distance: {total_distance:.1f} miles")

        # If route is short, just return top POIs
        if total_distance < min_spacing_miles * 2:
            return pois[:max_pois]

        # Divide route into segments
        num_segments = min(max_pois, int(total_distance / min_spacing_miles))
        segment_distance = total_distance / num_segments

        # Assign each POI to a route segment
        poi_segments = {i: [] for i in range(num_segments)}

        for poi in pois:
            # Find closest point on route
            min_dist = float('inf')
            closest_segment = 0
            cumulative_distance = 0.0

            for i in range(len(route_points) - 1):
                segment_start = route_points[i]
                segment_end = route_points[i + 1]
                segment_length = calculate_distance_miles(segment_start, segment_end)

                # Check distance to this segment
                poi_point = (poi.latitude, poi.longitude)
                dist_to_start = calculate_distance_miles(poi_point, segment_start)
                dist_to_end = calculate_distance_miles(poi_point, segment_end)
                dist_to_segment = min(dist_to_start, dist_to_end)

                if dist_to_segment < min_dist:
                    min_dist = dist_to_segment
                    # Determine which distribution segment this belongs to
                    segment_idx = int(cumulative_distance / segment_distance)
                    closest_segment = min(segment_idx, num_segments - 1)

                cumulative_distance += segment_length

            poi_segments[closest_segment].append(poi)

        # Select best POI from each segment
        distributed = []
        for segment_idx in range(num_segments):
            segment_pois = poi_segments[segment_idx]
            if segment_pois:
                # Take the top-ranked POI from this segment
                distributed.append(segment_pois[0])

        logger.info(
            f"Distributed {len(distributed)} POIs across {num_segments} "
            f"route segments"
        )
        return distributed[:max_pois]

    @staticmethod
    def filter_and_rank(
        pois: List[POI],
        route_points: List[Tuple[float, float]],
        max_results: int = 15,
        distribute: bool = True
    ) -> List[POI]:
        """
        Complete filtering and ranking pipeline.

        Applies all ranking and filtering steps in order:
        1. Calculate distances to route
        2. Rank by distance + category + rating
        3. Filter duplicates
        4. Distribute along route (optional)
        5. Limit to max results

        Args:
            pois: Raw list of POIs from search
            route_points: Route coordinates
            max_results: Maximum POIs to return
            distribute: Whether to enforce distribution along route

        Returns:
            Filtered, ranked, and distributed list of POIs
        """
        logger.info(f"Starting filter and rank pipeline with {len(pois)} POIs")

        # Step 1 & 2: Rank (includes distance calculation)
        ranked = POIRankingService.rank_pois(pois, route_points)

        # Step 3: Filter duplicates
        filtered = POIRankingService.filter_duplicates(ranked)

        # Step 4: Distribute along route
        if distribute and len(filtered) > max_results:
            final = POIRankingService.distribute_along_route(
                filtered,
                route_points,
                max_results
            )
        else:
            final = filtered[:max_results]

        logger.info(f"Filter and rank pipeline complete: {len(final)} POIs selected")
        return final
