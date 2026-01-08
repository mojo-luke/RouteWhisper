# Offline Navigation

## Overview
The Navigation SDK supports offline routing and navigation by pre-downloading map tiles and routing data. This allows navigation to continue without internet connectivity.

## What Works Offline

- **Routing**: Calculate routes using downloaded tiles
- **Rerouting**: Automatic rerouting using offline data
- **Map Display**: Show maps using cached tiles
- **Navigation**: Full turn-by-turn navigation
- **Voice Instructions**: Pre-downloaded voice files

## What Requires Online

- **Traffic Data**: Real-time traffic information
- **Alternative Routes**: Live route alternatives
- **Search**: Place search and geocoding
- **Tiles Download**: Initial tile download requires network

## Setting Up Offline Navigation

### Step 1: Configure Tile Store

```kotlin
import com.mapbox.common.TileStore
import com.mapbox.common.TileStoreOptions

val tileStoreOptions = TileStoreOptions.Builder()
    .baseURL("https://api.mapbox.com")
    .build()

val tileStore = TileStore.create(tileStoreOptions)
```

### Step 2: Configure Navigation for Offline

```kotlin
import com.mapbox.navigation.base.options.RoutingTilesOptions

val routingTilesOptions = RoutingTilesOptions.Builder()
    .tileStore(tileStore)
    .tilesVersion("2024-01-01") // Specific version
    .build()

val navigationOptions = NavigationOptions.Builder(context)
    .accessToken(YOUR_TOKEN)
    .routingTilesOptions(routingTilesOptions)
    .build()
```

### Step 3: Download Tiles for Region

```kotlin
import com.mapbox.navigation.core.RoutingTilesController
import com.mapbox.geojson.Polygon
import com.mapbox.geojson.Point

fun downloadRegion(southwest: Point, northeast: Point) {
    // Create bounding box
    val coordinates = listOf(
        listOf(
            southwest,
            Point.fromLngLat(northeast.longitude(), southwest.latitude()),
            northeast,
            Point.fromLngLat(southwest.longitude(), northeast.latitude()),
            southwest
        )
    )
    val boundingBox = Polygon.fromLngLats(coordinates)

    // Create tile region descriptor
    val descriptor = mapboxNavigation.createRoutingTilesetDescriptor(
        options = TilesetDescriptorOptions.Builder()
            .tilesVersion("2024-01-01")
            .build(),
        geometry = boundingBox
    )

    // Download tiles
    mapboxNavigation.getRoutingTilesController().downloadTiles(
        descriptor,
        object : RoutingTilesCallback {
            override fun onTilesDownloaded() {
                Log.d("Offline", "Tiles downloaded successfully")
            }

            override fun onTilesDownloadError(error: String) {
                Log.e("Offline", "Download failed: $error")
            }

            override fun onProgressUpdate(progress: Float) {
                Log.d("Offline", "Download progress: ${progress * 100}%")
            }
        }
    )
}

// Usage - download San Francisco area
val sfSouthwest = Point.fromLngLat(-122.5, 37.7)
val sfNortheast = Point.fromLngLat(-122.3, 37.8)
downloadRegion(sfSouthwest, sfNortheast)
```

## Monitoring Download Progress

```kotlin
import com.mapbox.navigation.core.RoutingTilesController

val tilesController = mapboxNavigation.getRoutingTilesController()

tilesController.addTilesDownloadListener(object : RoutingTilesDownloadListener {
    override fun onTilesDownloadProgress(progress: Float) {
        updateProgressBar(progress)
    }

    override fun onTilesDownloadComplete() {
        showToast("Offline navigation ready")
    }

    override fun onTilesDownloadError(error: String) {
        showToast("Download failed: $error")
    }
})
```

## Storage Management

### Check Tile Storage Size

```kotlin
fun getTileStorageSize(): Long {
    val tileStoreSize = tileStore.getSize()
    Log.d("Offline", "Tile storage: ${tileStoreSize / 1024 / 1024} MB")
    return tileStoreSize
}
```

### Clear Offline Tiles

```kotlin
fun clearOfflineTiles() {
    mapboxNavigation.getRoutingTilesController().clearTiles()
    Log.d("Offline", "Offline tiles cleared")
}
```

### Estimate Download Size

```kotlin
fun estimateDownloadSize(boundingBox: Polygon) {
    val descriptor = mapboxNavigation.createRoutingTilesetDescriptor(
        TilesetDescriptorOptions.Builder().build(),
        boundingBox
    )

    // Estimate size (approximate)
    // Size varies by region - urban areas larger than rural
    // Typical: 50-200 MB per major city
    Log.d("Offline", "Estimated size: ~100 MB")
}
```

## Using Offline Navigation

### Request Offline Route

```kotlin
import com.mapbox.api.directions.v5.MapboxDirections
import com.mapbox.api.directions.v5.models.RouteOptions

fun requestOfflineRoute(origin: Point, destination: Point) {
    val routeOptions = RouteOptions.builder()
        .accessToken(YOUR_TOKEN)
        .coordinates(listOf(origin, destination))
        .profile(DirectionsCriteria.PROFILE_DRIVING)
        .steps(true)
        .voiceInstructions(true)
        .bannerInstructions(true)
        // Enable offline routing
        .enableOfflineMode(true)
        .build()

    mapboxNavigation.requestRoutes(
        routeOptions,
        object : NavigationRouterCallback {
            override fun onRoutesReady(
                routes: List<NavigationRoute>,
                routerOrigin: RouterOrigin
            ) {
                if (routerOrigin == RouterOrigin.OFFLINE) {
                    Log.d("Offline", "Using offline routing")
                }
                mapboxNavigation.setNavigationRoutes(routes)
            }

            override fun onFailure(
                reasons: List<RouterFailure>,
                routeOptions: RouteOptions
            ) {
                Log.e("Offline", "Offline routing failed")
            }

            override fun onCanceled(
                routeOptions: RouteOptions,
                routerOrigin: RouterOrigin
            ) {
                Log.d("Offline", "Routing canceled")
            }
        }
    )
}
```

### Detect Offline vs Online Routing

```kotlin
mapboxNavigation.requestRoutes(
    routeOptions,
    object : NavigationRouterCallback {
        override fun onRoutesReady(
            routes: List<NavigationRoute>,
            routerOrigin: RouterOrigin
        ) {
            when (routerOrigin) {
                RouterOrigin.ONLINE -> {
                    Log.d("Routing", "Using online routing with traffic")
                }
                RouterOrigin.OFFLINE -> {
                    Log.d("Routing", "Using offline routing")
                    showOfflineIndicator()
                }
                RouterOrigin.ONBOARD -> {
                    Log.d("Routing", "Using on-device routing")
                }
            }
        }

        override fun onFailure(reasons: List<RouterFailure>, routeOptions: RouteOptions) {}
        override fun onCanceled(routeOptions: RouteOptions, routerOrigin: RouterOrigin) {}
    }
)
```

## Complete Offline Setup Example

```kotlin
class OfflineNavigationManager(
    private val context: Context,
    private val mapboxNavigation: MapboxNavigation
) {

    private lateinit var tileStore: TileStore

    fun initialize() {
        // Create tile store
        val tileStoreOptions = TileStoreOptions.Builder()
            .baseURL("https://api.mapbox.com")
            .build()

        tileStore = TileStore.create(tileStoreOptions)

        // Configure navigation for offline
        val routingTilesOptions = RoutingTilesOptions.Builder()
            .tileStore(tileStore)
            .tilesVersion("2024-01-01")
            .build()

        // Navigation should be configured with these options
    }

    fun downloadCityRegion(cityName: String, bounds: BoundingBox) {
        val coordinates = listOf(
            listOf(
                Point.fromLngLat(bounds.west(), bounds.south()),
                Point.fromLngLat(bounds.east(), bounds.south()),
                Point.fromLngLat(bounds.east(), bounds.north()),
                Point.fromLngLat(bounds.west(), bounds.north()),
                Point.fromLngLat(bounds.west(), bounds.south())
            )
        )
        val polygon = Polygon.fromLngLats(coordinates)

        val descriptor = mapboxNavigation.createRoutingTilesetDescriptor(
            TilesetDescriptorOptions.Builder().build(),
            polygon
        )

        mapboxNavigation.getRoutingTilesController().downloadTiles(
            descriptor,
            object : RoutingTilesCallback {
                override fun onTilesDownloaded() {
                    Log.d("Offline", "$cityName tiles downloaded")
                    saveDownloadedRegion(cityName, bounds)
                }

                override fun onTilesDownloadError(error: String) {
                    Log.e("Offline", "Failed to download $cityName: $error")
                }

                override fun onProgressUpdate(progress: Float) {
                    Log.d("Offline", "$cityName download: ${(progress * 100).toInt()}%")
                }
            }
        )
    }

    fun getStorageInfo(): StorageInfo {
        val sizeBytes = tileStore.getSize()
        val sizeMB = sizeBytes / 1024 / 1024

        return StorageInfo(
            sizeBytes = sizeBytes,
            sizeMB = sizeMB,
            regions = getDownloadedRegions()
        )
    }

    fun clearAllTiles() {
        mapboxNavigation.getRoutingTilesController().clearTiles()
    }

    private fun saveDownloadedRegion(name: String, bounds: BoundingBox) {
        // Save to SharedPreferences or database
        val prefs = context.getSharedPreferences("offline_regions", Context.MODE_PRIVATE)
        prefs.edit()
            .putString(name, "${bounds.west()},${bounds.south()},${bounds.east()},${bounds.north()}")
            .apply()
    }

    private fun getDownloadedRegions(): List<String> {
        val prefs = context.getSharedPreferences("offline_regions", Context.MODE_PRIVATE)
        return prefs.all.keys.toList()
    }

    data class StorageInfo(
        val sizeBytes: Long,
        val sizeMB: Long,
        val regions: List<String>
    )
}
```

## Best Practices

1. **Download on WiFi** - Tile downloads can be large
2. **Download home/frequent areas** - Pre-download common routes
3. **Update tiles periodically** - Road networks change
4. **Monitor storage** - Clean up unused regions
5. **Fallback to online** - Try online if offline fails
6. **Inform user** - Show offline mode indicator
7. **Test offline scenarios** - Enable airplane mode for testing

## Limitations

- **No real-time traffic** - Routes may be slower without traffic data
- **No search** - Can't search for new places offline
- **Larger app size** - Offline tiles take storage space
- **Maintenance required** - Need to update tiles periodically
- **Initial download** - Requires network for first download

## Related Documentation
- [Initialization Guide](initialization.md) - MapboxNavigation setup
- [Rerouting](rerouting.md) - Automatic rerouting works offline
- [Directions API](../apis/directions-api.md) - Requesting routes

## External Resources
- Offline Navigation Guide: https://docs.mapbox.com/android/navigation/guides/get-started/offline/
- Navigation SDK Examples: https://github.com/mapbox/mapbox-navigation-android-examples
