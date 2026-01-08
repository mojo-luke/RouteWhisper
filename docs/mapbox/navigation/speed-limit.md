# Speed Limit Component

## Overview
The `MapboxSpeedInfoView` component displays the current speed limit of the road the user is traveling on, along with the user's current speed.

**Important**: Mapbox doesn't have speed limit data for every road. When data is unavailable, the API returns null.

## Basic Implementation

### Step 1: Add to Layout

```xml
<com.mapbox.navigation.ui.speedlimit.view.MapboxSpeedInfoView
    android:id="@+id/speedInfoView"
    android:layout_width="wrap_content"
    android:layout_height="wrap_content"
    android:layout_alignParentTop="true"
    android:layout_alignParentEnd="true" />
```

### Step 2: Initialize Speed Info API

```kotlin
import com.mapbox.navigation.ui.speedlimit.api.MapboxSpeedInfoApi
import com.mapbox.navigation.ui.speedlimit.view.MapboxSpeedInfoView

class NavigationActivity : AppCompatActivity() {

    private lateinit var speedInfoApi: MapboxSpeedInfoApi
    private lateinit var speedInfoView: MapboxSpeedInfoView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_navigation)

        speedInfoView = findViewById(R.id.speedInfoView)
        speedInfoApi = MapboxSpeedInfoApi()
    }
}
```

### Step 3: Register Location Observer

```kotlin
import com.mapbox.navigation.core.trip.session.LocationMatcherResult
import com.mapbox.navigation.core.trip.session.LocationObserver

val locationObserver = object : LocationObserver {
    override fun onNewLocationMatcherResult(locationMatcherResult: LocationMatcherResult) {
        val enhancedLocation = locationMatcherResult.enhancedLocation
        val speedLimit = locationMatcherResult.speedLimit

        // Update speed info
        val speedInfo = speedInfoApi.updatePostedAndCurrentSpeed(
            speedLimit,
            enhancedLocation.speed
        )

        speedInfoView.render(speedInfo)
    }

    override fun onNewRawLocation(rawLocation: Location) {
        // Not needed for speed limit
    }
}

mapboxNavigation.registerLocationObserver(locationObserver)
```

### Step 4: Clean Up

```kotlin
override fun onDestroy() {
    super.onDestroy()
    mapboxNavigation.unregisterLocationObserver(locationObserver)
}
```

## Speed Limit Data

### SpeedLimit Object

```kotlin
data class SpeedLimit(
    val speed: Int?, // Speed limit value
    val unit: String?, // "mph" or "km/h"
    val unknown: Boolean // true if speed limit is unknown
)
```

### Handling Missing Data

```kotlin
val locationObserver = object : LocationObserver {
    override fun onNewLocationMatcherResult(locationMatcherResult: LocationMatcherResult) {
        val speedLimit = locationMatcherResult.speedLimit

        if (speedLimit == null || speedLimit.unknown) {
            // No speed limit data available
            speedInfoView.visibility = View.GONE
        } else {
            // Speed limit available
            speedInfoView.visibility = View.VISIBLE

            val speedInfo = speedInfoApi.updatePostedAndCurrentSpeed(
                speedLimit,
                locationMatcherResult.enhancedLocation.speed
            )

            speedInfoView.render(speedInfo)
        }
    }

    override fun onNewRawLocation(rawLocation: Location) {}
}
```

## Customization

### Sign Styles

Speed limit signs vary by region:
- **US Style**: White background, black text, rectangular
- **Vienna Style** (Europe): White background, red circle border

The SDK automatically chooses appropriate style based on speed limit data.

### Custom Styling

```xml
<com.mapbox.navigation.ui.speedlimit.view.MapboxSpeedInfoView
    android:id="@+id/speedInfoView"
    android:layout_width="wrap_content"
    android:layout_height="wrap_content"
    app:speedLimitTextColor="@color/black"
    app:currentSpeedTextColor="@color/blue"
    app:speedLimitBackgroundColor="@color/white"
    app:speedLimitBorderColor="@color/red" />
```

## Overspeed Detection

### Detecting Speeding

```kotlin
val locationObserver = object : LocationObserver {
    override fun onNewLocationMatcherResult(locationMatcherResult: LocationMatcherResult) {
        val speedLimit = locationMatcherResult.speedLimit
        val currentSpeed = locationMatcherResult.enhancedLocation.speed

        if (speedLimit != null && !speedLimit.unknown) {
            val speedLimitValue = convertToMetersPerSecond(speedLimit.speed ?: 0, speedLimit.unit)

            if (currentSpeed > speedLimitValue) {
                // User is speeding
                val overspeedAmount = currentSpeed - speedLimitValue
                highlightOverspeed(overspeedAmount)
            } else {
                clearOverspeedHighlight()
            }
        }

        // Render speed info
        val speedInfo = speedInfoApi.updatePostedAndCurrentSpeed(speedLimit, currentSpeed)
        speedInfoView.render(speedInfo)
    }

    override fun onNewRawLocation(rawLocation: Location) {}
}

private fun convertToMetersPerSecond(speed: Int, unit: String?): Double {
    return when (unit) {
        "mph" -> speed * 0.44704 // mph to m/s
        "km/h" -> speed / 3.6 // km/h to m/s
        else -> speed.toDouble()
    }
}

private fun highlightOverspeed(amount: Double) {
    // Change speed limit view to warning color
    speedInfoView.setBackgroundColor(Color.RED)
}

private fun clearOverspeedHighlight() {
    speedInfoView.setBackgroundColor(Color.WHITE)
}
```

### Overspeed Threshold

Add tolerance before warning:

```kotlin
private fun isOverspeed(currentSpeed: Double, speedLimit: Double, tolerancePercent: Double = 10.0): Boolean {
    val threshold = speedLimit * (1 + tolerancePercent / 100)
    return currentSpeed > threshold
}

// Usage
if (isOverspeed(currentSpeed, speedLimitValue, 10.0)) {
    // User is more than 10% over speed limit
    showSpeedingWarning()
}
```

## Speed Unit Conversion

### Display in Preferred Units

```kotlin
import com.mapbox.navigation.base.formatter.UnitType

class SpeedDisplayManager(private val unitType: UnitType) {

    fun formatSpeed(speedMetersPerSecond: Double): String {
        return when (unitType) {
            UnitType.IMPERIAL -> {
                val mph = speedMetersPerSecond * 2.23694
                String.format("%.0f mph", mph)
            }
            UnitType.METRIC -> {
                val kmh = speedMetersPerSecond * 3.6
                String.format("%.0f km/h", kmh)
            }
        }
    }
}

// Usage
val speedManager = SpeedDisplayManager(UnitType.IMPERIAL)
val formattedSpeed = speedManager.formatSpeed(currentSpeed)
```

## Complete Example

```kotlin
class NavigationActivity : AppCompatActivity() {

    private lateinit var mapboxNavigation: MapboxNavigation
    private lateinit var speedInfoApi: MapboxSpeedInfoApi
    private lateinit var speedInfoView: MapboxSpeedInfoView
    private var isOverspeed = false

    private val locationObserver = object : LocationObserver {
        override fun onNewLocationMatcherResult(locationMatcherResult: LocationMatcherResult) {
            updateSpeedInfo(locationMatcherResult)
        }

        override fun onNewRawLocation(rawLocation: Location) {}
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_navigation)

        speedInfoView = findViewById(R.id.speedInfoView)
        speedInfoApi = MapboxSpeedInfoApi()

        mapboxNavigation.registerLocationObserver(locationObserver)
    }

    private fun updateSpeedInfo(locationMatcherResult: LocationMatcherResult) {
        val speedLimit = locationMatcherResult.speedLimit
        val currentSpeed = locationMatcherResult.enhancedLocation.speed

        // Check if speed limit data is available
        if (speedLimit == null || speedLimit.unknown) {
            speedInfoView.visibility = View.GONE
            return
        }

        speedInfoView.visibility = View.VISIBLE

        // Update speed info view
        val speedInfo = speedInfoApi.updatePostedAndCurrentSpeed(speedLimit, currentSpeed)
        speedInfoView.render(speedInfo)

        // Check for overspeeding
        checkOverspeed(currentSpeed, speedLimit)
    }

    private fun checkOverspeed(currentSpeed: Float, speedLimit: SpeedLimit) {
        val speedLimitMps = convertToMetersPerSecond(
            speedLimit.speed ?: 0,
            speedLimit.unit
        )

        val wasOverspeed = isOverspeed
        isOverspeed = currentSpeed > speedLimitMps * 1.1 // 10% tolerance

        if (isOverspeed && !wasOverspeed) {
            // Started speeding
            onSpeedingStarted()
        } else if (!isOverspeed && wasOverspeed) {
            // Stopped speeding
            onSpeedingStopped()
        }
    }

    private fun onSpeedingStarted() {
        speedInfoView.setBackgroundColor(
            ContextCompat.getColor(this, R.color.speedingWarning)
        )
    }

    private fun onSpeedingStopped() {
        speedInfoView.setBackgroundColor(Color.TRANSPARENT)
    }

    private fun convertToMetersPerSecond(speed: Int, unit: String?): Double {
        return when (unit) {
            "mph" -> speed * 0.44704
            "km/h" -> speed / 3.6
            else -> speed.toDouble()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        mapboxNavigation.unregisterLocationObserver(locationObserver)
    }
}
```

## Best Practices

1. **Hide view when no data** - Don't show blank speed limit
2. **Add overspeed tolerance** - 5-10% before warning
3. **Use appropriate colors** - Red for speeding, neutral for normal
4. **Position in corner** - Don't obstruct main navigation view
5. **Test in different regions** - Speed limit availability varies
6. **Respect user preferences** - Allow disabling overspeed warnings
7. **Use enhanced location** - More accurate than raw GPS

## Common Issues

### Speed limit always null
- Mapbox doesn't have data for all roads
- More common on minor/rural roads
- Hide component when no data available

### Inaccurate speed readings
- Use `enhancedLocation.speed` not `rawLocation.speed`
- GPS speed can be noisy
- Consider smoothing speed values

### Wrong units displayed
- Check `speedLimit.unit` field
- Convert appropriately for display
- Respect user's preferred units

## Related Documentation
- [Location Component](location-component.md) - Location tracking
- [Trip Progress](trip-progress.md) - Distance and time display
- [UI Components Overview](ui-components.md) - All UI components

## External Resources
- Speed Limit Guide: https://docs.mapbox.com/android/navigation/guides/ui-components/speed-limit/
- Navigation SDK Examples: https://github.com/mapbox/mapbox-navigation-android-examples
