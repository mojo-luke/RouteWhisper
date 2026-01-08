# Mapbox Search SDK for Android

## Overview
The Mapbox Search SDK for Android provides comprehensive location search capabilities with pre-built UI components for seamless app integration.

## Core Features
- **Pre-built UI components** for drop-in search functionality
- **Multi-mode searching**: by place name, category, or geographic coordinates
- **Offline address search** functionality
- Customizable search experiences

## Search Types & Components

### 1. Address Autofill
Streamlines address entry during registration or checkout by enabling users to fill in the address form by entering only a few characters.

**Use cases**:
- User registration forms
- Checkout flows
- Delivery address entry

### 2. Category Search
Enables POI (Points of Interest) discovery for specific types of locations.

**Common categories**:
- Restaurants
- Parking
- EV charging stations
- Gas stations
- Hotels
- ATMs

### 3. Place Autocomplete
Returns suggestions including addresses, businesses, and POIs in response to text queries or coordinate-based requests.

**Features**:
- Type-ahead suggestions
- Search by coordinates
- Reverse geocoding
- Business and POI results

### 4. Search Engine
A customizable foundation for building tailored search experiences.

**Variants**:
- Online search engine
- Offline search engine (for address lookup without internet)
- Hybrid search combining both

### 5. Search UI
Ready-made interface components with:
- Style customization options
- Result filtering capabilities
- Built-in best practices

## Technical Requirements

### System Requirements
- **Android SDK**: 21+ (Android 5.0)
- **NDK**: 23 (default) or 27
- **Kotlin**: 1.7+
- **Java**: 8+ for source/target compatibility

### Supported Architectures
- armeabi-v7a
- arm64-v8a
- x86
- x86_64

## Current Version
v2.17.1

**Version Lines**:
- **1.x**: Compatible with Maps SDK 10
- **2.x**: Compatible with Maps SDK 11

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

### Add Dependencies
```gradle
dependencies {
    // Core Search SDK
    implementation 'com.mapbox.search:mapbox-search-android:2.17.1'

    // UI components (optional)
    implementation 'com.mapbox.search:mapbox-search-android-ui:2.17.1'
}
```

## Basic Usage Example

### Simple Search
```kotlin
import com.mapbox.search.SearchEngine
import com.mapbox.search.SearchEngineSettings

val searchEngine = SearchEngine.createSearchEngine(
    SearchEngineSettings(accessToken = YOUR_TOKEN)
)

searchEngine.search(
    query = "coffee shop",
    options = SearchOptions(proximity = Point.fromLngLat(-122.4194, 37.7749))
) { response ->
    response.onValue { results ->
        results.forEach { result ->
            println("${result.name} - ${result.address}")
        }
    }
}
```

### Category Search
```kotlin
import com.mapbox.search.CategorySearchEngine

val categorySearchEngine = CategorySearchEngine.create()

categorySearchEngine.search(
    categoryName = "restaurant",
    options = CategorySearchOptions(
        proximity = Point.fromLngLat(-122.4194, 37.7749),
        limit = 10
    )
) { response ->
    response.onValue { results ->
        // Handle restaurant results
    }
}
```

### Using Search UI
```kotlin
import com.mapbox.search.ui.view.SearchBottomSheetView

val searchView = SearchBottomSheetView(context)
searchView.initialize(
    SearchBottomSheetView.Configuration(
        accessToken = YOUR_TOKEN
    )
)

searchView.addOnSearchResultClickListener { searchResult ->
    // Handle selected result
    val coordinate = searchResult.coordinate
    val name = searchResult.name
}
```

## Integration with Navigation

Search SDK pairs naturally with Navigation SDK for complete origin-to-destination flows:

1. **Search for destination** using Search SDK
2. **Get coordinates** from search result
3. **Calculate route** using Directions API
4. **Start navigation** using Navigation SDK

## Offline Search

For offline address lookup:

```kotlin
import com.mapbox.search.offline.OfflineSearchEngine

val offlineEngine = OfflineSearchEngine.create(
    OfflineSearchEngineSettings(
        accessToken = YOUR_TOKEN,
        tileStore = tileStore
    )
)

// Download region for offline use
offlineEngine.createTilesetDescriptor()
```

## Documentation
- Full Search SDK Guide: https://docs.mapbox.com/android/search/overview/
- Search UI Components: https://docs.mapbox.com/android/search/guides/ui-components/
- API Reference: https://docs.mapbox.com/android/search/api/
- Examples: https://docs.mapbox.com/android/search/examples/
