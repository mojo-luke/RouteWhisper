package com.routewhisper.route_whisper_app

import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp

class MainActivity : FlutterActivity() {
    private val methodChannelName = "routewhisper.com/navigation"

    companion object {
        const val SHARED_ENGINE_ID = "routewhisper_shared_engine"

        // Static reference to method channel for use by other activities
        internal var methodChannelInstance: MethodChannel? = null

        fun sendRoutePolyline(polyline: String) {
            methodChannelInstance?.invokeMethod("setRoutePolyline", mapOf("polyline" to polyline))
            Log.d("MainActivity", "Sent route polyline to Flutter (${polyline.length} chars)")
        }

        fun sendWaypointArrived(legIndex: Int, latitude: Double, longitude: Double) {
            if (methodChannelInstance == null) {
                Log.e("MainActivity", "❌ methodChannelInstance is NULL! Cannot send waypoint arrival")
                return
            }

            Log.d("MainActivity", "Invoking waypointArrived method channel for leg $legIndex")
            methodChannelInstance?.invokeMethod("waypointArrived", mapOf(
                "legIndex" to legIndex,
                "latitude" to latitude,
                "longitude" to longitude,
                "timestamp" to System.currentTimeMillis()
            ))
            Log.d("MainActivity", "✅ Sent waypoint arrival to Flutter: leg $legIndex")
        }

        fun sendAutoDepartureDetected(distance: Double, speed: Double) {
            methodChannelInstance?.invokeMethod("autoDepartureDetected", mapOf(
                "distance" to distance,
                "speed" to speed,
                "timestamp" to System.currentTimeMillis()
            ))
            Log.d("MainActivity", "Sent auto-departure to Flutter: ${distance}m, ${speed}mph")
        }

        fun sendDestinationArrived() {
            methodChannelInstance?.invokeMethod("destinationArrived", mapOf(
                "timestamp" to System.currentTimeMillis()
            ))
            Log.d("MainActivity", "Sent destination arrival to Flutter")
        }
    }

    // Use the shared FlutterEngine created by RouteWhisperApplication
    override fun getCachedEngineId(): String {
        return SHARED_ENGINE_ID
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        Log.d("MainActivity", "Configuring shared Flutter engine: $SHARED_ENGINE_ID")

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
        methodChannelInstance = channel  // Store reference for MapActivity

        channel.setMethodCallHandler { call, result ->
            Log.d("MainActivity", "Received method call: ${call.method}")

            when (call.method) {
                "calculateRoute" -> handleCalculateRoute(call, result)
                "updateNavigationRoute" -> handleUpdateNavigationRoute(call, result)
                "openMapView" -> handleOpenMapView(call, result)
                "cancelNavigation" -> handleCancelNavigation(result)
                else -> result.notImplemented()
            }
        }
    }

    internal fun handleCalculateRoute(call: MethodCall, result: MethodChannel.Result) {
        val originLat = call.argument<Double>("originLat")
        val originLng = call.argument<Double>("originLng")
        val destLat = call.argument<Double>("destLat")
        val destLng = call.argument<Double>("destLng")
        val waypoints = call.argument<List<List<Double>>>("waypoints") // [[lng, lat], [lng, lat], ...]
        val waypointNames = call.argument<List<String>>("waypointNames") // ["Name 1", "Name 2", ...]

        if (originLat == null || originLng == null || destLat == null || destLng == null) {
            result.error("INVALID_ARGS", "Missing coordinates", null)
            return
        }

        if (waypoints != null && waypoints.isNotEmpty()) {
            Log.d("MainActivity", "Calculate route with ${waypoints.size} waypoints: ($originLat, $originLng) -> ($destLat, $destLng)")
            if (waypointNames != null && waypointNames.isNotEmpty()) {
                Log.d("MainActivity", "Waypoint names: $waypointNames")
            }
        } else {
            Log.d("MainActivity", "Calculate route: ($originLat, $originLng) -> ($destLat, $destLng)")
        }

        // Launch MapActivity which will handle route calculation with waypoints
        val intent = Intent(this, MapActivity::class.java).apply {
            putExtra("originLat", originLat)
            putExtra("originLng", originLng)
            putExtra("destLat", destLat)
            putExtra("destLng", destLng)

            // Pass waypoints as flat array: [lng1, lat1, lng2, lat2, ...]
            if (waypoints != null && waypoints.isNotEmpty()) {
                val flatWaypoints = waypoints.flatten().toDoubleArray()
                putExtra("waypoints", flatWaypoints)
                Log.d("MainActivity", "Passing ${waypoints.size} waypoints for route calculation")

                // Pass waypoint names as String array
                if (waypointNames != null && waypointNames.isNotEmpty()) {
                    putExtra("waypointNames", waypointNames.toTypedArray())
                    Log.d("MainActivity", "Passing ${waypointNames.size} waypoint names for route calculation")
                }
            }
        }
        startActivity(intent)

        result.success("Route calculation started")
    }

    /**
     * Update navigation route in existing MapActivity (in-place update)
     *
     * This method updates the route without launching a new activity, which is critical
     * for the "Never Leave Navigation" UX principle. Called when user adds POI during
     * active navigation.
     *
     * Unlike handleCalculateRoute which launches a NEW MapActivity, this method sends
     * the update to the EXISTING MapActivity instance via updateNavigationRoute().
     */
    internal fun handleUpdateNavigationRoute(call: MethodCall, result: MethodChannel.Result) {
        val originLat = call.argument<Double>("originLat")
        val originLng = call.argument<Double>("originLng")
        val destLat = call.argument<Double>("destLat")
        val destLng = call.argument<Double>("destLng")
        val waypoints = call.argument<List<List<Double>>>("waypoints") // [[lng, lat], [lng, lat], ...]
        val waypointNames = call.argument<List<String>>("waypointNames") // ["Name 1", "Name 2", ...]

        if (originLat == null || originLng == null || destLat == null || destLng == null) {
            result.error("INVALID_ARGS", "Missing coordinates", null)
            return
        }

        Log.d("MainActivity", "🔄 Update navigation route in-place with ${waypoints?.size ?: 0} waypoints")

        // Check if MapActivity is currently active
        val mapActivity = MapActivity.currentInstance
        if (mapActivity == null) {
            Log.e("MainActivity", "❌ No active MapActivity instance - cannot update route in-place")
            result.error("NO_ACTIVITY", "MapActivity not active", null)
            return
        }

        // Convert waypoints to Points
        val waypointPoints = if (waypoints != null && waypoints.isNotEmpty()) {
            waypoints.mapNotNull { coords ->
                if (coords.size >= 2) {
                    com.mapbox.geojson.Point.fromLngLat(coords[0], coords[1])
                } else {
                    null
                }
            }
        } else {
            emptyList()
        }

        Log.d("MainActivity", "Updating route with ${waypointPoints.size} waypoint points")

        // Update route in existing MapActivity (in-place)
        mapActivity.updateNavigationRoute(
            originLat = originLat,
            originLng = originLng,
            destLat = destLat,
            destLng = destLng,
            waypoints = waypointPoints,
            waypointNames = waypointNames
        )

        result.success("Route updated in-place")
    }

    private fun handleOpenMapView(call: MethodCall, result: MethodChannel.Result) {
        Log.d("MainActivity", "Open map view")

        // Launch MapActivity without coordinates - it will show current map state
        // (including any active routes, or just the map if no routes are set)
        val intent = Intent(this, MapActivity::class.java).apply {
            // Don't pass coordinates - MapActivity will just display current state
            putExtra("viewOnly", true)
        }
        startActivity(intent)

        result.success("Map view opened")
    }

    @OptIn(com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI::class)
    internal fun handleCancelNavigation(result: MethodChannel.Result) {
        Log.d("MainActivity", "Cancel navigation - stopping trip session and clearing routes")

        // Stop the active navigation session completely
        try {
            if (MapboxNavigationApp.isSetup()) {
                val mapboxNavigation = MapboxNavigationApp.current()

                // Stop the active guidance session
                mapboxNavigation?.stopTripSession()
                Log.d("MainActivity", "Trip session stopped")

                // Clear routes
                mapboxNavigation?.setNavigationRoutes(emptyList())
                Log.d("MainActivity", "Routes cleared successfully")

                // Stop replay simulation if active
                mapboxNavigation?.mapboxReplayer?.stop()
                mapboxNavigation?.mapboxReplayer?.finish()
                Log.d("MainActivity", "Replay simulation stopped")
            } else {
                Log.d("MainActivity", "MapboxNavigationApp not setup yet")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error cancelling navigation: ${e.message}")
        }

        result.success("Navigation cancelled")
    }
}
