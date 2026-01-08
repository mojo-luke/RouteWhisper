# Building Highlights at Destination

## Overview
Building Highlights automatically extrudes the destination building in 3D on the map, making it easier for users to identify their final destination visually.

## What It Does

- **Highlights destination building** - Extrudes building in 3D
- **Distinctive styling** - Different color from other buildings
- **Automatic detection** - Finds building at destination coordinates
- **Waypoint support** - Highlights buildings at intermediate stops

## Basic Implementation

### Step 1: Enable Building Layer

Ensure your map style includes buildings:

```kotlin
mapView.mapboxMap.loadStyle(Style.MAPBOX_STREETS) { style ->
    // Building layer already included in standard styles
    enableBuildingHighlights(style)
}
```

### Step 2: Configure Building Highlights

```kotlin
import com.mapbox.navigation.ui.maps.building.api.MapboxBuildingsApi
import com.mapbox.navigation.ui.maps.building.view.MapboxBuildingView

class NavigationActivity : AppCompatActivity() {

    private lateinit var buildingsApi: MapboxBuildingsApi
    private lateinit var buildingView: MapboxBuildingView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        mapView.mapboxMap.loadStyle(Style.MAPBOX_STREETS) { style ->
            initializeBuildingHighlights(style)
        }
    }

    private fun initializeBuildingHighlights(style: Style) {
        buildingsApi = MapboxBuildingsApi()
        buildingView = MapboxBuildingView()
    }
}
```

### Step 3: Highlight Building on Arrival

```kotlin
import com.mapbox.navigation.core.arrival.ArrivalObserver

val arrivalObserver = object : ArrivalObserver {
    override fun onWaypointArrival(routeProgress: RouteProgress) {
        // Highlight waypoint building
        highlightDestinationBuilding(routeProgress)
    }

    override fun onFinalDestinationArrival(routeProgress: RouteProgress) {
        // Highlight final destination building
        highlightDestinationBuilding(routeProgress)
    }

    override fun onNextRouteLegStart(routeLegProgress: RouteLegProgress) {
        // Clear previous building highlight
        clearBuildingHighlight()
    }
}

mapboxNavigation.registerArrivalObserver(arrivalObserver)
```

### Step 4: Implement Highlight Logic

```kotlin
import com.mapbox.navigation.ui.maps.building.model.MapboxBuildingHighlightOptions

private fun highlightDestinationBuilding(routeProgress: RouteProgress) {
    val destination = routeProgress.currentLegProgress?.routeLeg?.destination()
    val destinationPoint = destination?.location() ?: return

    // Query buildings at destination
    buildingsApi.queryBuilding(destinationPoint) { expected ->
        expected.fold(
            { buildingValue ->
                // Highlight the building
                val options = MapboxBuildingHighlightOptions.Builder()
                    .fillExtrusionColor(Color.parseColor("#FFA500")) // Orange
                    .fillExtrusionOpacity(0.8)
                    .build()

                buildingView.highlightBuilding(
                    mapStyle,
                    buildingValue,
                    options
                )
            },
            { error ->
                Log.e("Building", "No building found at destination: $error")
            }
        )
    }
}

private fun clearBuildingHighlight() {
    buildingView.clear(mapStyle)
}
```

## Customization

### Highlight Colors

```kotlin
val highlightOptions = MapboxBuildingHighlightOptions.Builder()
    .fillExtrusionColor(Color.parseColor("#00FF00")) // Green
    .fillExtrusionOpacity(0.9) // More opaque
    .fillExtrusionHeight(100.0) // Custom height
    .build()
```

### Common Color Schemes

```kotlin
// Destination (final)
val finalDestinationColor = Color.parseColor("#FF5722") // Red-orange

// Waypoint (intermediate)
val waypointColor = Color.parseColor("#2196F3") // Blue

// Charging station
val chargingStationColor = Color.parseColor("#4CAF50") // Green
```

## Multi-Waypoint Routes

Highlight different buildings at each stop:

```kotlin
private val arrivalObserver = object : ArrivalObserver {
    override fun onWaypointArrival(routeProgress: RouteProgress) {
        // Waypoint - use blue
        highlightBuilding(
            routeProgress,
            Color.parseColor("#2196F3"),
            isWaypoint = true
        )
    }

    override fun onFinalDestinationArrival(routeProgress: RouteProgress) {
        // Final destination - use orange
        highlightBuilding(
            routeProgress,
            Color.parseColor("#FFA500"),
            isWaypoint = false
        )
    }

    override fun onNextRouteLegStart(routeLegProgress: RouteLegProgress) {
        // Clear previous highlight when leaving waypoint
        clearBuildingHighlight()
    }
}

private fun highlightBuilding(
    routeProgress: RouteProgress,
    color: Int,
    isWaypoint: Boolean
) {
    val destination = routeProgress.currentLegProgress?.routeLeg?.destination()
    val point = destination?.location() ?: return

    buildingsApi.queryBuilding(point) { expected ->
        expected.fold(
            { buildingValue ->
                val options = MapboxBuildingHighlightOptions.Builder()
                    .fillExtrusionColor(color)
                    .fillExtrusionOpacity(if (isWaypoint) 0.7 else 0.9)
                    .build()

                buildingView.highlightBuilding(mapStyle, buildingValue, options)

                if (!isWaypoint) {
                    // Final destination - also add marker
                    addDestinationMarker(point)
                }
            },
            { error ->
                Log.w("Building", "No building at ${if (isWaypoint) "waypoint" else "destination"}")
            }
        )
    }
}
```

## Arrival Detection

Building highlights work best with arrival detection:

```kotlin
import com.mapbox.navigation.base.options.ArrivalOptions

val arrivalOptions = ArrivalOptions.Builder()
    .arrivalDistanceThreshold(50.0) // 50 meters
    .build()

val navigationOptions = NavigationOptions.Builder(context)
    .accessToken(YOUR_TOKEN)
    .arrivalOptions(arrivalOptions)
    .build()
```

## Complete Example

```kotlin
class NavigationActivity : AppCompatActivity() {

    private lateinit var mapboxNavigation: MapboxNavigation
    private lateinit var buildingsApi: MapboxBuildingsApi
    private lateinit var buildingView: MapboxBuildingView
    private lateinit var mapStyle: Style

    private val arrivalObserver = object : ArrivalObserver {
        override fun onWaypointArrival(routeProgress: RouteProgress) {
            highlightWaypointBuilding(routeProgress)
        }

        override fun onFinalDestinationArrival(routeProgress: RouteProgress) {
            highlightFinalDestinationBuilding(routeProgress)
            showArrivalMessage()
        }

        override fun onNextRouteLegStart(routeLegProgress: RouteLegProgress) {
            clearBuildingHighlight()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_navigation)

        mapView.mapboxMap.loadStyle(Style.MAPBOX_STREETS) { style ->
            this.mapStyle = style
            initializeBuildingHighlights()
        }

        mapboxNavigation.registerArrivalObserver(arrivalObserver)
    }

    private fun initializeBuildingHighlights() {
        buildingsApi = MapboxBuildingsApi()
        buildingView = MapboxBuildingView()
    }

    private fun highlightWaypointBuilding(routeProgress: RouteProgress) {
        val destination = routeProgress.currentLegProgress?.routeLeg?.destination()
        val point = destination?.location() ?: return

        buildingsApi.queryBuilding(point) { expected ->
            expected.fold(
                { buildingValue ->
                    val options = MapboxBuildingHighlightOptions.Builder()
                        .fillExtrusionColor(Color.parseColor("#2196F3")) // Blue for waypoint
                        .fillExtrusionOpacity(0.7)
                        .build()

                    buildingView.highlightBuilding(mapStyle, buildingValue, options)
                },
                { error ->
                    Log.w("Building", "No building at waypoint")
                }
            )
        }
    }

    private fun highlightFinalDestinationBuilding(routeProgress: RouteProgress) {
        val destination = routeProgress.currentLegProgress?.routeLeg?.destination()
        val point = destination?.location() ?: return

        buildingsApi.queryBuilding(point) { expected ->
            expected.fold(
                { buildingValue ->
                    val options = MapboxBuildingHighlightOptions.Builder()
                        .fillExtrusionColor(Color.parseColor("#FFA500")) // Orange for final destination
                        .fillExtrusionOpacity(0.9)
                        .build()

                    buildingView.highlightBuilding(mapStyle, buildingValue, options)
                },
                { error ->
                    Log.w("Building", "No building at destination")
                }
            )
        }
    }

    private fun clearBuildingHighlight() {
        buildingView.clear(mapStyle)
    }

    private fun showArrivalMessage() {
        Toast.makeText(this, "You have arrived!", Toast.LENGTH_SHORT).show()
    }

    override fun onDestroy() {
        super.onDestroy()
        mapboxNavigation.unregisterArrivalObserver(arrivalObserver)
        clearBuildingHighlight()
    }
}
```

## Best Practices

1. **Clear highlights** when leaving waypoints
2. **Use distinct colors** for waypoints vs final destination
3. **Handle missing buildings** - Not all destinations have building data
4. **Combine with markers** for non-building destinations
5. **Test camera angle** - Ensure 3D buildings are visible
6. **Set appropriate pitch** - 45-60 degrees for 3D effect

## Common Issues

### Building not highlighting
- Check destination is actually at a building
- Verify map style includes building layer
- Ensure 3D buildings are enabled in style

### Building wrong color
- Check highlight options configuration
- Verify style hasn't been overridden

### Buildings not visible
- Camera pitch too low (use 45-60 degrees)
- Zoom level too far out
- Building layer disabled in style

## Related Documentation
- [Navigation Camera](navigation-camera.md) - Camera positioning for 3D buildings
- [Arrival Detection](ui-components.md) - Detecting destination arrival
- [Waypoints](waypoints.md) - Multi-stop navigation

## External Resources
- Building Highlights Guide: https://docs.mapbox.com/android/navigation/guides/ui-components/building-highlight/
- Navigation SDK Examples: https://github.com/mapbox/mapbox-navigation-android-examples
