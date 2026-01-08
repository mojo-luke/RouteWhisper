# Trip Progress Component

## Overview
The `MapboxTripProgressView` component displays real-time navigation metrics including estimated time of arrival (ETA), distance remaining, and time remaining.

## Displayed Information

The component shows three key metrics:
- **Estimated Time of Arrival (ETA)** - Predicted arrival time
- **Distance Remaining** - Total distance left to destination
- **Time Remaining** - Estimated time until arrival

## Basic Implementation

### Step 1: Add to Layout

```xml
<com.mapbox.navigation.ui.tripprogress.view.MapboxTripProgressView
    android:id="@+id/tripProgressView"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:layout_alignParentBottom="true" />
```

### Step 2: Initialize Trip Progress API

```kotlin
import com.mapbox.navigation.ui.tripprogress.api.MapboxTripProgressApi
import com.mapbox.navigation.ui.tripprogress.view.MapboxTripProgressView
import com.mapbox.navigation.ui.tripprogress.model.TripProgressUpdateFormatter

class NavigationActivity : AppCompatActivity() {

    private lateinit var tripProgressApi: MapboxTripProgressApi
    private lateinit var tripProgressView: MapboxTripProgressView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_navigation)

        tripProgressView = findViewById(R.id.tripProgressView)

        val formatter = TripProgressUpdateFormatter.Builder(this)
            .build()

        tripProgressApi = MapboxTripProgressApi(formatter)
    }
}
```

### Step 3: Register Route Progress Observer

```kotlin
import com.mapbox.navigation.core.trip.session.RouteProgressObserver

val routeProgressObserver = RouteProgressObserver { routeProgress ->
    // Get formatted trip progress data
    val tripProgressData = tripProgressApi.getTripProgress(routeProgress)

    // Render to view
    tripProgressView.render(tripProgressData)
}

mapboxNavigation.registerRouteProgressObserver(routeProgressObserver)
```

### Step 4: Clean Up

```kotlin
override fun onDestroy() {
    super.onDestroy()
    mapboxNavigation.unregisterRouteProgressObserver(routeProgressObserver)
}
```

## Custom Formatting

### Custom Formatter

Create custom formatter to control how data is displayed:

```kotlin
import com.mapbox.navigation.ui.tripprogress.model.TripProgressUpdateFormatter
import com.mapbox.navigation.base.formatter.DistanceFormatterOptions
import com.mapbox.navigation.base.formatter.UnitType
import android.text.SpannableString
import android.text.style.ForegroundColorSpan

class CustomTripProgressFormatter(context: Context) : TripProgressUpdateFormatter {

    private val distanceFormatter = DistanceFormatterOptions.Builder(context)
        .unitType(UnitType.IMPERIAL)
        .build()

    override fun getEta(routeProgress: RouteProgress): SpannableString {
        val eta = routeProgress.durationRemaining?.let { duration ->
            val etaTime = Calendar.getInstance().apply {
                add(Calendar.SECOND, duration.toInt())
            }
            SimpleDateFormat("h:mm a", Locale.US).format(etaTime.time)
        } ?: "--:--"

        return SpannableString(eta).apply {
            setSpan(
                ForegroundColorSpan(Color.WHITE),
                0,
                length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    override fun getDistanceRemaining(routeProgress: RouteProgress): SpannableString {
        val distanceRemaining = routeProgress.distanceRemaining
        val formatted = formatDistance(distanceRemaining)

        return SpannableString(formatted).apply {
            setSpan(
                ForegroundColorSpan(Color.WHITE),
                0,
                length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    override fun getTimeRemaining(routeProgress: RouteProgress): SpannableString {
        val duration = routeProgress.durationRemaining ?: 0.0
        val hours = (duration / 3600).toInt()
        val minutes = ((duration % 3600) / 60).toInt()

        val formatted = when {
            hours > 0 -> "$hours hr $minutes min"
            else -> "$minutes min"
        }

        return SpannableString(formatted).apply {
            setSpan(
                ForegroundColorSpan(Color.WHITE),
                0,
                length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    private fun formatDistance(meters: Double): String {
        return when (distanceFormatter.unitType) {
            UnitType.IMPERIAL -> {
                val miles = meters / 1609.34
                when {
                    miles >= 10 -> String.format("%.0f mi", miles)
                    miles >= 0.1 -> String.format("%.1f mi", miles)
                    else -> String.format("%.0f ft", meters * 3.28084)
                }
            }
            UnitType.METRIC -> {
                val km = meters / 1000
                when {
                    km >= 10 -> String.format("%.0f km", km)
                    km >= 0.1 -> String.format("%.1f km", km)
                    else -> String.format("%.0f m", meters)
                }
            }
        }
    }
}

// Usage
val customFormatter = CustomTripProgressFormatter(this)
tripProgressApi = MapboxTripProgressApi(customFormatter)
```

## Styling

### XML Styling

```xml
<com.mapbox.navigation.ui.tripprogress.view.MapboxTripProgressView
    android:id="@+id/tripProgressView"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    app:tripProgressViewBackgroundColor="@color/navigationBackground"
    app:tripProgressTextColor="@color/white"
    app:tripProgressLabelColor="@color/lightGray" />
```

### Programmatic Styling

```kotlin
import com.mapbox.navigation.ui.tripprogress.view.MapboxTripProgressViewOptions

val options = MapboxTripProgressViewOptions.Builder()
    .backgroundColor(ContextCompat.getColor(this, R.color.darkGray))
    .textColor(ContextCompat.getColor(this, R.color.white))
    .textSize(14f)
    .build()

tripProgressView.updateOptions(options)
```

## Accessing Raw Data

Get trip progress data without rendering:

```kotlin
val routeProgressObserver = RouteProgressObserver { routeProgress ->
    // Access raw values
    val distanceRemaining = routeProgress.distanceRemaining // meters
    val durationRemaining = routeProgress.durationRemaining // seconds
    val distanceTraveled = routeProgress.distanceTraveled // meters
    val fractionTraveled = routeProgress.fractionTraveled // 0.0 to 1.0

    // Calculate ETA
    val etaCalendar = Calendar.getInstance().apply {
        add(Calendar.SECOND, durationRemaining.toInt())
    }

    // Use data for custom logic
    updateCustomUI(distanceRemaining, durationRemaining, etaCalendar.time)
}
```

## Multi-Leg Routes

For routes with multiple waypoints:

```kotlin
val routeProgressObserver = RouteProgressObserver { routeProgress ->
    val currentLeg = routeProgress.currentLegProgress
    val upcomingLeg = routeProgress.upcomingStepPoints

    // Current leg progress
    val legDistanceRemaining = currentLeg?.distanceRemaining ?: 0.0
    val legDurationRemaining = currentLeg?.durationRemaining ?: 0.0

    // Total route progress (all legs)
    val totalDistanceRemaining = routeProgress.distanceRemaining
    val totalDurationRemaining = routeProgress.durationRemaining

    // Show current leg or total - your choice
    tripProgressView.render(tripProgressApi.getTripProgress(routeProgress))
}
```

## Complete Example

```kotlin
class NavigationActivity : AppCompatActivity() {

    private lateinit var mapboxNavigation: MapboxNavigation
    private lateinit var tripProgressApi: MapboxTripProgressApi
    private lateinit var tripProgressView: MapboxTripProgressView

    private val routeProgressObserver = RouteProgressObserver { routeProgress ->
        updateTripProgress(routeProgress)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_navigation)

        // Initialize views
        tripProgressView = findViewById(R.id.tripProgressView)

        // Initialize API with custom formatter
        val formatter = TripProgressUpdateFormatter.Builder(this)
            .distanceRoundingIncrement(50) // Round to nearest 50
            .build()

        tripProgressApi = MapboxTripProgressApi(formatter)

        // Customize appearance
        val options = MapboxTripProgressViewOptions.Builder()
            .backgroundColor(ContextCompat.getColor(this, R.color.navigationDark))
            .textColor(ContextCompat.getColor(this, R.color.white))
            .build()

        tripProgressView.updateOptions(options)

        // Register observer
        mapboxNavigation.registerRouteProgressObserver(routeProgressObserver)
    }

    private fun updateTripProgress(routeProgress: RouteProgress) {
        // Get formatted data
        val tripProgressData = tripProgressApi.getTripProgress(routeProgress)

        // Render to view
        tripProgressView.render(tripProgressData)

        // Optional: Log progress for debugging
        Log.d("TripProgress", """
            Distance Remaining: ${routeProgress.distanceRemaining}m
            Duration Remaining: ${routeProgress.durationRemaining}s
            Fraction Traveled: ${routeProgress.fractionTraveled}
        """.trimIndent())
    }

    override fun onDestroy() {
        super.onDestroy()
        mapboxNavigation.unregisterRouteProgressObserver(routeProgressObserver)
    }
}
```

## Unit Conversion

### Imperial Units (US)
- Distance: miles (mi) and feet (ft)
- Format: "5.2 mi" or "500 ft"

### Metric Units
- Distance: kilometers (km) and meters (m)
- Format: "8.3 km" or "500 m"

### Setting Unit Type

```kotlin
val formatter = TripProgressUpdateFormatter.Builder(this)
    .distanceFormatterOptions(
        DistanceFormatterOptions.Builder(this)
            .unitType(UnitType.IMPERIAL) // or UnitType.METRIC
            .build()
    )
    .build()
```

## Best Practices

1. **Place at bottom of screen** for easy glance while navigating
2. **Use high contrast colors** for readability
3. **Update frequently** (every RouteProgress update)
4. **Show both distance and time** for comprehensive progress info
5. **Use appropriate units** based on user locale
6. **Keep formatting consistent** throughout app
7. **Test with various route lengths** - short trips vs long trips

## Common Issues

### Progress not updating
- Ensure RouteProgressObserver is registered
- Check navigation session is active (trip session started)
- Verify route is set to MapboxNavigation

### Incorrect ETA
- ETA based on current traffic conditions
- Updates dynamically as conditions change
- Can vary during navigation

### Wrong units displayed
- Check DistanceFormatterOptions unit type
- Use device locale for automatic unit selection

## Related Documentation
- [Maneuver Instructions](maneuver-instructions.md) - Turn-by-turn visual guidance
- [Voice Instructions](voice-instructions.md) - Audio guidance
- [Route Progress](../apis/directions-api.md) - Route progress data structure
- [UI Components Overview](ui-components.md) - All UI components

## External Resources
- Trip Progress Guide: https://docs.mapbox.com/android/navigation/guides/ui-components/trip-progress/
- Navigation SDK Examples: https://github.com/mapbox/mapbox-navigation-android-examples
