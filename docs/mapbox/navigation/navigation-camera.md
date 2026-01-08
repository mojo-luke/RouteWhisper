# Navigation Camera Component

## Overview
The Navigation Camera automatically frames the user's location and upcoming route during navigation. It combines user location data with active route geometry to continuously track movement and frame upcoming maneuvers.

## Core Architecture

The system consists of two main components:

1. **MapboxNavigationViewportDataSource** - Generates map camera targets
2. **NavigationCamera** - Consumes and executes camera targets to control camera behavior

## Initialization

### Step 1: Create Viewport Data Source

```kotlin
import com.mapbox.navigation.ui.maps.camera.data.MapboxNavigationViewportDataSource

val viewportDataSource = MapboxNavigationViewportDataSource(mapboxMap)
```

### Step 2: Create Navigation Camera

```kotlin
import com.mapbox.navigation.ui.maps.camera.NavigationCamera

val navigationCamera = NavigationCamera(
    mapboxMap,
    binding.mapView.camera,
    viewportDataSource
)
```

## Providing Data to Camera

The viewport data source requires three types of updates:

### 1. Routes
Use `RoutesObserver` to detect route changes:

```kotlin
val routesObserver = RoutesObserver { routeUpdateResult ->
    if (routeUpdateResult.navigationRoutes.isNotEmpty()) {
        viewportDataSource.onRouteChanged(routeUpdateResult.navigationRoutes.first())
        viewportDataSource.evaluate()
    }
}

mapboxNavigation.registerRoutesObserver(routesObserver)
```

### 2. Location
Use `LocationObserver` for enhanced location updates:

```kotlin
val locationObserver = object : LocationObserver {
    override fun onNewLocationMatcherResult(locationMatcherResult: LocationMatcherResult) {
        viewportDataSource.onLocationChanged(locationMatcherResult.enhancedLocation)
        viewportDataSource.evaluate()
    }

    override fun onNewRawLocation(rawLocation: Location) {
        // Optional: handle raw location
    }
}

mapboxNavigation.registerLocationObserver(locationObserver)
```

### 3. Route Progress
Use `RouteProgressObserver` for route progress changes:

```kotlin
val progressObserver = RouteProgressObserver { routeProgress ->
    viewportDataSource.onRouteProgressChanged(routeProgress)
    viewportDataSource.evaluate()
}

mapboxNavigation.registerRouteProgressObserver(progressObserver)
```

**Important**: Always call `evaluate()` after providing data to regenerate camera targets.

## Camera States

NavigationCamera maintains these states:

| State | Description |
|-------|-------------|
| `IDLE` | Camera is inactive |
| `TRANSITION_TO_FOLLOWING` | Animating to following mode |
| `FOLLOWING` | User-centric tracking mode |
| `TRANSITION_TO_OVERVIEW` | Animating to overview mode |
| `OVERVIEW` | Full route visibility mode |

### Requesting State Changes

```kotlin
// Switch to following mode (track user during navigation)
navigationCamera.requestNavigationCameraToFollowing()

// Switch to overview mode (show entire route)
navigationCamera.requestNavigationCameraToOverview()

// Disable navigation camera (allow manual camera control)
navigationCamera.requestNavigationCameraToIdle()
```

## Camera Modes Explained

### Following Mode
- **Purpose**: Track user location during active navigation
- **Behavior**:
  - User positioned according to focal point settings
  - Camera continuously updates to show upcoming maneuvers
  - Automatic zoom and tilt adjustments
  - Smooth transitions as route progresses

**Use when**: User is actively navigating

### Overview Mode
- **Purpose**: Display entire route or significant remaining portion
- **Behavior**:
  - Shows full route geometry
  - Zooms out to fit route within frame
  - Useful for route preview or understanding full journey
  - Can show remaining route segment during navigation

**Use when**: User wants to see full route layout

### Idle Mode
- **Purpose**: Disable automatic camera control
- **Behavior**:
  - No automatic camera updates
  - User can manually pan/zoom/tilt map
  - Useful for exploring map freely

**Use when**: User wants manual map control

## Customization Options

### Frame Padding

Control spacing around framed elements to avoid UI overlap:

```kotlin
val options = MapboxNavigationViewportDataSourceOptions.Builder()
    .followingFrameOptions(
        FollowingFrameOptions.Builder()
            .defaultPadding(EdgeInsets(100.0, 50.0, 150.0, 50.0)) // top, left, bottom, right
            .build()
    )
    .overviewFrameOptions(
        OverviewFrameOptions.Builder()
            .defaultPadding(EdgeInsets(150.0, 50.0, 150.0, 50.0))
            .build()
    )
    .build()

viewportDataSource = MapboxNavigationViewportDataSource(mapboxMap, options)
```

### Focal Point

Position the user location indicator within the following frame:

```kotlin
val options = MapboxNavigationViewportDataSourceOptions.Builder()
    .followingFrameOptions(
        FollowingFrameOptions.Builder()
            .focalPoint(Point(0.5, 0.75)) // x: 0.0-1.0, y: 0.0-1.0
            // 0.5, 0.75 = centered horizontally, in lower quarter vertically
            .build()
    )
    .build()
```

**Focal point values**:
- `x`: 0.0 (left) to 1.0 (right)
- `y`: 0.0 (top) to 1.0 (bottom)
- Default: `(0.5, 0.5)` - center of screen

**Common settings**:
- `(0.5, 0.7)` - Lower third, good for seeing ahead
- `(0.5, 0.5)` - Center
- `(0.5, 0.3)` - Upper third

### Pitch and Zoom

Control camera viewing angle and zoom levels:

```kotlin
val options = MapboxNavigationViewportDataSourceOptions.Builder()
    .followingFrameOptions(
        FollowingFrameOptions.Builder()
            .pitch(45.0) // Camera tilt angle (0-60 degrees)
            .minZoom(10.0)
            .maxZoom(18.0)
            .build()
    )
    .overviewFrameOptions(
        OverviewFrameOptions.Builder()
            .pitch(0.0) // Flat view for overview
            .build()
    )
    .build()
```

**Pitch**:
- `0.0` - Top-down view (flat)
- `45.0` - Angled view (good for 3D buildings)
- `60.0` - Maximum tilt

## Free-Drive Navigation

When no route exists, the system maintains constant zoom while tracking location:

```kotlin
// Camera automatically switches to free-drive mode when route cleared
mapboxNavigation.setNavigationRoutes(emptyList())
```

**Free-drive behavior**:
- Follows user location
- Maintains constant zoom level
- No route-specific framing
- Useful for "explore mode" or before route selection

## Complete Example

```kotlin
class NavigationActivity : AppCompatActivity() {

    private lateinit var mapboxNavigation: MapboxNavigation
    private lateinit var viewportDataSource: MapboxNavigationViewportDataSource
    private lateinit var navigationCamera: NavigationCamera

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_navigation)

        val mapView = findViewById<MapView>(R.id.mapView)
        mapView.mapboxMap.loadStyle(Style.MAPBOX_STREETS) { style ->
            initializeCamera(mapView.mapboxMap, mapView.camera)
        }
    }

    private fun initializeCamera(mapboxMap: MapboxMap, camera: Camera) {
        // 1. Create viewport data source with options
        val options = MapboxNavigationViewportDataSourceOptions.Builder()
            .followingFrameOptions(
                FollowingFrameOptions.Builder()
                    .defaultPadding(EdgeInsets(100.0, 50.0, 150.0, 50.0))
                    .focalPoint(Point(0.5, 0.75))
                    .pitch(45.0)
                    .build()
            )
            .overviewFrameOptions(
                OverviewFrameOptions.Builder()
                    .defaultPadding(EdgeInsets(150.0, 50.0, 150.0, 50.0))
                    .pitch(0.0)
                    .build()
            )
            .build()

        viewportDataSource = MapboxNavigationViewportDataSource(mapboxMap, options)

        // 2. Create navigation camera
        navigationCamera = NavigationCamera(mapboxMap, camera, viewportDataSource)

        // 3. Register observers
        registerObservers()

        // 4. Start in following mode
        navigationCamera.requestNavigationCameraToFollowing()
    }

    private fun registerObservers() {
        mapboxNavigation.registerRoutesObserver { routeUpdateResult ->
            if (routeUpdateResult.navigationRoutes.isNotEmpty()) {
                viewportDataSource.onRouteChanged(routeUpdateResult.navigationRoutes.first())
                viewportDataSource.evaluate()
            }
        }

        mapboxNavigation.registerLocationObserver(object : LocationObserver {
            override fun onNewLocationMatcherResult(locationMatcherResult: LocationMatcherResult) {
                viewportDataSource.onLocationChanged(locationMatcherResult.enhancedLocation)
                viewportDataSource.evaluate()
            }

            override fun onNewRawLocation(rawLocation: Location) {}
        })

        mapboxNavigation.registerRouteProgressObserver { routeProgress ->
            viewportDataSource.onRouteProgressChanged(routeProgress)
            viewportDataSource.evaluate()
        }
    }

    fun onOverviewButtonClick() {
        navigationCamera.requestNavigationCameraToOverview()
    }

    fun onRecenterButtonClick() {
        navigationCamera.requestNavigationCameraToFollowing()
    }
}
```

## Debugging

Enable debug overlay to visualize padding and framed geometries:

```kotlin
import com.mapbox.navigation.ui.maps.camera.utils.MapboxNavigationViewportDataSourceDebugger

val debugger = MapboxNavigationViewportDataSourceDebugger(
    context,
    mapboxMap,
    viewportDataSource
)

// Show debug overlay
debugger.enabled = true
```

**Debug overlay shows**:
- Frame padding boundaries
- Framed route geometry
- Focal point position
- Camera targets

## Best Practices

1. **Always call evaluate()** after providing data updates
2. **Use appropriate padding** to avoid UI element overlap (buttons, instructions, etc.)
3. **Set focal point lower** (e.g., 0.7-0.8) to show more route ahead
4. **Start in following mode** when navigation begins
5. **Switch to overview** when user requests route preview
6. **Return to idle** when user manually interacts with map
7. **Unregister observers** in onDestroy() to prevent memory leaks

## Common Issues

### Camera not updating
- Ensure `evaluate()` called after data updates
- Check observers are properly registered
- Verify camera is not in IDLE state

### User position off-center
- Adjust focal point in FollowingFrameOptions
- Check padding values aren't pushing position off-screen

### Route not fully visible in overview
- Increase overview padding
- Check route geometry is valid

## Related Documentation
- [Initialization Guide](initialization.md) - MapboxNavigation setup
- [Route Line Component](route-line.md) - Rendering routes on map
- [UI Components Overview](ui-components.md) - All UI components

## External Resources
- Navigation Camera Guide: https://docs.mapbox.com/android/navigation/guides/ui-components/camera/
- Camera API Reference: https://docs.mapbox.com/android/navigation/api/
