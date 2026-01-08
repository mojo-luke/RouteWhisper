# Automatic Rerouting

## Overview
The Navigation SDK automatically detects when users go off-route and calculates new routes to get them back on track. This happens without developer intervention but can be customized.

## How It Works

1. **Off-Route Detection** - SDK monitors deviation from planned route
2. **Automatic Request** - New route automatically requested when threshold exceeded
3. **Route Update** - New route seamlessly replaces old route
4. **Notification** - App receives callback about rerouting event

## Automatic Rerouting (Default)

Rerouting is **enabled by default**. No configuration needed:

```kotlin
// Automatic rerouting works out of the box
mapboxNavigation.startTripSession()
mapboxNavigation.setNavigationRoutes(routes)

// SDK automatically reroutes when user goes off-route
```

## Customizing Reroute Options

### Configure Reroute Settings

```kotlin
import com.mapbox.navigation.base.options.RerouteOptions

val rerouteOptions = RerouteOptions.Builder()
    .distanceFromRouteThreshold(25.0) // meters before reroute triggered
    .build()

val navigationOptions = NavigationOptions.Builder(context)
    .accessToken(YOUR_TOKEN)
    .rerouteOptions(rerouteOptions)
    .build()
```

### Disable Automatic Rerouting

```kotlin
val navigationOptions = NavigationOptions.Builder(context)
    .accessToken(YOUR_TOKEN)
    .enableAutoReroute(false) // Disable automatic rerouting
    .build()
```

## Monitoring Reroute Events

### Reroute State Observer

Listen for reroute events:

```kotlin
import com.mapbox.navigation.core.reroute.RerouteState

mapboxNavigation.registerRerouteStateObserver { rerouteState ->
    when (rerouteState) {
        is RerouteState.FetchingRoute -> {
            // Rerouting in progress
            showReroutingIndicator()
        }
        is RerouteState.RouteFetched -> {
            // New route received
            hideReroutingIndicator()
            Log.d("Reroute", "New route calculated")
        }
        is RerouteState.Failed -> {
            // Reroute failed
            hideReroutingIndicator()
            showRerouteError(rerouteState.message)
        }
        is RerouteState.Idle -> {
            // No rerouting happening
        }
    }
}
```

### Off-Route Observer

Detect when user goes off-route:

```kotlin
import com.mapbox.navigation.core.trip.session.OffRouteObserver

mapboxNavigation.registerOffRouteObserver(object : OffRouteObserver {
    override fun onOffRouteStateChanged(offRoute: Boolean) {
        if (offRoute) {
            Log.d("Navigation", "User is off route - rerouting...")
            showOffRouteWarning()
        } else {
            Log.d("Navigation", "User is on route")
            hideOffRouteWarning()
        }
    }
})
```

## Manual Rerouting

Trigger reroute manually:

```kotlin
import com.mapbox.navigation.core.directions.session.RoutesExtra

fun requestManualReroute() {
    // Get current location
    val currentLocation = mapView.location.lastKnownLocation ?: return

    // Request new route from current location to original destination
    val origin = Point.fromLngLat(currentLocation.longitude, currentLocation.latitude)
    val destination = getCurrentDestination() // Your method

    val directions = MapboxDirections.builder()
        .accessToken(getString(R.string.mapbox_access_token))
        .profile(DirectionsCriteria.PROFILE_DRIVING_TRAFFIC)
        .origin(origin)
        .destination(destination)
        .steps(true)
        .voiceInstructions(true)
        .bannerInstructions(true)
        .alternatives(true)
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
            Log.e("Reroute", "Manual reroute failed", t)
        }
    })
}
```

## Reroute Controller

### Custom Reroute Logic

Implement custom reroute behavior:

```kotlin
import com.mapbox.navigation.core.reroute.RerouteController
import com.mapbox.navigation.core.reroute.RerouteOptions

class CustomRerouteController : RerouteController {

    override fun reroute(callback: RerouteController.RoutesCallback) {
        // Implement custom reroute logic
        // e.g., add custom parameters, use different profile, etc.

        // Request route
        val directions = buildCustomDirectionsRequest()

        directions.enqueueCall(object : Callback<DirectionsResponse> {
            override fun onResponse(
                call: Call<DirectionsResponse>,
                response: Response<DirectionsResponse>
            ) {
                val routes = response.body()?.routes()
                if (routes != null && routes.isNotEmpty()) {
                    val navigationRoutes = routes.map { it.toNavigationRoute() }
                    callback.onNewRoutes(navigationRoutes)
                } else {
                    callback.onError("No routes found")
                }
            }

            override fun onFailure(call: Call<DirectionsResponse>, t: Throwable) {
                callback.onError(t.message ?: "Reroute failed")
            }
        })
    }

    override fun interrupt() {
        // Cancel ongoing reroute request
    }

    private fun buildCustomDirectionsRequest(): MapboxDirections {
        // Build custom request
        return MapboxDirections.builder()
            .accessToken(YOUR_TOKEN)
            // ... custom parameters
            .build()
    }
}

// Set custom controller
val navigationOptions = NavigationOptions.Builder(context)
    .accessToken(YOUR_TOKEN)
    .rerouteController(CustomRerouteController())
    .build()
```

## Handling Reroute Failures

### Retry Logic

```kotlin
private var rerouteAttempts = 0
private val maxRerouteAttempts = 3

mapboxNavigation.registerRerouteStateObserver { rerouteState ->
    when (rerouteState) {
        is RerouteState.Failed -> {
            rerouteAttempts++

            if (rerouteAttempts < maxRerouteAttempts) {
                // Retry reroute
                Handler(Looper.getMainLooper()).postDelayed({
                    requestManualReroute()
                }, 2000) // Wait 2 seconds before retry
            } else {
                // Max attempts reached
                showRerouteFailureMessage()
                rerouteAttempts = 0
            }
        }
        is RerouteState.RouteFetched -> {
            // Success - reset attempts
            rerouteAttempts = 0
        }
        else -> {}
    }
}
```

### Fallback Strategy

```kotlin
private fun handleRerouteFailure() {
    // Option 1: Continue with old route
    // Let user know they need to get back on route

    // Option 2: Stop navigation
    stopNavigation()
    showMessage("Unable to calculate new route. Please restart navigation.")

    // Option 3: Use cached route
    val cachedRoute = getCachedRoute()
    if (cachedRoute != null) {
        mapboxNavigation.setNavigationRoutes(listOf(cachedRoute))
    }
}
```

## Complete Example

```kotlin
class NavigationActivity : AppCompatActivity() {

    private lateinit var mapboxNavigation: MapboxNavigation
    private var isRerouting = false

    private val rerouteStateObserver = { rerouteState: RerouteState ->
        when (rerouteState) {
            is RerouteState.FetchingRoute -> {
                isRerouting = true
                showReroutingIndicator()
            }
            is RerouteState.RouteFetched -> {
                isRerouting = false
                hideReroutingIndicator()
                showToast("New route calculated")
            }
            is RerouteState.Failed -> {
                isRerouting = false
                hideReroutingIndicator()
                showToast("Reroute failed: ${rerouteState.message}")
                handleRerouteFailure()
            }
            is RerouteState.Idle -> {
                isRerouting = false
            }
        }
    }

    private val offRouteObserver = OffRouteObserver { offRoute ->
        if (offRoute) {
            showOffRouteWarning()
        } else {
            hideOffRouteWarning()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_navigation)

        // Configure reroute options
        val rerouteOptions = RerouteOptions.Builder()
            .distanceFromRouteThreshold(25.0)
            .build()

        val navigationOptions = NavigationOptions.Builder(this)
            .accessToken(getString(R.string.mapbox_access_token))
            .rerouteOptions(rerouteOptions)
            .build()

        // Register observers
        mapboxNavigation.registerRerouteStateObserver(rerouteStateObserver)
        mapboxNavigation.registerOffRouteObserver(offRouteObserver)

        // Manual reroute button
        findViewById<Button>(R.id.rerouteButton).setOnClickListener {
            requestManualReroute()
        }
    }

    private fun showReroutingIndicator() {
        findViewById<ProgressBar>(R.id.rerouteProgress).visibility = View.VISIBLE
    }

    private fun hideReroutingIndicator() {
        findViewById<ProgressBar>(R.id.rerouteProgress).visibility = View.GONE
    }

    private fun showOffRouteWarning() {
        findViewById<TextView>(R.id.offRouteWarning).apply {
            text = "Off route - calculating new route..."
            visibility = View.VISIBLE
        }
    }

    private fun hideOffRouteWarning() {
        findViewById<TextView>(R.id.offRouteWarning).visibility = View.GONE
    }

    private fun handleRerouteFailure() {
        // Implement fallback strategy
        showToast("Unable to calculate new route. Continuing with current route.")
    }

    override fun onDestroy() {
        super.onDestroy()
        mapboxNavigation.unregisterRerouteStateObserver(rerouteStateObserver)
        mapboxNavigation.unregisterOffRouteObserver(offRouteObserver)
    }
}
```

## Best Practices

1. **Keep automatic rerouting enabled** for best UX
2. **Show rerouting indicator** to inform user
3. **Handle reroute failures gracefully** with retry or fallback
4. **Don't reroute too frequently** - use appropriate threshold
5. **Preserve route options** (avoid tolls, etc.) when rerouting
6. **Test offline scenarios** - rerouting requires network
7. **Unregister observers** in onDestroy()

## Common Issues

### Frequent rerouting
- Increase `distanceFromRouteThreshold`
- Check GPS accuracy
- Ensure map matching is working correctly

### Reroute not triggered
- Verify automatic rerouting is enabled
- Check trip session is started
- Ensure route is set to navigation

### Slow rerouting
- Network latency
- Consider caching routes
- Use appropriate routing profile

## Related Documentation
- [Initialization Guide](initialization.md) - MapboxNavigation setup
- [Directions API](../apis/directions-api.md) - Requesting routes
- [Troubleshooting](../troubleshooting.md) - Common rerouting issues

## External Resources
- Navigation SDK Guide: https://docs.mapbox.com/android/navigation/guides/
- Rerouting Examples: https://github.com/mapbox/mapbox-navigation-android-examples
