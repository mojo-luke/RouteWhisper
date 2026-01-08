# Mapbox Documentation Library

> **Purpose**: This local documentation library provides quick reference to Mapbox features and APIs. Always consult these docs BEFORE building custom solutions to check if Mapbox already provides what you need.

## ⚡ IMPORTANT: Token-Efficient Usage

**DON'T read all 21 files (150K tokens)!**

### Three Ways to Use This Library:

1. **FASTEST**: Read **[QUICK_INDEX.md](QUICK_INDEX.md)** (1.5K tokens)
   - Ultra-compact task→doc mapping
   - Find the right doc in seconds

2. **DETAILED**: Read **[USAGE_GUIDE.md](USAGE_GUIDE.md)** (3K tokens)
   - Complete token management strategy
   - Decision trees, examples, cost comparisons

3. **COMPREHENSIVE**: Read README.md (this file) (5K tokens)
   - Full feature overview
   - Use cases, workflows, gotchas

**Recommended workflow**:
1. Read QUICK_INDEX.md → find your doc (1.5K)
2. Read that ONE specific doc → get info (5-7K)
3. **Total: 6.5-8.5K tokens instead of 150K** (94% savings)

## Quick Navigation

### Core Navigation (Android)
- **[Android Navigation Overview](navigation/android-navigation-overview.md)** - Features, system requirements, key capabilities
- **[Installation & Setup](navigation/installation-setup.md)** - Step-by-step installation guide, token configuration, common issues
- **[Initialization Guide](navigation/initialization.md)** - MapboxNavigation setup, lifecycle management, observer patterns
- **[Navigation Camera](navigation/navigation-camera.md)** - Automatic camera framing, following/overview modes, customization
- **[Route Line Component](navigation/route-line.md)** - Rendering routes, traffic visualization, alternative routes
- **[Voice Instructions](navigation/voice-instructions.md)** - Audio guidance, speech synthesis, language support
- **[Maneuver Instructions](navigation/maneuver-instructions.md)** - Turn-by-turn visual guidance, lane guidance, road shields
- **[Trip Progress](navigation/trip-progress.md)** - ETA, distance remaining, time remaining display
- **[Location Component](navigation/location-component.md)** - User location display, location puck, accuracy circle
- **[Rerouting](navigation/rerouting.md)** - Automatic rerouting, off-route detection, manual rerouting
- **[Speed Limit](navigation/speed-limit.md)** - Speed limit display, overspeed detection
- **[Offline Navigation](navigation/offline-navigation.md)** - Downloading tiles, offline routing
- **[Foreground Service](navigation/foreground-service.md)** - Background navigation, notification management
- **[Building Highlights](navigation/building-highlights.md)** - 3D building extrusion at destinations
- **[Waypoints](navigation/waypoints.md)** - Multi-stop navigation, waypoint management
- **[UI Components](navigation/ui-components.md)** - 15 pre-built components overview

### Maps SDKs
- **[Android Maps SDK](maps/android-maps-overview.md)** - MapView, layers, sources, camera controls
- **[Camera Controls](maps/camera-controls.md)** - Camera positioning, zoom, bearing, pitch, animations
- **[Flutter Maps SDK](flutter/flutter-maps-overview.md)** - Cross-platform maps, limitations, conflicts with native SDKs

### Search
- **[Android Search SDK](search/android-search-overview.md)** - Place autocomplete, category search, address autofill

### APIs
- **[Directions API](apis/directions-api.md)** - Route calculation, turn-by-turn instructions, EV routing

### Reference
- **[Token Scopes](reference/token-scopes.md)** - Public vs secret tokens, permissions, security best practices

### Troubleshooting
- **[Troubleshooting Guide](troubleshooting.md)** - Common errors, solutions, debugging commands

---

## Documentation by Use Case

### Building a Navigation App

1. **Start here**: [Installation & Setup](navigation/installation-setup.md)
   - Configure Maven access
   - Add dependencies
   - Set up tokens

2. **Initialize SDK**: [Initialization Guide](navigation/initialization.md)
   - Application setup
   - Lifecycle management
   - Location permissions

3. **Choose UI approach**:
   - **Option A**: Use [Drop-in UI](navigation/ui-components.md) (fastest, less control)
   - **Option B**: Pick [individual components](navigation/ui-components.md) (more work, full control)

4. **Request routes**: [Directions API](apis/directions-api.md)
   - Routing profiles (driving-traffic, walking, cycling)
   - Route alternatives
   - Voice instructions

5. **Handle errors**: [Troubleshooting Guide](troubleshooting.md)

### Displaying Maps Only

1. **Choose platform**:
   - Android native: [Android Maps SDK](maps/android-maps-overview.md)
   - Cross-platform: [Flutter Maps SDK](flutter/flutter-maps-overview.md)

2. **Add search**: [Search SDK](search/android-search-overview.md)
   - Place autocomplete
   - Category search (POIs)

3. **Configure tokens**: [Token Scopes](reference/token-scopes.md)

### Flutter + Native Navigation

**Important**: Cannot use `mapbox_maps_flutter` with native Navigation SDK due to conflicts.

**Recommended approach**:
1. Remove Flutter Maps plugin from `pubspec.yaml`
2. Use native Navigation SDK in Kotlin ([Installation](navigation/installation-setup.md))
3. Bridge with method channels (see [Flutter Maps limitations](flutter/flutter-maps-overview.md))
4. Keep Flutter UI minimal (launcher only)

---

## Key Concepts

### Token Types

| Type | Prefix | Usage | Where |
|------|--------|-------|-------|
| **Public** | `pk.` | Runtime map/navigation | Mobile apps, web apps |
| **Secret** | `sk.` | Downloads, API management | gradle.properties, CI/CD |
| **Temporary** | `tk.` | Short-lived access | Programmatic use |

See [Token Scopes](reference/token-scopes.md) for details.

### SDK Compatibility

| SDK | Version | NDK | Platform |
|-----|---------|-----|----------|
| Navigation | v3.18.0-beta.1 | 23 or 27 | Android |
| Maps | v11.x.x | 23 or 27 | Android |
| Search | v2.17.1 | 23 or 27 | Android |
| Flutter Maps | v2.17.0 | - | Flutter (iOS/Android) |

**Important**: Flutter Maps SDK conflicts with native Navigation SDK - choose one.

### NDK Variants

- **NDK 23** (default): Standard artifacts (`android:3.10.0`)
- **NDK 27**: 16KB page size support (artifact: `android-ndk27:3.10.0` or specify `ndkVersion` in build.gradle)

For Navigation SDK 3.10.0, use standard `android:3.10.0` package and set `ndkVersion` in build.gradle.

### Routing Profiles

| Profile | Use Case | Features |
|---------|----------|----------|
| `mapbox/driving-traffic` | Cars (default) | Real-time traffic, incidents |
| `mapbox/driving` | Cars (fast) | Prefers highways, no traffic |
| `mapbox/walking` | Pedestrians | Sidewalks, trails |
| `mapbox/cycling` | Bicycles | Bike lanes, avoids highways |

See [Directions API](apis/directions-api.md) for details.

---

## Common Workflows

### Workflow 1: Request a Route

```kotlin
import com.mapbox.api.directions.v5.MapboxDirections
import com.mapbox.geojson.Point

val origin = Point.fromLngLat(-122.4194, 37.7749)
val destination = Point.fromLngLat(-118.2437, 34.0522)

val directions = MapboxDirections.builder()
    .accessToken(YOUR_TOKEN)
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
        // Use routes for navigation
    }
})
```

### Workflow 2: Start Navigation

```kotlin
// Set routes to MapboxNavigation
val navigationRoutes = routes.map { it.toNavigationRoute() }
MapboxNavigationApp.current()?.setNavigationRoutes(navigationRoutes)

// Start trip session
MapboxNavigationApp.current()?.startTripSession()
```

### Workflow 3: Search for Place

```kotlin
import com.mapbox.search.SearchEngine

val searchEngine = SearchEngine.createSearchEngine(
    SearchEngineSettings(accessToken = YOUR_TOKEN)
)

searchEngine.search("coffee shop") { response ->
    response.onValue { results ->
        results.forEach { result ->
            println("${result.name} - ${result.address}")
        }
    }
}
```

---

## Pre-Built UI Components

The Navigation SDK provides 15 ready-to-use UI components. See [UI Components guide](navigation/ui-components.md) for full details.

### Essential Components

1. **NavigationView** - Complete navigation UI (Drop-in)
2. **ManeuverInstructions** - Turn-by-turn text guidance
3. **VoiceInstructions** - Audio guidance
4. **TripProgress** - ETA, distance, time remaining
5. **SpeedLimit** - Current speed limit display
6. **RouteLineView** - Route visualization on map

### Using Drop-in UI (Fastest)

```kotlin
// Add to layout
<com.mapbox.navigation.ui.maps.NavigationView
    android:id="@+id/navigationView"
    android:layout_width="match_parent"
    android:layout_height="match_parent" />
```

Drop-in UI includes:
- Map display
- Camera controls
- Route line
- Maneuver instructions
- Voice guidance
- Trip progress
- Speed limit
- Rerouting

---

## Critical Gotchas

### 1. Flutter Maps Conflict
**Issue**: Cannot use `mapbox_maps_flutter` with native Navigation SDK
**Why**: Dependency conflicts (ndk27 vs non-ndk27 variants)
**Solution**: Choose one or the other (see [Flutter Maps limitations](flutter/flutter-maps-overview.md))

### 2. Token Confusion
**Issue**: Using public token for downloads or secret token in app
**Fix**:
- **Public (pk.)** → `res/values/developer-config.xml`
- **Secret (sk.)** → `~/.gradle/gradle.properties`

See [Token Scopes](reference/token-scopes.md)

### 3. Coordinates Order
**Issue**: Swapping latitude and longitude
**Correct**: `Point.fromLngLat(longitude, latitude)` - **longitude first!**

### 4. SOURCE_DATE_EPOCH
**Issue**: CMake errors during build
**Fix**: `unset SOURCE_DATE_EPOCH` before building

See [Troubleshooting](troubleshooting.md) for more.

---

## Getting Unstuck

### Build Errors
1. Check [Troubleshooting Guide](troubleshooting.md)
2. Verify [Installation & Setup](navigation/installation-setup.md)
3. Validate [Token Scopes](reference/token-scopes.md)

### Runtime Errors
1. Check [Initialization Guide](navigation/initialization.md)
2. Review [Troubleshooting: Runtime Issues](troubleshooting.md#runtime-navigation-issues)
3. Verify location permissions granted

### API Errors
1. Review [Directions API](apis/directions-api.md)
2. Check [Troubleshooting: API Issues](troubleshooting.md#api-and-network-issues)
3. Validate token scopes

---

## External Resources

### Official Documentation
- Navigation SDK: https://docs.mapbox.com/android/navigation/guides/
- Maps SDK: https://docs.mapbox.com/android/maps/guides/
- Search SDK: https://docs.mapbox.com/android/search/overview/
- Directions API: https://docs.mapbox.com/api/navigation/directions/

### API Playgrounds
- Directions API: https://docs.mapbox.com/playground/directions/
- Search Box API: https://docs.mapbox.com/playground/search-box/

### Tools
- Mapbox Studio: https://studio.mapbox.com/
- Token Management: https://account.mapbox.com/access-tokens/
- GitHub Issues: https://github.com/mapbox/mapbox-navigation-android/issues

---

## Document Index

### Navigation SDK (Android)
```
navigation/
├── android-navigation-overview.md    Features, requirements, version info
├── installation-setup.md             Maven setup, tokens, permissions
├── initialization.md                 MapboxNavigation setup, lifecycle
├── navigation-camera.md              Camera framing, following/overview modes
├── route-line.md                     Route rendering, traffic, alternatives
├── voice-instructions.md             Audio guidance, speech synthesis
├── maneuver-instructions.md          Turn-by-turn visual guidance
├── trip-progress.md                  ETA, distance, time display
├── location-component.md             User location display, puck styles
├── rerouting.md                      Automatic rerouting, off-route detection
├── speed-limit.md                    Speed limit display, overspeed detection
├── offline-navigation.md             Offline tiles, offline routing
├── foreground-service.md             Background navigation, notifications
├── building-highlights.md            3D building extrusion
├── waypoints.md                      Multi-stop navigation
└── ui-components.md                  15 pre-built UI components overview
```

### Maps SDKs
```
maps/
├── android-maps-overview.md          MapView, layers, sources, camera
└── camera-controls.md                Camera positioning, zoom, animations

flutter/
└── flutter-maps-overview.md          Cross-platform maps, limitations
```

### Search SDK
```
search/
└── android-search-overview.md        Place search, autocomplete, categories
```

### APIs
```
apis/
└── directions-api.md                 Route calculation, voice instructions
```

### Reference
```
reference/
└── token-scopes.md                   Token types, permissions, security
```

### Troubleshooting
```
troubleshooting.md                    Common errors, solutions, debugging
```

---

## Contributing to This Library

When adding new documentation:
1. Fetch from official Mapbox docs using MCP + WebFetch
2. Organize by category (navigation, maps, search, apis, reference)
3. Update this README with new file in appropriate section
4. Cross-reference related docs
5. Include practical code examples

---

**Last Updated**: January 6, 2026
**Maintained For**: RouteWhisper navigation app
**Mapbox SDK Versions**: Navigation 3.18.0-beta.1, Maps 11.x, Search 2.17.1
