"""
Polyline utilities for route corridor extraction
Ported from PolylineUtils.kt (commit 9b95a3a)
"""

import math
from enum import Enum
from typing import List, Tuple
from shapely.geometry import Point, LineString, Polygon
from shapely.ops import unary_union


class TripScale(str, Enum):
    """Coarse trip classification used by the recommendation engine.

    Thresholds per `docs/recommendations-brief.md` → "Trip scale":
        local    : <20 mi
        regional : 20–100 mi
        long     : 100+ mi

    Detection is route-distance based (the sum of segment lengths along
    the polyline) — NOT straight-line origin-to-destination. A winding
    coastal route can be a `long` trip even between cities that look
    close as the crow flies.
    """
    LOCAL = "local"
    REGIONAL = "regional"
    LONG = "long"


def decode_polyline(polyline: str, precision: int = 6) -> List[Tuple[float, float]]:
    """
    Decode Google-encoded polyline into list of (lat, lng) coordinates.

    Uses Google's polyline encoding algorithm.
    Mapbox Navigation SDK uses precision 6 for route geometry (NOT precision 5).

    Args:
        polyline: Encoded polyline string
        precision: Precision factor (6 for Mapbox Navigation SDK, 5 for Google Maps)

    Returns:
        List of (latitude, longitude) tuples

    Example:
        >>> decode_polyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@", precision=5)
        [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]
    """
    coordinates = []
    index = 0
    lat = 0
    lng = 0
    factor = 10 ** precision

    while index < len(polyline):
        # Decode latitude
        result = 0
        shift = 0
        while True:
            if index >= len(polyline):
                return coordinates  # truncated polyline — return what we have
            byte = ord(polyline[index]) - 63
            index += 1
            result |= (byte & 0x1F) << shift
            shift += 5
            if byte < 0x20:
                break

        d_lat = ~(result >> 1) if (result & 1) else (result >> 1)
        lat += d_lat

        # Decode longitude
        result = 0
        shift = 0
        while True:
            if index >= len(polyline):
                return coordinates  # truncated polyline — return what we have
            byte = ord(polyline[index]) - 63
            index += 1
            result |= (byte & 0x1F) << shift
            shift += 5
            if byte < 0x20:
                break

        d_lng = ~(result >> 1) if (result & 1) else (result >> 1)
        lng += d_lng

        coordinates.append((lat / factor, lng / factor))

    return coordinates


def create_corridor_buffer(
    points: List[Tuple[float, float]],
    radius_miles: float
) -> Polygon:
    """
    Create a buffered polygon corridor around route points.

    Creates circular buffers around each route point and merges them into
    a single polygon representing the route corridor for POI search.

    Args:
        points: List of (latitude, longitude) tuples
        radius_miles: Buffer radius in miles

    Returns:
        Shapely Polygon representing the route corridor

    Note:
        Uses approximate degree-to-miles conversion. More accurate for
        mid-latitudes (US). For precise geographic operations, use
        proper coordinate transformations.
    """
    if not points:
        raise ValueError("Cannot create corridor from empty points list")

    # Convert miles to approximate degrees
    # At mid-latitudes: 1 degree lat ≈ 69 miles, 1 degree lng ≈ 54 miles
    # Using conservative average for buffer
    radius_degrees = radius_miles / 60.0

    # Create buffer around each point
    buffers = []
    for lat, lng in points:
        point = Point(lng, lat)  # Shapely uses (x, y) = (lng, lat)
        buffer = point.buffer(radius_degrees)
        buffers.append(buffer)

    # Merge all buffers into single polygon
    corridor = unary_union(buffers)

    return corridor


def calculate_distance_miles(
    point1: Tuple[float, float],
    point2: Tuple[float, float]
) -> float:
    """
    Calculate great-circle distance between two points using Haversine formula.

    Args:
        point1: (latitude, longitude) of first point
        point2: (latitude, longitude) of second point

    Returns:
        Distance in miles

    Example:
        >>> calculate_distance_miles((37.7749, -122.4194), (34.0522, -118.2437))
        347.32  # San Francisco to Los Angeles
    """
    lat1, lon1 = point1
    lat2, lon2 = point2

    # Earth's radius in miles
    R = 3958.8

    # Convert to radians
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)

    # Haversine formula
    a = (
        math.sin(delta_lat / 2) ** 2 +
        math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    distance = R * c

    return distance


def calculate_bounds(points: List[Tuple[float, float]]) -> List[float]:
    """
    Calculate bounding box for a list of points.

    Args:
        points: List of (latitude, longitude) tuples

    Returns:
        Bounding box as [minLng, minLat, maxLng, maxLat]

    Example:
        >>> calculate_bounds([(37.7, -122.4), (37.8, -122.3)])
        [-122.4, 37.7, -122.3, 37.8]
    """
    if not points:
        raise ValueError("Cannot calculate bounds from empty points list")

    lats = [p[0] for p in points]
    lngs = [p[1] for p in points]

    return [min(lngs), min(lats), max(lngs), max(lats)]


def simplify_route_points(
    points: List[Tuple[float, float]],
    max_points: int = 100
) -> List[Tuple[float, float]]:
    """
    Simplify route by sampling evenly-spaced points.

    For very long routes with many points, this reduces computational
    cost while maintaining route shape for corridor extraction.

    Args:
        points: List of (latitude, longitude) tuples
        max_points: Maximum number of points to keep

    Returns:
        Simplified list of points
    """
    if len(points) <= max_points:
        return points

    # Calculate step size to sample evenly
    step = len(points) / max_points

    simplified = []
    for i in range(max_points):
        index = int(i * step)
        simplified.append(points[index])

    # Always include last point
    if simplified[-1] != points[-1]:
        simplified.append(points[-1])

    return simplified


def point_to_line_distance(
    point: Tuple[float, float],
    route_points: List[Tuple[float, float]]
) -> float:
    """
    Calculate minimum distance from a point to a route (line).

    Args:
        point: (latitude, longitude) of the point
        route_points: List of (latitude, longitude) tuples forming the route

    Returns:
        Minimum distance in miles from point to nearest segment of route
    """
    if not route_points:
        raise ValueError("Route points cannot be empty")

    if len(route_points) == 1:
        return calculate_distance_miles(point, route_points[0])

    # Create LineString from route points
    # Shapely uses (x, y) = (lng, lat)
    line = LineString([(p[1], p[0]) for p in route_points])
    point_geom = Point(point[1], point[0])

    # Get nearest point on line
    nearest = line.interpolate(line.project(point_geom))

    # Calculate distance (result in degrees, convert to miles)
    distance_degrees = point_geom.distance(nearest)
    distance_miles = distance_degrees * 60.0  # Approximate conversion

    return distance_miles


def route_length_miles(route_points: List[Tuple[float, float]]) -> float:
    """Sum of haversine distances between consecutive route points.

    Empty / single-point routes return 0.0. Used to classify trip
    scale and to detect when a multi-day plan needs an overnight
    break.
    """
    if len(route_points) < 2:
        return 0.0
    total = 0.0
    for i in range(len(route_points) - 1):
        total += calculate_distance_miles(route_points[i], route_points[i + 1])
    return total


def detect_trip_scale(route_points: List[Tuple[float, float]]) -> TripScale:
    """Classify a route as local / regional / long.

    Uses route-distance, not straight-line — see TripScale docstring
    for the brief reference. A 25-mile commute with curves still
    classifies as `regional` even if origin and destination are 12
    miles apart as the crow flies.
    """
    miles = route_length_miles(route_points)
    if miles < 20:
        return TripScale.LOCAL
    if miles < 100:
        return TripScale.REGIONAL
    return TripScale.LONG
