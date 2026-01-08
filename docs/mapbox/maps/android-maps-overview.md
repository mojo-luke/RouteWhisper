# Mapbox Maps SDK for Android

## Overview
The Mapbox Maps SDK for Android is a library for embedding highly customized maps within Android applications. It enables developers to integrate interactive, styled maps directly into their apps with runtime customization capabilities.

## Key Features
- **Map Styling**: Access to Mapbox Standard, Satellite, and custom styles designed in Mapbox Studio
- **Runtime Styling**: Modify map appearance dynamically based on data or user interaction
- **Camera Manipulation**: Control map viewing angles and zoom levels
- **Data Visualization**: Add custom markers, layers, and styled features
- **Querying Capabilities**: Interact with map elements programmatically
- **Static Map Generation**: Create snapshots using the MapSnapshotter class

## System Requirements
- **Android SDK**: 21 or higher
- **OpenGL ES 3**: Required for rendering
- **Kotlin**: 1.6.0+ (for Kotlin projects)
- **Java**: 8+ compatibility for source/target settings

## NDK Support
- **NDK 23** (default): Standard deployment
- **NDK 27** (v11.7.0+): Supports 16 KB page sizes via `-ndk27` artifact variant

## Core Components

### MapView
The primary view component for displaying maps in Android layouts.

### Camera
Controls map viewing angles, zoom levels, and positioning. Supports:
- Programmatic camera movements
- Animated transitions
- Following user location

### Layers
Visual representation of data on the map:
- Symbol layers (icons and text)
- Line layers (roads, paths)
- Fill layers (polygons, areas)
- Circle layers (points)
- Heatmap layers
- Fill-extrusion layers (3D buildings)

### Sources
Data sources that feed layers:
- GeoJSON sources
- Vector tile sources
- Raster tile sources
- Image sources

## Integration Ecosystem
Works seamlessly with:
- **Mapbox Studio**: For map design
- **Static Images API**: For generating static map images
- **Java SDK services**: For directions, geocoding, etc.
- **Navigation SDK**: For turn-by-turn navigation

## Language Support
The SDK is built in Kotlin but is 100% interoperable with Java applications.

## Legal Requirements
- Apps must display Mapbox attribution
- Provide users telemetry opt-out access through the attribution control

## Installation

### Add Maven Repository
```gradle
repositories {
    maven {
        url 'https://api.mapbox.com/downloads/v2/releases/maven'
        authentication {
            basic(BasicAuthentication)
        }
        credentials {
            username = 'mapbox'
            password = MAPBOX_DOWNLOADS_TOKEN
        }
    }
}
```

### Add Dependency
```gradle
dependencies {
    implementation 'com.mapbox.maps:android:11.x.x'
    // For NDK 27:
    implementation 'com.mapbox.maps:android-ndk27:11.x.x'
}
```

### Configure Access Token
Add to `res/values/developer-config.xml`:
```xml
<resources>
    <string name="mapbox_access_token">YOUR_PUBLIC_TOKEN</string>
</resources>
```

## Basic Usage

### XML Layout
```xml
<com.mapbox.maps.MapView
    android:id="@+id/mapView"
    android:layout_width="match_parent"
    android:layout_height="match_parent" />
```

### Kotlin Activity
```kotlin
import com.mapbox.maps.MapView
import com.mapbox.maps.Style

class MainActivity : AppCompatActivity() {
    private lateinit var mapView: MapView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        mapView = findViewById(R.id.mapView)
        mapView.mapboxMap.loadStyle(Style.MAPBOX_STREETS)
    }
}
```

## Documentation
- Full Maps SDK Guide: https://docs.mapbox.com/android/maps/guides/
- API Reference: https://docs.mapbox.com/android/maps/api/
- Examples: https://docs.mapbox.com/android/maps/examples/
