# Maps SDK Camera Controls

## Overview
The camera represents the user's viewpoint above the map. The Mapbox Maps SDK for Android provides complete control over camera positioning, including zoom, bearing (rotation), pitch (tilt), and center coordinates.

## Camera Position Parameters

### Center
Geographic coordinates where the camera is pointing.

```kotlin
val center = Point.fromLngLat(-122.4194, 37.7749)
```

**Format**: `Point.fromLngLat(longitude, latitude)`
**Important**: Longitude first, then latitude!

### Zoom
Zoom level of the map (0 = world view, 22 = building level).

```kotlin
val zoom = 15.0
```

**Zoom levels**:
- `0-3` - World/continent view
- `4-6` - Country view
- `7-10` - City view
- `11-14` - Neighborhood view
- `15-18` - Street view
- `19-22` - Building level

### Bearing
Map rotation in degrees (0-360, where 0 is north).

```kotlin
val bearing = 90.0 // Map rotated 90° clockwise (east at top)
```

**Values**:
- `0.0` - North at top (default)
- `90.0` - East at top
- `180.0` - South at top
- `270.0` - West at top

### Pitch
Camera tilt angle in degrees (0-60).

```kotlin
val pitch = 45.0 // 45° tilt for 3D view
```

**Values**:
- `0.0` - Top-down view (flat)
- `30.0` - Slight tilt
- `45.0` - Medium tilt (good for 3D buildings)
- `60.0` - Maximum tilt

## Setting Camera Position

### Instant Camera Movement

```kotlin
import com.mapbox.maps.CameraOptions

val cameraOptions = CameraOptions.Builder()
    .center(Point.fromLngLat(-122.4194, 37.7749))
    .zoom(15.0)
    .bearing(0.0)
    .pitch(45.0)
    .build()

mapView.mapboxMap.setCamera(cameraOptions)
```

### Animated Camera Movement

```kotlin
import com.mapbox.maps.plugin.animation.MapAnimationOptions

val cameraOptions = CameraOptions.Builder()
    .center(Point.fromLngLat(-122.4194, 37.7749))
    .zoom(15.0)
    .bearing(0.0)
    .pitch(45.0)
    .build()

val animationOptions = MapAnimationOptions.Builder()
    .duration(2000) // 2 seconds
    .build()

mapView.camera.easeTo(cameraOptions, animationOptions)
```

## Camera Animation Types

### easeTo()
Smooth animation with easing function.

```kotlin
mapView.camera.easeTo(
    cameraOptions,
    MapAnimationOptions.Builder()
        .duration(2000)
        .build()
)
```

**Use for**: Gentle camera movements, UI transitions

### flyTo()
Dramatic "fly over" animation with arc.

```kotlin
mapView.camera.flyTo(
    cameraOptions,
    MapAnimationOptions.Builder()
        .duration(3000)
        .build()
)
```

**Use for**: Long-distance camera movements, dramatic effect

### moveTo()
Instant camera movement without animation.

```kotlin
mapView.camera.moveTo(cameraOptions)
```

**Use for**: Initial positioning, quick updates

## Getting Current Camera Position

```kotlin
val currentCamera = mapView.mapboxMap.cameraState

val center = currentCamera.center // Point
val zoom = currentCamera.zoom // Double
val bearing = currentCamera.bearing // Double
val pitch = currentCamera.pitch // Double
```

## Camera Padding

Add padding to shift effective camera center (useful for UI overlays):

```kotlin
import com.mapbox.maps.EdgeInsets

val cameraOptions = CameraOptions.Builder()
    .center(Point.fromLngLat(-122.4194, 37.7749))
    .zoom(15.0)
    .padding(EdgeInsets(100.0, 50.0, 150.0, 50.0)) // top, left, bottom, right
    .build()

mapView.mapboxMap.setCamera(cameraOptions)
```

**Effect**: Map content avoids padded areas, useful for:
- Centering with bottom instruction banner
- Avoiding top navigation bar
- Accounting for side panels

## Restricting Camera

### Zoom Restrictions

```kotlin
mapView.mapboxMap.setBounds(
    CameraBoundsOptions.Builder()
        .minZoom(10.0)
        .maxZoom(18.0)
        .build()
)
```

### Geographic Restrictions

Limit map to specific region:

```kotlin
import com.mapbox.geojson.BoundingBox

val bounds = BoundingBox.fromPoints(
    Point.fromLngLat(-122.5, 37.7), // Southwest
    Point.fromLngLat(-122.3, 37.8)  // Northeast
)

mapView.mapboxMap.setBounds(
    CameraBoundsOptions.Builder()
        .bounds(bounds)
        .build()
)
```

**Use for**: Restricting map to specific area (city, campus, etc.)

## Camera Change Listeners

### Listen for Camera Changes

```kotlin
mapView.mapboxMap.subscribeCameraChanged { cameraChangedEvent ->
    val newCenter = cameraChangedEvent.cameraState.center
    val newZoom = cameraChangedEvent.cameraState.zoom

    Log.d("Camera", "Camera moved to $newCenter at zoom $newZoom")
}
```

### Listen for User Interaction

```kotlin
import com.mapbox.maps.plugin.gestures.addOnMapClickListener

mapView.mapboxMap.addOnMapClickListener { point ->
    Log.d("Camera", "User clicked at $point")
    true // Return true if handled
}
```

## Common Camera Patterns

### Follow User Location

```kotlin
import com.mapbox.maps.plugin.locationcomponent.location

// Enable location component first
mapView.location.updateSettings {
    enabled = true
    pulsingEnabled = true
}

// Then center camera on user
val userLocation = mapView.location.locationPuck.lastLocation
userLocation?.let {
    val cameraOptions = CameraOptions.Builder()
        .center(Point.fromLngLat(it.longitude, it.latitude))
        .zoom(16.0)
        .build()

    mapView.camera.easeTo(cameraOptions)
}
```

### Fit Bounds to Route

```kotlin
import com.mapbox.geojson.LineString

fun fitCameraToRoute(routeGeometry: LineString) {
    val coordinates = routeGeometry.coordinates()

    if (coordinates.isEmpty()) return

    // Calculate bounding box
    var minLng = coordinates[0].longitude()
    var maxLng = coordinates[0].longitude()
    var minLat = coordinates[0].latitude()
    var maxLat = coordinates[0].latitude()

    coordinates.forEach { point ->
        minLng = minOf(minLng, point.longitude())
        maxLng = maxOf(maxLng, point.longitude())
        minLat = minOf(minLat, point.latitude())
        maxLat = maxOf(maxLat, point.latitude())
    }

    val bounds = BoundingBox.fromPoints(
        Point.fromLngLat(minLng, minLat),
        Point.fromLngLat(maxLng, maxLat)
    )

    val cameraOptions = mapView.mapboxMap.cameraForCoordinateBounds(
        bounds,
        EdgeInsets(100.0, 50.0, 100.0, 50.0) // Padding
    )

    mapView.camera.easeTo(cameraOptions)
}
```

### Zoom In/Out Buttons

```kotlin
fun zoomIn() {
    val currentZoom = mapView.mapboxMap.cameraState.zoom
    val cameraOptions = CameraOptions.Builder()
        .zoom(currentZoom + 1)
        .build()

    mapView.camera.easeTo(
        cameraOptions,
        MapAnimationOptions.Builder().duration(300).build()
    )
}

fun zoomOut() {
    val currentZoom = mapView.mapboxMap.cameraState.zoom
    val cameraOptions = CameraOptions.Builder()
        .zoom(currentZoom - 1)
        .build()

    mapView.camera.easeTo(
        cameraOptions,
        MapAnimationOptions.Builder().duration(300).build()
    )
}
```

### Rotate to North

```kotlin
fun resetBearing() {
    val cameraOptions = CameraOptions.Builder()
        .bearing(0.0) // North at top
        .build()

    mapView.camera.easeTo(
        cameraOptions,
        MapAnimationOptions.Builder().duration(500).build()
    )
}
```

## Complete Example

```kotlin
class MapActivity : AppCompatActivity() {

    private lateinit var mapView: MapView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_map)

        mapView = findViewById(R.id.mapView)
        mapView.mapboxMap.loadStyle(Style.MAPBOX_STREETS) { style ->
            // Initial camera position
            val initialCamera = CameraOptions.Builder()
                .center(Point.fromLngLat(-122.4194, 37.7749))
                .zoom(13.0)
                .bearing(0.0)
                .pitch(0.0)
                .build()

            mapView.mapboxMap.setCamera(initialCamera)

            // Add click listener to animate to clicked location
            mapView.mapboxMap.addOnMapClickListener { point ->
                animateCameraToPoint(point)
                true
            }
        }
    }

    private fun animateCameraToPoint(point: Point) {
        val cameraOptions = CameraOptions.Builder()
            .center(point)
            .zoom(16.0)
            .pitch(45.0)
            .build()

        mapView.camera.flyTo(
            cameraOptions,
            MapAnimationOptions.Builder()
                .duration(2000)
                .build()
        )
    }
}
```

## Best Practices

1. **Use animations** for better UX (easeTo/flyTo instead of moveTo)
2. **Add padding** when UI elements overlap map
3. **Limit zoom/bounds** for focused applications
4. **Handle orientation changes** - save/restore camera state
5. **Use flyTo** for long distances, **easeTo** for short movements
6. **Remember: longitude first** when creating Points
7. **Test on different screen sizes** - camera framing varies

## Common Issues

### Camera not updating
- Ensure style is loaded before setting camera
- Check CameraOptions are valid (coordinates in range)

### Jittery animations
- Reduce animation frequency
- Use appropriate duration (500-2000ms typical)

### Map not centered correctly with UI overlay
- Use padding in CameraOptions to account for UI elements

## Related Documentation
- [Navigation Camera](../navigation/navigation-camera.md) - Automatic camera for navigation
- [Android Maps Overview](android-maps-overview.md) - Maps SDK features

## External Resources
- Maps SDK Camera Guide: https://docs.mapbox.com/android/maps/guides/camera-and-animation/
- Camera API Reference: https://docs.mapbox.com/android/maps/api/
