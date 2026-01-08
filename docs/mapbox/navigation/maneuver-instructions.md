# Maneuver Instructions Component

## Overview
The `MapboxManeuverView` component displays visual turn-by-turn navigation instructions using banner instruction data from the Directions API. It provides a comprehensive display of upcoming maneuvers with road names, turn icons, lane guidance, and distance information.

## What It Displays

### Primary Maneuver
Shows the name of the road, freeway, or exit of the next maneuver with:
- **Turn icon** - Visual directional indicator (turn left/right, merge, exit, etc.)
- **Primary instruction text** - Main direction ("Turn right onto Market Street")
- **Step distance** - Remaining distance to complete current maneuver

### Secondary Maneuver
Additional road details when available:
- Alternative road names
- Exit information
- Route numbers

### Sub Maneuver
Information about the following maneuver if it occurs shortly after the primary:
- Upcoming turn preview
- "Then turn left" type instructions

### Lane Guidance
Helps users select the correct lane for upcoming turns:
- Visual lane indicators
- Highlighted lanes to use
- Turn direction per lane

### Upcoming Maneuver List
Preview of subsequent turns in scrollable list format.

## Basic Implementation

### Step 1: Request Banner Instructions in Directions API

```kotlin
import com.mapbox.api.directions.v5.MapboxDirections

val directions = MapboxDirections.builder()
    .accessToken(YOUR_TOKEN)
    .origin(origin)
    .destination(destination)
    .steps(true)
    .bannerInstructions(true) // Enable banner instructions
    .build()
```

### Step 2: Add to Layout

```xml
<com.mapbox.navigation.ui.maneuver.view.MapboxManeuverView
    android:id="@+id/maneuverView"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:layout_alignParentTop="true" />
```

### Step 3: Initialize Maneuver API

```kotlin
import com.mapbox.navigation.ui.maneuver.api.MapboxManeuverApi
import com.mapbox.navigation.ui.maneuver.view.MapboxManeuverView

class NavigationActivity : AppCompatActivity() {

    private lateinit var maneuverApi: MapboxManeuverApi
    private lateinit var maneuverView: MapboxManeuverView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_navigation)

        maneuverView = findViewById(R.id.maneuverView)
        maneuverApi = MapboxManeuverApi(MapboxDistanceFormatter(this))
    }
}
```

### Step 4: Register Route Progress Observer

```kotlin
import com.mapbox.navigation.core.trip.session.RouteProgressObserver

val routeProgressObserver = RouteProgressObserver { routeProgress ->
    // Get maneuver data
    maneuverApi.getManeuvers(routeProgress).fold(
        { maneuvers ->
            // Render maneuvers to view
            maneuverView.renderManeuvers(maneuvers)
        },
        { error ->
            Log.e("Maneuver", "Error getting maneuvers: $error")
        }
    )
}

mapboxNavigation.registerRouteProgressObserver(routeProgressObserver)
```

### Step 5: Handle Road Shields

Road shields (highway/route numbers) require image loading:

```kotlin
import com.mapbox.navigation.ui.shield.api.MapboxRouteShieldApi

val routeShieldApi = MapboxRouteShieldApi()

val routeProgressObserver = RouteProgressObserver { routeProgress ->
    maneuverApi.getManeuvers(routeProgress).fold(
        { maneuvers ->
            maneuverView.renderManeuvers(maneuvers)

            // Get road shields
            routeShieldApi.getRoadShields(routeProgress) { shields ->
                shields.fold(
                    { roadShieldResult ->
                        maneuverView.renderManeuverShields(roadShieldResult)
                    },
                    { error ->
                        Log.e("Shields", "Error getting shields: $error")
                    }
                )
            }
        },
        { error ->
            Log.e("Maneuver", "Error: $error")
        }
    )
}
```

## Customization

### XML Styling

Customize appearance through XML attributes:

```xml
<com.mapbox.navigation.ui.maneuver.view.MapboxManeuverView
    android:id="@+id/maneuverView"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    app:maneuverViewBackgroundColor="@color/navigationBackground"
    app:primaryManeuverTextColor="@color/white"
    app:secondaryManeuverTextColor="@color/gray"
    app:distanceTextColor="@color/white"
    app:turnIconColor="@color/blue"
    app:laneGuidanceBackgroundColor="@color/darkGray" />
```

### Programmatic Styling

```kotlin
import com.mapbox.navigation.ui.maneuver.view.MapboxManeuverViewOptions

val options = MapboxManeuverViewOptions.Builder()
    .primaryManeuverTextAppearance(R.style.PrimaryManeuverText)
    .secondaryManeuverTextAppearance(R.style.SecondaryManeuverText)
    .turnIconColor(ContextCompat.getColor(this, R.color.blue))
    .build()

maneuverView.updateOptions(options)
```

### Using Individual Subviews

For complete layout control, use individual components:

```xml
<LinearLayout
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical">

    <!-- Primary maneuver only -->
    <com.mapbox.navigation.ui.maneuver.view.MapboxPrimaryManeuver
        android:id="@+id/primaryManeuver"
        android:layout_width="match_parent"
        android:layout_height="wrap_content" />

    <!-- Lane guidance only -->
    <com.mapbox.navigation.ui.maneuver.view.MapboxLaneGuidance
        android:id="@+id/laneGuidance"
        android:layout_width="match_parent"
        android:layout_height="wrap_content" />

    <!-- Upcoming maneuvers list -->
    <com.mapbox.navigation.ui.maneuver.view.MapboxUpcomingManeuverAdapter
        android:id="@+id/upcomingManeuvers"
        android:layout_width="match_parent"
        android:layout_height="wrap_content" />
</LinearLayout>
```

## Maneuver Types

The SDK supports various maneuver types with corresponding icons:

### Basic Turns
- Turn left/right
- Turn slight left/right
- Turn sharp left/right
- U-turn

### Merges
- Merge left/right
- Merge slight left/right

### Exits
- Take exit (left/right)
- Exit ramp

### Roundabouts
- Enter roundabout
- Exit roundabout at Nth exit
- Rotary (traffic circle)

### Special Maneuvers
- Continue straight
- Fork left/right
- End of road (left/right)
- Arrival at destination

## Lane Guidance

### Enabling Lane Guidance

Lane guidance is automatically shown when available in banner instructions:

```kotlin
// Automatically displayed when route has lane data
// No additional configuration needed
```

### Lane Guidance Data

Lane guidance shows:
- **Active lanes** - Recommended lanes (highlighted)
- **Valid lanes** - Legal lanes for maneuver
- **Invalid lanes** - Lanes that don't allow maneuver

### Example Lane Display

```
Lane 1: ← (active - highlighted)
Lane 2: ↑ (valid but not recommended)
Lane 3: →↑ (invalid for current maneuver)
```

## Complete Example

```kotlin
class NavigationActivity : AppCompatActivity() {

    private lateinit var mapboxNavigation: MapboxNavigation
    private lateinit var maneuverApi: MapboxManeuverApi
    private lateinit var maneuverView: MapboxManeuverView
    private lateinit var routeShieldApi: MapboxRouteShieldApi

    private val routeProgressObserver = RouteProgressObserver { routeProgress ->
        updateManeuverView(routeProgress)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_navigation)

        // Initialize views
        maneuverView = findViewById(R.id.maneuverView)

        // Initialize APIs
        val distanceFormatter = MapboxDistanceFormatter(this)
        maneuverApi = MapboxManeuverApi(distanceFormatter)
        routeShieldApi = MapboxRouteShieldApi()

        // Customize appearance
        customizeManeuverView()

        // Register observer
        mapboxNavigation.registerRouteProgressObserver(routeProgressObserver)
    }

    private fun customizeManeuverView() {
        val options = MapboxManeuverViewOptions.Builder()
            .primaryManeuverTextAppearance(R.style.PrimaryManeuverText)
            .secondaryManeuverTextAppearance(R.style.SecondaryManeuverText)
            .subManeuverTextAppearance(R.style.SubManeuverText)
            .turnIconColor(ContextCompat.getColor(this, R.color.navigationBlue))
            .build()

        maneuverView.updateOptions(options)
    }

    private fun updateManeuverView(routeProgress: RouteProgress) {
        // Get and render maneuvers
        maneuverApi.getManeuvers(routeProgress).fold(
            { maneuvers ->
                maneuverView.renderManeuvers(maneuvers)

                // Get and render road shields
                routeShieldApi.getRoadShields(routeProgress) { result ->
                    result.fold(
                        { shields ->
                            maneuverView.renderManeuverShields(shields)
                        },
                        { error ->
                            Log.e("Shields", "Error loading shields: $error")
                        }
                    )
                }
            },
            { error ->
                Log.e("Maneuver", "Error getting maneuvers: $error")
            }
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        mapboxNavigation.unregisterRouteProgressObserver(routeProgressObserver)
    }
}
```

## Distance Formatting

Customize distance display format:

```kotlin
import com.mapbox.navigation.base.formatter.DistanceFormatterOptions
import com.mapbox.navigation.base.formatter.UnitType

val distanceFormatter = MapboxDistanceFormatter(
    DistanceFormatterOptions.Builder(this)
        .unitType(UnitType.IMPERIAL) // or UnitType.METRIC
        .roundingIncrement(50) // Round to nearest 50
        .build()
)

val maneuverApi = MapboxManeuverApi(distanceFormatter)
```

**Unit types**:
- `UnitType.IMPERIAL` - Miles, feet (US)
- `UnitType.METRIC` - Kilometers, meters

## Best Practices

1. **Always request banner instructions** in Directions API (`.bannerInstructions(true)`)
2. **Place at top of screen** for easy visibility while driving
3. **Use high contrast colors** for text and icons
4. **Load road shields asynchronously** to avoid blocking UI
5. **Handle maneuver updates smoothly** - no jarring transitions
6. **Test with various route types** - highways, urban, roundabouts
7. **Unregister observers** in onDestroy() to prevent memory leaks

## Common Issues

### Maneuver view not updating
- Ensure route has `.bannerInstructions(true)` in request
- Check RouteProgressObserver is registered
- Verify route is set to MapboxNavigation

### Road shields not displaying
- Check network connection for shield images
- Verify token has required permissions
- Ensure `getRoadShields()` callback is called

### Lane guidance not showing
- Not all routes have lane data
- Ensure route includes `.steps(true)` and `.bannerInstructions(true)`
- Lane guidance only shown near complex intersections

## Related Documentation
- [Voice Instructions](voice-instructions.md) - Audio turn guidance
- [Trip Progress](trip-progress.md) - ETA and distance display
- [Directions API](../apis/directions-api.md) - Requesting routes with banner data
- [UI Components Overview](ui-components.md) - All UI components

## External Resources
- Maneuver View Guide: https://docs.mapbox.com/android/navigation/guides/ui-components/maneuver/
- Navigation SDK Examples: https://github.com/mapbox/mapbox-navigation-android-examples
