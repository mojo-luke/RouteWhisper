# Location Component

## Overview
The Location Component displays the user's current location on the map with a location puck (indicator). It shows position, bearing (direction), and accuracy.

## Basic Setup

### Step 1: Enable Location Component

```kotlin
import com.mapbox.maps.plugin.locationcomponent.location

mapView.location.updateSettings {
    enabled = true
    pulsingEnabled = true // Animated pulsing effect
}
```

### Step 2: Request Location Permissions

```kotlin
import android.Manifest
import androidx.activity.result.contract.ActivityResultContracts

class NavigationActivity : AppCompatActivity() {

    private val locationPermissionRequest = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        when {
            permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true -> {
                enableLocationComponent()
            }
            permissions[Manifest.permission.ACCESS_COARSE_LOCATION] == true -> {
                enableLocationComponent()
            }
            else -> {
                // Permission denied
                Toast.makeText(this, "Location permission required", Toast.LENGTH_SHORT).show()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestLocationPermissions()
    }

    private fun requestLocationPermissions() {
        locationPermissionRequest.launch(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )
        )
    }

    private fun enableLocationComponent() {
        mapView.location.updateSettings {
            enabled = true
            pulsingEnabled = true
        }
    }
}
```

## Location Puck Styles

### 2D Puck (Default)

Simple 2D indicator:

```kotlin
import com.mapbox.maps.plugin.locationcomponent.createDefault2DPuck

mapView.location.updateSettings {
    enabled = true
    locationPuck = createDefault2DPuck(withBearing = true)
}
```

### 3D Puck

3D model puck (arrow or custom model):

```kotlin
import com.mapbox.maps.plugin.locationcomponent.generated.LocationComponentSettings

mapView.location.updateSettings {
    enabled = true
    locationPuck = LocationPuck3D(
        modelUri = "asset://your-model.gltf", // Custom 3D model
        modelScale = listOf(1f, 1f, 1f),
        modelRotation = listOf(0f, 0f, 0f)
    )
}
```

### Custom 2D Puck

Customize appearance with your own images:

```kotlin
import com.mapbox.maps.plugin.locationcomponent.LocationPuck2D

mapView.location.updateSettings {
    enabled = true
    locationPuck = LocationPuck2D(
        topImage = ContextCompat.getDrawable(this, R.drawable.custom_location_icon),
        bearingImage = ContextCompat.getDrawable(this, R.drawable.custom_bearing_icon),
        shadowImage = ContextCompat.getDrawable(this, R.drawable.location_shadow),
        scaleExpression = "interpolate" // Size based on zoom
    )
}
```

## Customization Options

### Accuracy Circle

Show accuracy radius around location puck:

```kotlin
mapView.location.updateSettings {
    enabled = true
    showAccuracyRing = true
    accuracyRingColor = ColorUtils.colorToRgbaString(Color.BLUE)
    accuracyRingBorderColor = ColorUtils.colorToRgbaString(Color.WHITE)
}
```

### Bearing Indicator

Show direction user is facing:

```kotlin
mapView.location.updateSettings {
    enabled = true
    locationPuck = createDefault2DPuck(withBearing = true)
    puckBearingEnabled = true // Enable bearing rotation
}
```

### Pulsing Effect

Animated pulsing for better visibility:

```kotlin
mapView.location.updateSettings {
    enabled = true
    pulsingEnabled = true
    pulsingColor = ColorUtils.colorToRgbaString(Color.BLUE)
    pulsingMaxRadius = 20f // Maximum radius in pixels
}
```

## Location Tracking Modes

### Free Mode (Default)

Location updates but camera doesn't follow:

```kotlin
mapView.location.updateSettings {
    enabled = true
    // Camera controlled manually
}
```

### Following Mode

Camera automatically follows user location:

```kotlin
import com.mapbox.maps.CameraOptions
import com.mapbox.geojson.Point

// Get current location
val location = mapView.location.lastKnownLocation

location?.let {
    val cameraOptions = CameraOptions.Builder()
        .center(Point.fromLngLat(it.longitude, it.latitude))
        .zoom(16.0)
        .build()

    mapView.camera.easeTo(cameraOptions)
}

// Listen for location updates
mapView.location.addOnIndicatorPositionChangedListener { point ->
    // Optionally update camera on each location change
    val cameraOptions = CameraOptions.Builder()
        .center(point)
        .build()

    mapView.camera.easeTo(cameraOptions)
}
```

## Accessing Location Data

### Get Last Known Location

```kotlin
val lastLocation = mapView.location.lastKnownLocation

lastLocation?.let { location ->
    val latitude = location.latitude
    val longitude = location.longitude
    val accuracy = location.accuracy // meters
    val bearing = location.bearing // degrees
    val speed = location.speed // meters/second

    Log.d("Location", "Current position: $latitude, $longitude")
}
```

### Listen for Location Updates

```kotlin
import com.mapbox.maps.plugin.locationcomponent.OnIndicatorPositionChangedListener

val positionListener = OnIndicatorPositionChangedListener { point ->
    Log.d("Location", "New position: ${point.latitude()}, ${point.longitude()}")
}

mapView.location.addOnIndicatorPositionChangedListener(positionListener)

// Remove listener when done
override fun onDestroy() {
    super.onDestroy()
    mapView.location.removeOnIndicatorPositionChangedListener(positionListener)
}
```

### Listen for Bearing Changes

```kotlin
import com.mapbox.maps.plugin.locationcomponent.OnIndicatorBearingChangedListener

val bearingListener = OnIndicatorBearingChangedListener { bearing ->
    Log.d("Location", "New bearing: $bearing degrees")
}

mapView.location.addOnIndicatorBearingChangedListener(bearingListener)
```

## Integration with Navigation

When using Navigation SDK, location is automatically managed:

```kotlin
// Navigation SDK automatically updates location component
// Just enable it
mapView.location.updateSettings {
    enabled = true
    pulsingEnabled = true
}

// Location puck will follow enhanced location from Navigation SDK
// Enhanced location includes GPS filtering and dead reckoning
```

## Complete Example

```kotlin
class MapActivity : AppCompatActivity() {

    private lateinit var mapView: MapView

    private val locationPermissionRequest = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        if (permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true) {
            setupLocationComponent()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_map)

        mapView = findViewById(R.id.mapView)
        mapView.mapboxMap.loadStyle(Style.MAPBOX_STREETS) {
            requestLocationPermissions()
        }
    }

    private fun requestLocationPermissions() {
        locationPermissionRequest.launch(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )
        )
    }

    private fun setupLocationComponent() {
        mapView.location.updateSettings {
            enabled = true
            pulsingEnabled = true
            showAccuracyRing = true
            locationPuck = createDefault2DPuck(withBearing = true)
        }

        // Listen for location updates
        mapView.location.addOnIndicatorPositionChangedListener { point ->
            Log.d("Location", "Position: ${point.latitude()}, ${point.longitude()}")
        }

        // Center camera on user location
        centerOnUserLocation()
    }

    private fun centerOnUserLocation() {
        val location = mapView.location.lastKnownLocation

        location?.let {
            val cameraOptions = CameraOptions.Builder()
                .center(Point.fromLngLat(it.longitude, it.latitude))
                .zoom(16.0)
                .build()

            mapView.camera.flyTo(cameraOptions)
        }
    }
}
```

## Best Practices

1. **Always request permissions** before enabling location
2. **Use pulsing effect** for better visibility
3. **Show accuracy ring** when accuracy is important
4. **Enable bearing** for directional context
5. **Handle permission denial** gracefully
6. **Remove listeners** in onDestroy() to prevent leaks
7. **Use Navigation SDK location** when navigating (enhanced accuracy)

## Common Issues

### Location puck not showing
- Check location permissions granted
- Ensure `enabled = true` in settings
- Verify GPS is enabled on device
- Check location services are available

### Inaccurate location
- Indoor locations are less accurate
- GPS signal may be weak
- Use Navigation SDK for enhanced location during navigation

### Location not updating
- Check listeners are registered
- Verify trip session started (for Navigation SDK)
- Ensure app has location permissions

## Related Documentation
- [Navigation Camera](navigation-camera.md) - Camera following location
- [Initialization Guide](initialization.md) - Location permissions setup
- [Camera Controls](../maps/camera-controls.md) - Camera positioning

## External Resources
- Location Component Guide: https://docs.mapbox.com/android/maps/guides/location/location-component/
- Maps SDK Location: https://docs.mapbox.com/android/maps/guides/location/
