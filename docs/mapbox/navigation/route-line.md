# Route Line Component

## Overview
The Route Line component renders navigation routes on the map with support for alternative routes, traffic congestion visualization, and dynamic styling.

## Core Components

The route line system comprises two main classes:

1. **MapboxRouteLineApi** - Manages creation and modification of route lines, produces view-related data mutations
2. **MapboxRouteLineView** - Consumes API data and renders results on the map

**Default appearance**: Routes display as solid blue lines with darker blue outlines.

## Basic Implementation

### Step 1: Initialize Components

```kotlin
import com.mapbox.navigation.ui.maps.route.line.api.MapboxRouteLineApi
import com.mapbox.navigation.ui.maps.route.line.api.MapboxRouteLineApiOptions
import com.mapbox.navigation.ui.maps.route.line.view.MapboxRouteLineView
import com.mapbox.navigation.ui.maps.route.line.view.MapboxRouteLineViewOptions

val routeLineApi = MapboxRouteLineApi(
    MapboxRouteLineApiOptions.Builder().build()
)

val routeLineView = MapboxRouteLineView(
    MapboxRouteLineViewOptions.Builder(context).build()
)
```

### Step 2: Register Routes Observer

```kotlin
val routesObserver = RoutesObserver { routeUpdateResult ->
    val navigationRoutes = routeUpdateResult.navigationRoutes

    // Get alternative route metadata for enhanced visualization
    val alternativesMetadata = mapboxNavigation.getAlternativeMetadataFor(navigationRoutes)

    // Update route line
    routeLineApi.setNavigationRoutes(navigationRoutes, alternativesMetadata) { value ->
        routeLineView.renderRouteDrawData(mapStyle, value)
    }
}

mapboxNavigation.registerRoutesObserver(routesObserver)
```

### Step 3: Handle Route Progress (Optional)

Update route line as navigation progresses:

```kotlin
val routeProgressObserver = RouteProgressObserver { routeProgress ->
    routeLineApi.updateWithRouteProgress(routeProgress) { result ->
        routeLineView.renderRouteLineUpdate(mapStyle, result)
    }
}

mapboxNavigation.registerRouteProgressObserver(routeProgressObserver)
```

## Traffic Congestion Display

### Enable Traffic on Routes

Request routes with traffic data:

```kotlin
import com.mapbox.api.directions.v5.DirectionsCriteria

val directions = MapboxDirections.builder()
    .profile(DirectionsCriteria.PROFILE_DRIVING_TRAFFIC) // Use traffic profile
    .origin(origin)
    .destination(destination)
    .annotationsList(
        listOf(
            DirectionsCriteria.ANNOTATION_CONGESTION_NUMERIC,
            DirectionsCriteria.ANNOTATION_DISTANCE
        )
    )
    .build()
```

**Required annotations**:
- `ANNOTATION_CONGESTION_NUMERIC` - Numeric congestion values (0-100)
- `ANNOTATION_DISTANCE` - Distance per segment for accurate rendering

### Traffic Color Coding

Default traffic colors:
- **Green/Low**: Free-flowing traffic
- **Yellow/Moderate**: Moderate congestion
- **Orange/Heavy**: Heavy traffic
- **Red/Severe**: Severe congestion

## Key Features

### 1. Vanishing Route Line

Make traveled route sections transparent or differently colored:

```kotlin
val options = MapboxRouteLineApiOptions.Builder()
    .vanishingRouteLineEnabled(true)
    .build()

val routeLineApi = MapboxRouteLineApi(options)
```

**Effect**: As you travel, the route line behind you fades or changes color, making it clear which portion is remaining.

### 2. Layer Positioning

Position route lines beneath specific map layers:

```kotlin
val options = MapboxRouteLineViewOptions.Builder(context)
    .routeLineBelowLayerId("road-label") // Route below road labels
    .build()

val routeLineView = MapboxRouteLineView(options)
```

**Common layer IDs**:
- `"road-label"` - Route below road labels (default for navigation)
- `"building"` - Route below buildings
- `null` - Route on top of everything

### 3. Color Customization

Customize route colors:

```kotlin
import com.mapbox.navigation.ui.maps.route.line.model.RouteLineColorResources

val colorResources = RouteLineColorResources.Builder()
    .routeDefaultColor(Color.BLUE)
    .routeCasingColor(Color.parseColor("#1E3A8A"))
    .routeModerateColor(Color.YELLOW) // Moderate traffic
    .routeHeavyColor(Color.parseColor("#FF6B00")) // Heavy traffic
    .routeSevereColor(Color.RED) // Severe traffic
    .alternativeRouteDefaultColor(Color.GRAY)
    .alternativeRouteCasingColor(Color.DKGRAY)
    .inactiveRouteLegColor(Color.LTGRAY)
    .restrictedRoadColor(Color.parseColor("#FF0000"))
    .build()

val options = MapboxRouteLineApiOptions.Builder()
    .routeLineColorResources(colorResources)
    .build()
```

### 4. Inactive Route Legs

For multi-waypoint routes, style inactive legs differently:

```kotlin
val options = MapboxRouteLineApiOptions.Builder()
    .styleInactiveRouteLegsIndependently(true)
    .build()
```

**Effect**: Legs you haven't reached yet appear in a different color (e.g., gray) compared to the active leg.

### 5. Restricted Road Sections

Show restricted roads with dashed lines:

```kotlin
val options = MapboxRouteLineApiOptions.Builder()
    .displayRestrictedRoadSections(true)
    .build()
```

**Effect**: Sections with restrictions (e.g., private roads, tolls) appear with dashed lines instead of solid.

### 6. Soft Traffic Gradients

Smooth color transitions between traffic congestion levels:

```kotlin
val options = MapboxRouteLineApiOptions.Builder()
    .displaySoftGradientForTraffic(true)
    .softGradientTransition(30.0) // Transition distance in map units (5.0-75.0)
    .build()
```

**Effect**: Instead of abrupt color changes, traffic colors blend smoothly.

## Alternative Routes

### Displaying Alternatives

Alternative routes are automatically styled when provided:

```kotlin
// Request alternatives in Directions API
val directions = MapboxDirections.builder()
    .alternatives(true) // Request up to 2 alternatives
    .build()

// They'll automatically render with alternative styling
routeLineApi.setNavigationRoutes(navigationRoutes, alternativesMetadata) { value ->
    routeLineView.renderRouteDrawData(mapStyle, value)
}
```

**Default alternative styling**:
- Lighter color (gray by default)
- Thinner line width
- Lower z-order (behind primary route)

### Selecting Alternative Route

```kotlin
// User clicks alternative route
mapView.mapboxMap.addOnMapClickListener { point ->
    routeLineApi.findClosestRoute(point, mapboxMap, { expectedResult ->
        expectedResult.onValue { closestRoute ->
            // Set selected route as primary
            val reorderedRoutes = navigationRoutes.toMutableList()
            reorderedRoutes.remove(closestRoute)
            reorderedRoutes.add(0, closestRoute)

            mapboxNavigation.setNavigationRoutes(reorderedRoutes)
        }
    })
    true
}
```

## Runtime Updates

### Dynamic Styling

Update styling without recreating components:

```kotlin
import com.mapbox.navigation.ui.maps.route.line.model.MapboxRouteLineViewDynamicOptionsBuilder

val dynamicOptions = MapboxRouteLineViewDynamicOptionsBuilder()
    .routeLineBelowLayerId("new-layer-id")
    .build()

routeLineView.updateDynamicOptions(mapStyle, dynamicOptions)

// Re-render route with new options
routeLineApi.getRouteDrawData { value ->
    routeLineView.renderRouteDrawData(mapStyle, value)
}
```

### Updating Route Progress

As navigation progresses, update the route line:

```kotlin
val routeProgressObserver = RouteProgressObserver { routeProgress ->
    routeLineApi.updateWithRouteProgress(routeProgress) { result ->
        routeLineView.renderRouteLineUpdate(mapStyle, result)
    }
}

mapboxNavigation.registerRouteProgressObserver(routeProgressObserver)
```

**What this does**:
- Updates vanishing route line
- Highlights active leg
- Dims completed sections
- Shows current position accurately

## Complete Example

```kotlin
class NavigationActivity : AppCompatActivity() {

    private lateinit var mapboxNavigation: MapboxNavigation
    private lateinit var routeLineApi: MapboxRouteLineApi
    private lateinit var routeLineView: MapboxRouteLineView
    private lateinit var mapStyle: Style

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_navigation)

        val mapView = findViewById<MapView>(R.id.mapView)
        mapView.mapboxMap.loadStyle(Style.MAPBOX_STREETS) { style ->
            this.mapStyle = style
            initializeRouteLineComponents()
        }
    }

    private fun initializeRouteLineComponents() {
        // Configure route line API
        val apiOptions = MapboxRouteLineApiOptions.Builder()
            .vanishingRouteLineEnabled(true)
            .styleInactiveRouteLegsIndependently(true)
            .displayRestrictedRoadSections(true)
            .displaySoftGradientForTraffic(true)
            .softGradientTransition(30.0)
            .build()

        routeLineApi = MapboxRouteLineApi(apiOptions)

        // Configure route line view
        val viewOptions = MapboxRouteLineViewOptions.Builder(this)
            .routeLineBelowLayerId("road-label")
            .build()

        routeLineView = MapboxRouteLineView(viewOptions)

        // Register observers
        registerRouteLineObservers()
    }

    private fun registerRouteLineObservers() {
        // Routes observer
        val routesObserver = RoutesObserver { routeUpdateResult ->
            val navigationRoutes = routeUpdateResult.navigationRoutes

            if (navigationRoutes.isNotEmpty()) {
                val alternativesMetadata =
                    mapboxNavigation.getAlternativeMetadataFor(navigationRoutes)

                routeLineApi.setNavigationRoutes(
                    navigationRoutes,
                    alternativesMetadata
                ) { value ->
                    routeLineView.renderRouteDrawData(mapStyle, value)
                }
            } else {
                // Clear route line when no routes
                routeLineApi.clearRouteLine { value ->
                    routeLineView.renderRouteClearData(mapStyle, value)
                }
            }
        }

        mapboxNavigation.registerRoutesObserver(routesObserver)

        // Route progress observer
        val routeProgressObserver = RouteProgressObserver { routeProgress ->
            routeLineApi.updateWithRouteProgress(routeProgress) { result ->
                routeLineView.renderRouteLineUpdate(mapStyle, result)
            }
        }

        mapboxNavigation.registerRouteProgressObserver(routeProgressObserver)
    }

    private fun requestRoute(origin: Point, destination: Point) {
        val directions = MapboxDirections.builder()
            .accessToken(getString(R.string.mapbox_access_token))
            .profile(DirectionsCriteria.PROFILE_DRIVING_TRAFFIC)
            .origin(origin)
            .destination(destination)
            .alternatives(true)
            .annotationsList(
                listOf(
                    DirectionsCriteria.ANNOTATION_CONGESTION_NUMERIC,
                    DirectionsCriteria.ANNOTATION_DISTANCE
                )
            )
            .steps(true)
            .build()

        directions.enqueueCall(object : Callback<DirectionsResponse> {
            override fun onResponse(
                call: Call<DirectionsResponse>,
                response: Response<DirectionsResponse>
            ) {
                val routes = response.body()?.routes()
                if (routes != null && routes.isNotEmpty()) {
                    val navigationRoutes = routes.map { it.toNavigationRoute() }
                    mapboxNavigation.setNavigationRoutes(navigationRoutes)
                }
            }

            override fun onFailure(call: Call<DirectionsResponse>, t: Throwable) {
                Log.e("RouteRequest", "Failed to get route", t)
            }
        })
    }
}
```

## Best Practices

1. **Always request traffic annotations** when using PROFILE_DRIVING_TRAFFIC
2. **Enable vanishing route line** for better UX during navigation
3. **Position route below labels** for better readability
4. **Use soft gradients** for smoother traffic visualization
5. **Handle alternative routes** with click detection for user selection
6. **Clear route line** when navigation ends
7. **Unregister observers** in onDestroy() to prevent memory leaks

## Common Issues

### Route line not visible
- Check route line layer is below labels
- Verify style is loaded before rendering
- Ensure routes are set to MapboxNavigation

### Traffic colors not showing
- Request routes with PROFILE_DRIVING_TRAFFIC
- Include ANNOTATION_CONGESTION_NUMERIC
- Include ANNOTATION_DISTANCE

### Alternative routes not displaying
- Request alternatives in Directions API (`.alternatives(true)`)
- Ensure alternatives metadata is passed to setNavigationRoutes

### Vanishing route not working
- Enable in MapboxRouteLineApiOptions
- Register RouteProgressObserver
- Call updateWithRouteProgress

## Related Documentation
- [Navigation Camera](navigation-camera.md) - Camera controls for following routes
- [Directions API](../apis/directions-api.md) - Requesting routes with traffic
- [UI Components Overview](ui-components.md) - All UI components

## External Resources
- Route Line Guide: https://docs.mapbox.com/android/navigation/guides/ui-components/route-line/
- Route Line API Reference: https://docs.mapbox.com/android/navigation/api/
