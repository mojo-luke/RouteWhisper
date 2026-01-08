# Mapbox Directions API

## Overview
The Mapbox Directions API enables route calculation with turn-by-turn instructions across multiple transportation modes. Supports up to 25 waypoints and provides traffic-aware routing with comprehensive navigation data.

## Endpoint
```
GET https://api.mapbox.com/directions/v5/{profile}/{coordinates}
```

## Core Routing Profiles

- **mapbox/driving-traffic**: Automotive routing factoring current and historic traffic conditions
- **mapbox/driving**: Fastest automotive routes preferring highways
- **mapbox/walking**: Pedestrian/hiking routes using sidewalks and trails
- **mapbox/cycling**: Bicycle routes avoiding highways, preferring bike lanes

## Required Parameters

- `profile`: Routing mode (see profiles above)
- `coordinates`: Semicolon-separated lon,lat pairs (2-25 waypoints)
  - Format: `{longitude},{latitude};{longitude},{latitude};...`
- `access_token`: Your Mapbox public access token

## Key Optional Parameters

### Navigation Options
- `steps` (boolean): Enable turn-by-turn instructions
- `alternatives` (boolean): Request up to 2 alternative routes
- `overview` (full/simplified/false): Geometry detail level
- `geometries` (geojson/polyline/polyline6): Output format

### Guidance Output
- `voice_instructions` (boolean): SSML-marked speech guidance
- `banner_instructions` (boolean): Visual guidance objects
- `language` (string): Instruction language (default: en)
- `roundabout_exits` (boolean): Separate roundabout entry/exit instructions

### Route Constraints
- `exclude` (string): Avoid motorways, tolls, ferries, unpaved roads
- `approaches` (string): Curb-side arrival specification per waypoint
- `radiuses` (string): Snapping tolerance per waypoint (meters)
- `bearings` (string): Direction constraints at waypoints

### Vehicle Specifications (driving profile)
- `max_height/width/weight` (number): Vehicle dimension restrictions
- `arrive_by/depart_at` (ISO 8601): Time-based routing with traffic prediction

## Example Request

```http
GET https://api.mapbox.com/directions/v5/mapbox/driving-traffic/-122.4194,37.7749;-118.2437,34.0522?steps=true&alternatives=true&geometries=geojson&access_token=YOUR_TOKEN
```

This requests driving directions from San Francisco to Los Angeles with:
- Turn-by-turn steps
- Alternative routes
- GeoJSON geometry format

## Response Structure

```json
{
  "code": "Ok",
  "routes": [
    {
      "geometry": {...},
      "distance": 830.4,
      "duration": 88.4,
      "legs": [...],
      "waypoints": [...]
    }
  ],
  "waypoints": [...]
}
```

### Route Object Fields
- `distance`: Total distance in meters
- `duration`: Total travel time in seconds
- `legs`: Array of route segments between waypoints
- `geometry`: Encoded route path (format depends on `geometries` parameter)

### Leg Object Fields
- `steps`: Array of individual turn instructions
- `summary`: Major roads traversed
- `annotations`: Speed, congestion, duration per segment
- `incidents`: Traffic events (driving-traffic profile only)

### Step Object Fields
- `maneuver`: Turn instructions with bearing angles
- `name`: Street name
- `intersections`: Detailed crossing information
- `voiceInstructions`: Spoken guidance cues
- `bannerInstructions`: Visual turn information
- `distance`: Distance to next step (meters)
- `duration`: Time to next step (seconds)

## Electric Vehicle (EV) Routing

EV routing automatically identifies charging stops with battery predictions.

### Required EV Parameters
- `engine=electric`: Enable EV routing
- `ev_max_charge`: Battery capacity (Wh)
- `ev_connector_types`: Compatible charger types (comma-separated)
- `energy_consumption_curve`: Power consumption rates
- `ev_charging_curve`: Charging speed vs. state-of-charge

### Optional EV Parameters
- `ev_initial_charge`: Starting battery level (Wh)
- `ev_min_charge_at_destination`: Required final charge (Wh)
- `ev_add_charging_stops` (boolean): Auto-insert stations (default: true)
- `ev_prefer_amenities`: Soft preferences for facilities at charging stops

### EV Response
Charging stops appear as waypoints with metadata:
- Charge time required
- Connector type
- Power availability
- Amenities

**Note**: EV routing supports 12 waypoints maximum when auto-adding stops; 25 when manually specified.

## POST Requests

For large requests exceeding ~8100 bytes, use HTTP POST with URL-encoded body parameters instead of GET query strings.

```http
POST https://api.mapbox.com/directions/v5/{profile}/{coordinates}
Content-Type: application/x-www-form-urlencoded

steps=true&alternatives=true&access_token=YOUR_TOKEN
```

## Notable Response Features

### Traffic Annotations
Congestion levels:
- Numeric: 0-100
- String: low/moderate/heavy/severe

### Speed Limits
`maxspeed` annotation with local unit (km/h or mph)

### Lane Guidance
Available turn lanes with:
- `active`: Lanes you should be in
- `valid`: Legal lanes for the maneuver

### Admin Boundaries
ISO country/region codes per intersection

### Rest Stops & Tolls
POI information at intersections

### Time Zones
IANA timezone identifiers for waypoints

## Usage in Android

```kotlin
import com.mapbox.api.directions.v5.DirectionsCriteria
import com.mapbox.api.directions.v5.MapboxDirections
import com.mapbox.geojson.Point

val origin = Point.fromLngLat(-122.4194, 37.7749)
val destination = Point.fromLngLat(-118.2437, 34.0522)

val directions = MapboxDirections.builder()
    .accessToken(YOUR_TOKEN)
    .profile(DirectionsCriteria.PROFILE_DRIVING_TRAFFIC)
    .origin(origin)
    .destination(destination)
    .steps(true)
    .alternatives(true)
    .voiceInstructions(true)
    .bannerInstructions(true)
    .build()

directions.enqueueCall(object : Callback<DirectionsResponse> {
    override fun onResponse(
        call: Call<DirectionsResponse>,
        response: Response<DirectionsResponse>
    ) {
        val routes = response.body()?.routes()
        // Use routes for navigation
    }

    override fun onFailure(call: Call<DirectionsResponse>, t: Throwable) {
        // Handle error
    }
})
```

## Pricing & Limits

- Direction requests counted individually
- Alternative route requests cost extra
- Annotations and voice instructions included in standard pricing
- Specific rate limits apply to account tier

## Documentation
Full API Reference: https://docs.mapbox.com/api/navigation/directions/
