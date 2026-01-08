# MapboxNavigation Initialization Guide

## Overview
The Navigation SDK requires proper initialization before starting navigation sessions. This guide covers setup, lifecycle management, and best practices.

## Core Setup Steps

1. **Create MapboxNavigation object** - Main entry point for SDK interaction
2. **Start trip session** - Enables data consumption and location processing

## Application-Level Setup

### Configure MapboxNavigationApp

Initialize in your `Application` class's `onCreate()` method:

```kotlin
import android.app.Application
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp

class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        if (!MapboxNavigationApp.isSetup()) {
            MapboxNavigationApp.setup {
                NavigationOptions.Builder(this)
                    .accessToken(getString(R.string.mapbox_access_token))
                    .build()
            }
        }
    }
}
```

### Register Application Class

Update `AndroidManifest.xml`:

```xml
<application
    android:name=".MyApplication"
    android:icon="@mipmap/ic_launcher"
    android:label="@string/app_name">
    <!-- Activities -->
</application>
```

## Lifecycle Management

### Lifecycle Reference Counter

The Navigation SDK uses a lifecycle reference counter approach:
- `MapboxNavigation` instance is created when an attached lifecycle reaches `CREATED` state
- Instance is shared across all attached components
- Automatically destroyed when no lifecycles are attached

### Attaching LifecycleOwners

**Option 1: Activity Approach**
```kotlin
import androidx.appcompat.app.AppCompatActivity
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp

class NavigationActivity : AppCompatActivity() {

    override fun onResume() {
        super.onResume()
        MapboxNavigationApp.attach(this)
    }

    override fun onPause() {
        super.onPause()
        MapboxNavigationApp.detach(this)
    }
}
```

**Option 2: Fragment Approach**
```kotlin
import androidx.fragment.app.Fragment
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp

class NavigationFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        MapboxNavigationApp.attach(viewLifecycleOwner)
        return inflater.inflate(R.layout.fragment_navigation, container, false)
    }
}
```

## Observer Registration

### MapboxNavigationObserver Pattern

Safely register observers with automatic lifecycle management:

```kotlin
import com.mapbox.navigation.core.lifecycle.MapboxNavigationObserver

class MyNavigationObserver : MapboxNavigationObserver {

    override fun onAttached(mapboxNavigation: MapboxNavigation) {
        // Register observers here
        mapboxNavigation.registerRouteProgressObserver(routeProgressObserver)
        mapboxNavigation.registerLocationObserver(locationObserver)
    }

    override fun onDetached(mapboxNavigation: MapboxNavigation) {
        // Unregister observers here
        mapboxNavigation.unregisterRouteProgressObserver(routeProgressObserver)
        mapboxNavigation.unregisterLocationObserver(locationObserver)
    }
}

// Register the observer
MapboxNavigationApp.registerObserver(MyNavigationObserver())
```

**Benefits**:
- Prevents memory leaks
- Automatic registration/unregistration
- Safe observer lifecycle management

## Location Permissions

### Required Permissions

Add to `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

### Runtime Permission Request

```kotlin
import androidx.activity.result.contract.ActivityResultContracts

class NavigationActivity : AppCompatActivity() {

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        if (permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true) {
            startTripSession()
        } else {
            // Handle permission denied
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestLocationPermissions()
    }

    private fun requestLocationPermissions() {
        requestPermissionLauncher.launch(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )
        )
    }
}
```

## Starting the Trip Session

After permissions are granted:

```kotlin
MapboxNavigationApp.current()?.startTripSession()
```

**What this does**:
- Starts foreground service for continuous location updates
- Begins consuming GPS data
- Enables navigation processing

**Stopping the session**:
```kotlin
MapboxNavigationApp.current()?.stopTripSession()
```

## Navigation Options Configuration

### Basic Options

```kotlin
NavigationOptions.Builder(context)
    .accessToken(YOUR_TOKEN)
    .build()
```

### Advanced Options

```kotlin
NavigationOptions.Builder(context)
    .accessToken(YOUR_TOKEN)
    .distanceFormatterOptions(
        DistanceFormatterOptions.Builder(context)
            .unitType(UnitType.IMPERIAL)
            .build()
    )
    .routingTilesOptions(
        RoutingTilesOptions.Builder()
            .tilesVersion("2024-01-01")
            .build()
    )
    .locationOptions(
        LocationOptions.Builder()
            .minTimeMillisBetweenUpdates(500)
            .build()
    )
    .build()
```

## Accessing MapboxNavigation Instance

### From Anywhere
```kotlin
val mapboxNavigation = MapboxNavigationApp.current()
```

### Via ViewModel (Recommended)
```kotlin
class NavigationViewModel : ViewModel() {

    fun getNavigation() = MapboxNavigationApp.current()

    fun setRoute(routes: List<NavigationRoute>) {
        getNavigation()?.setNavigationRoutes(routes)
    }
}
```

## Best Practices

### 1. Singleton Pattern
Use `MapboxNavigationApp` as singleton - don't create multiple `MapboxNavigation` instances manually.

### 2. Lifecycle Management
Always attach/detach lifecycles properly to prevent memory leaks.

### 3. Observer Pattern
Use `MapboxNavigationObserver` for all observer registrations to ensure proper cleanup.

### 4. Foreground Service
The trip session runs as foreground service - ensure proper notification handling.

### 5. Permission Handling
Always check and request location permissions before starting trip session.

## Common Patterns

### Full Activity Example

```kotlin
class NavigationActivity : AppCompatActivity() {

    private val navigationObserver = object : MapboxNavigationObserver {
        override fun onAttached(mapboxNavigation: MapboxNavigation) {
            mapboxNavigation.startTripSession()
        }

        override fun onDetached(mapboxNavigation: MapboxNavigation) {
            mapboxNavigation.stopTripSession()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_navigation)

        MapboxNavigationApp.registerObserver(navigationObserver)
    }

    override fun onResume() {
        super.onResume()
        MapboxNavigationApp.attach(this)
    }

    override fun onPause() {
        super.onPause()
        MapboxNavigationApp.detach(this)
    }

    override fun onDestroy() {
        super.onDestroy()
        MapboxNavigationApp.unregisterObserver(navigationObserver)
    }
}
```

## Troubleshooting

### Issue: MapboxNavigation is null
**Cause**: Lifecycle not attached or app not initialized
**Solution**: Ensure `MapboxNavigationApp.setup()` called in Application.onCreate() and lifecycle attached

### Issue: Location updates not working
**Cause**: Trip session not started or permissions not granted
**Solution**: Call `startTripSession()` after permissions granted

### Issue: Memory leaks
**Cause**: Observers not unregistered
**Solution**: Use `MapboxNavigationObserver` pattern for automatic cleanup

## Documentation
- Navigation SDK Overview: docs/mapbox/navigation/android-navigation-overview.md
- UI Components: docs/mapbox/navigation/ui-components.md
- Installation: docs/mapbox/navigation/installation-setup.md
