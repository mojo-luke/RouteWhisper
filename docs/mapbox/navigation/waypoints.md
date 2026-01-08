# Multi-Waypoint Navigation

## Overview
Waypoints allow navigation through multiple stops before reaching the final destination. The Navigation SDK supports routes with up to 25 waypoints (or 12 for EV routing).

## Use Cases

- **Delivery routes** - Multiple delivery stops
- **Tour routes** - Visit multiple attractions
- **Errands** - Multiple errands in one trip
- **Pick-up/drop-off** - Pick up passenger, then drive to destination
- **Charging stops** - EV routes with charging stations

## Creating Multi-Waypoint Routes

### Request Route with Waypoints

```kotlin
import com.mapbox.api.directions.v5.MapboxDirections
import com.mapbox.geojson.Point

fun requestRouteWithWaypoints(
    origin: Point,
    waypoints: List<Point>,
    destination: Point
) {
    // Combine all points
    val allCoordinates = listOf(origin) + waypoints + listOf(destination)

    val directions = MapboxDirections.builder()
        .accessToken(getString(R.string.mapbox_access_token))
        .profile(DirectionsCriteria.PROFILE_DRIVING_TRAFFIC)
        .coordinates(allCoordinates)
        .steps(true)
        .voiceInstructions(true)
        .bannerInstructions(true)
        .alternatives(false) // Alternatives not supported with waypoints
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
            Log.e("Waypoints", "Failed to get route", t)
        }
    })
}

// Usage
val origin = Point.fromLngLat(-122.4194, 37.7749) // San Francisco
val waypoint1 = Point.fromLngLat(-122.2711, 37.8044) // Oakland
val waypoint2 = Point.fromLngLat(-122.0838, 37.3861) // San Jose
val destination = Point.fromLngLat(-121.8863, 37.3382) // Milpitas

requestRouteWithWaypoints(
    origin,
    listOf(waypoint1, waypoint2),
    destination
)
```

## Waypoint Names

Add names to waypoints for better UX:

```kotlin
val directions = MapboxDirections.builder()
    .accessToken(YOUR_TOKEN)
    .coordinates(allCoordinates)
    .waypointNames(listOf(
        "Start", // Origin
        "Coffee Shop", // Waypoint 1
        "Post Office", // Waypoint 2
        "Home" // Destination
    ))
    .build()
```

## Detecting Waypoint Arrival

### Arrival Observer

```kotlin
import com.mapbox.navigation.core.arrival.ArrivalObserver

val arrivalObserver = object : ArrivalObserver {
    override fun onWaypointArrival(routeProgress: RouteProgress) {
        val waypointIndex = routeProgress.currentLegProgress?.legIndex ?: 0
        val waypoint = routeProgress.currentLegProgress?.routeLeg?.destination()

        Log.d("Waypoint", "Arrived at waypoint $waypointIndex")
        showWaypointArrivalNotification(waypointIndex)

        // Optionally pause navigation
        // mapboxNavigation.stopTripSession()
    }

    override fun onFinalDestinationArrival(routeProgress: RouteProgress) {
        Log.d("Waypoint", "Arrived at final destination")
        showFinalArrivalNotification()

        // Stop navigation
        mapboxNavigation.stopTripSession()
    }

    override fun onNextRouteLegStart(routeLegProgress: RouteLegProgress) {
        val nextLegIndex = routeLegProgress.legIndex
        Log.d("Waypoint", "Starting leg $nextLegIndex")
    }
}

mapboxNavigation.registerArrivalObserver(arrivalObserver)
```

### Configuring Arrival Threshold

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

## Waypoint Markers

### Display Waypoint Markers on Map

```kotlin
import com.mapbox.maps.plugin.annotation.generated.PointAnnotationOptions
import com.mapbox.maps.plugin.annotation.generated.createPointAnnotationManager

fun addWaypointMarkers(waypoints: List<Point>) {
    val annotationApi = mapView.annotations
    val pointAnnotationManager = annotationApi.createPointAnnotationManager()

    waypoints.forEachIndexed { index, point ->
        val pointAnnotationOptions = PointAnnotationOptions()
            .withPoint(point)
            .withIconImage(createNumberedMarkerBitmap(index + 1))

        pointAnnotationManager.create(pointAnnotationOptions)
    }
}

private fun createNumberedMarkerBitmap(number: Int): Bitmap {
    // Create bitmap with number
    val size = 100
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)

    // Draw circle
    val paint = Paint().apply {
        color = Color.BLUE
        style = Paint.Style.FILL
    }
    canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)

    // Draw number
    val textPaint = Paint().apply {
        color = Color.WHITE
        textSize = 40f
        textAlign = Paint.Align.CENTER
    }
    canvas.drawText(
        number.toString(),
        size / 2f,
        size / 2f + 15f,
        textPaint
    )

    return bitmap
}
```

## Removing Waypoints

### Skip Next Waypoint

```kotlin
fun skipNextWaypoint() {
    val currentRoutes = mapboxNavigation.getNavigationRoutes()
    if (currentRoutes.isEmpty()) return

    val currentRoute = currentRoutes.first()
    val currentLegIndex = getCurrentLegIndex()

    if (currentLegIndex < currentRoute.legs.size - 1) {
        // Move to next leg
        val nextLegIndex = currentLegIndex + 1
        mapboxNavigation.updateLegIndex(nextLegIndex)
    }
}
```

### Remove Specific Waypoint

```kotlin
fun removeWaypoint(waypointIndex: Int) {
    val currentRoutes = mapboxNavigation.getNavigationRoutes()
    if (currentRoutes.isEmpty()) return

    // Get current route coordinates
    val route = currentRoutes.first()
    val coordinates = route.routeOptions?.coordinates() ?: return

    // Remove waypoint
    val newCoordinates = coordinates.toMutableList().apply {
        removeAt(waypointIndex + 1) // +1 because index 0 is origin
    }

    // Request new route with remaining waypoints
    requestRoute(newCoordinates)
}
```

## Adding Waypoints Dynamically

```kotlin
fun addWaypoint(newWaypoint: Point) {
    val currentRoutes = mapboxNavigation.getNavigationRoutes()
    if (currentRoutes.isEmpty()) return

    val route = currentRoutes.first()
    val currentCoordinates = route.routeOptions?.coordinates() ?: return

    // Insert waypoint before final destination
    val newCoordinates = currentCoordinates.toMutableList().apply {
        add(size - 1, newWaypoint) // Insert before last (destination)
    }

    // Request new route with added waypoint
    requestRoute(newCoordinates)
}
```

## Pausing at Waypoints

```kotlin
class NavigationActivity : AppCompatActivity() {

    private var isPausedAtWaypoint = false

    private val arrivalObserver = object : ArrivalObserver {
        override fun onWaypointArrival(routeProgress: RouteProgress) {
            // Pause navigation at waypoint
            pauseNavigationAtWaypoint(routeProgress)
        }

        override fun onFinalDestinationArrival(routeProgress: RouteProgress) {
            stopNavigation()
        }

        override fun onNextRouteLegStart(routeLegProgress: RouteLegProgress) {
            isPausedAtWaypoint = false
        }
    }

    private fun pauseNavigationAtWaypoint(routeProgress: RouteProgress) {
        isPausedAtWaypoint = true

        // Stop trip session (optional - pauses navigation)
        // mapboxNavigation.stopTripSession()

        // Show waypoint reached dialog
        val waypointIndex = routeProgress.currentLegProgress?.legIndex ?: 0
        showWaypointDialog(waypointIndex)
    }

    private fun showWaypointDialog(waypointIndex: Int) {
        AlertDialog.Builder(this)
            .setTitle("Waypoint Reached")
            .setMessage("You've arrived at stop ${waypointIndex + 1}. Continue to next destination?")
            .setPositiveButton("Continue") { _, _ ->
                resumeNavigation()
            }
            .setNegativeButton("Skip") { _, _ ->
                skipNextWaypoint()
            }
            .setNeutralButton("End Navigation") { _, _ ->
                stopNavigation()
            }
            .show()
    }

    private fun resumeNavigation() {
        if (isPausedAtWaypoint) {
            // Resume trip session if stopped
            // mapboxNavigation.startTripSession()

            // Move to next leg
            val currentLegIndex = getCurrentLegIndex()
            mapboxNavigation.updateLegIndex(currentLegIndex + 1)

            isPausedAtWaypoint = false
        }
    }
}
```

## Complete Example

```kotlin
class MultiWaypointNavigationActivity : AppCompatActivity() {

    private lateinit var mapboxNavigation: MapboxNavigation
    private val waypoints = mutableListOf<Point>()

    private val arrivalObserver = object : ArrivalObserver {
        override fun onWaypointArrival(routeProgress: RouteProgress) {
            val legIndex = routeProgress.currentLegProgress?.legIndex ?: 0
            handleWaypointArrival(legIndex)
        }

        override fun onFinalDestinationArrival(routeProgress: RouteProgress) {
            handleFinalArrival()
        }

        override fun onNextRouteLegStart(routeLegProgress: RouteLegProgress) {
            val legIndex = routeLegProgress.legIndex
            Log.d("Navigation", "Starting route to waypoint $legIndex")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_navigation)

        mapboxNavigation.registerArrivalObserver(arrivalObserver)

        // Set up waypoints
        setupWaypoints()

        // Request multi-waypoint route
        requestMultiWaypointRoute()
    }

    private fun setupWaypoints() {
        waypoints.add(Point.fromLngLat(-122.4194, 37.7749)) // Start: SF
        waypoints.add(Point.fromLngLat(-122.2711, 37.8044)) // Waypoint 1: Oakland
        waypoints.add(Point.fromLngLat(-122.0838, 37.3861)) // Waypoint 2: San Jose
        waypoints.add(Point.fromLngLat(-121.8863, 37.3382)) // End: Milpitas

        // Add markers
        addWaypointMarkers(waypoints)
    }

    private fun requestMultiWaypointRoute() {
        val directions = MapboxDirections.builder()
            .accessToken(getString(R.string.mapbox_access_token))
            .profile(DirectionsCriteria.PROFILE_DRIVING_TRAFFIC)
            .coordinates(waypoints)
            .waypointNames(listOf(
                "Start",
                "Coffee Stop",
                "Lunch Break",
                "Final Destination"
            ))
            .steps(true)
            .voiceInstructions(true)
            .bannerInstructions(true)
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
                    mapboxNavigation.startTripSession()
                }
            }

            override fun onFailure(call: Call<DirectionsResponse>, t: Throwable) {
                Log.e("Navigation", "Failed to get route", t)
            }
        })
    }

    private fun handleWaypointArrival(legIndex: Int) {
        Toast.makeText(
            this,
            "Arrived at waypoint ${legIndex + 1}",
            Toast.LENGTH_SHORT
        ).show()

        // Optionally pause for user confirmation
        // showWaypointDialog(legIndex)
    }

    private fun handleFinalArrival() {
        Toast.makeText(this, "You have arrived!", Toast.LENGTH_LONG).show()
        mapboxNavigation.stopTripSession()
    }

    override fun onDestroy() {
        super.onDestroy()
        mapboxNavigation.unregisterArrivalObserver(arrivalObserver)
    }
}
```

## Best Practices

1. **Limit waypoints** - Too many (>10) can affect performance
2. **Add waypoint names** - Better UX in instructions
3. **Show waypoint markers** - Visual indication on map
4. **Handle arrival** - Allow users to confirm before continuing
5. **Allow skipping** - Let users skip waypoints if needed
6. **Test route calculation** - More waypoints = longer calculation time
7. **Consider alternatives** - Waypoints disable alternative routes

## Limitations

- **Max waypoints**: 25 for regular routing, 12 for EV routing
- **No alternatives**: Alternative routes not supported with waypoints
- **Calculation time**: More waypoints = longer route calculation
- **Coordinate order**: Must be in visit order (can't optimize automatically)

## Related Documentation
- [Directions API](../apis/directions-api.md) - Requesting routes with waypoints
- [Building Highlights](building-highlights.md) - Highlighting waypoint buildings
- [Trip Progress](trip-progress.md) - Showing progress to next waypoint

## External Resources
- Waypoints Guide: https://docs.mapbox.com/android/navigation/guides/core-navigation/waypoints/
- Directions API Waypoints: https://docs.mapbox.com/api/navigation/directions/#waypoints
