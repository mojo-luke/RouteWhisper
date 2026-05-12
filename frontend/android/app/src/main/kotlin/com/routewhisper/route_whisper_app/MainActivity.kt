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

        /**
         * Forward each GPS fix to Flutter so the NarrationService can decide
         * whether to whisper a fact about a nearby place. Fires at the cadence
         * Mapbox's LocationObserver emits (roughly 1 Hz during driving) — no
         * per-side throttling needed at v1.
         */
        fun sendLocationUpdate(latitude: Double, longitude: Double, speedMph: Double) {
            methodChannelInstance?.invokeMethod("locationUpdate", mapOf(
                "latitude" to latitude,
                "longitude" to longitude,
                "speedMph" to speedMph,
            ))
        }
    }

    // Use the shared FlutterEngine created by RouteWhisperApplication
    override fun getCachedEngineId(): String {
        return SHARED_ENGINE_ID
    }

    // The shared engine's lifecycle is driven from RouteWhisperApplication via
    // ProcessLifecycleOwner. If this activity also dispatched its own lifecycle to the
    // engine, its onStop would fire AFTER MapActivity.onResume during a transition and
    // pause the engine while MapActivity is foreground — freezing overlay setState calls.
    override fun shouldDispatchAppLifecycleState(): Boolean = false

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
                "showPoisOnMap" -> handleShowPoisOnMap(call, result)
                "clearPoisFromMap" -> handleClearPoisFromMap(result)
                "hideOverlay" -> handleHideOverlay(result)
                "setBudgetStatus" -> handleSetBudgetStatus(call, result)
                "clearBudgetStatus" -> handleClearBudgetStatus(result)
                "setRecommendation" -> handleSetRecommendation(call, result)
                "clearRecommendation" -> handleClearRecommendation(result)
                "speakNarration" -> handleSpeakNarration(call, result)
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

    private fun handleShowPoisOnMap(call: MethodCall, result: MethodChannel.Result) {
        val poisRaw = call.argument<List<Map<String, Any>>>("pois")
        val bounds = call.argument<List<Double>>("bounds")
        if (poisRaw == null || bounds == null || bounds.size != 4) {
            result.error("INVALID_ARGS", "Missing pois or bounds", null)
            return
        }

        val map = MapActivity.currentInstance
        if (map == null) {
            Log.e("MainActivity", "showPoisOnMap: no active MapActivity")
            result.error("NO_ACTIVITY", "MapActivity not active", null)
            return
        }

        map.showPoisOnMap(poisRaw, bounds)
        result.success(null)
    }

    private fun handleClearPoisFromMap(result: MethodChannel.Result) {
        MapActivity.currentInstance?.clearPoisFromMap()
        result.success(null)
    }

    private fun handleHideOverlay(result: MethodChannel.Result) {
        MapActivity.currentInstance?.hideFlutterOverlay()
        result.success(null)
    }

    private fun handleSetBudgetStatus(call: MethodCall, result: MethodChannel.Result) {
        val used = call.argument<Int>("usedMinutes")
        val total = call.argument<Int>("totalMinutes")
        if (used == null || total == null) {
            result.error("INVALID_ARGS", "Missing usedMinutes or totalMinutes", null)
            return
        }
        MapActivity.currentInstance?.setBudgetStatusUi(used, total)
        result.success(null)
    }

    private fun handleClearBudgetStatus(result: MethodChannel.Result) {
        MapActivity.currentInstance?.clearBudgetStatusUi()
        result.success(null)
    }

    private fun handleSetRecommendation(call: MethodCall, result: MethodChannel.Result) {
        val poiId = call.argument<String>("poiId")
        val name = call.argument<String>("name")
        val category = call.argument<String>("category")
        val reason = call.argument<String>("reason")
        if (poiId == null || name == null || category == null || reason == null) {
            result.error("INVALID_ARGS", "Missing recommendation fields", null)
            return
        }
        MapActivity.currentInstance?.setRecommendationUi(poiId, name, category, reason)
        result.success(null)
    }

    private fun handleClearRecommendation(result: MethodChannel.Result) {
        MapActivity.currentInstance?.clearRecommendationUi()
        result.success(null)
    }

    /**
     * Speak arbitrary narration text via the Mapbox voice player.
     *
     * Phase 1 narration: reuses the same MapboxVoiceInstructionsPlayer the
     * turn-by-turn voice uses. That shares audio focus with the nav voice
     * (no fighting over the speaker), and per the Mapbox SDK doc page on
     * voice instructions the player handles ducking/queuing internally —
     * turn-by-turn announcements take priority by virtue of being queued
     * by the same player on the same channel.
     */
    private fun handleSpeakNarration(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")
        if (text.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Missing text", null)
            return
        }
        val activity = MapActivity.currentInstance
        if (activity == null) {
            // Quietly succeed — narration isn't load-bearing and the user
            // may have backed out of nav. Don't surface this as a Flutter
            // error or it'll spam logs.
            Log.d("MainActivity", "speakNarration: no MapActivity; silently dropping")
            result.success(null)
            return
        }
        activity.speakNarration(text)
        result.success(null)
    }

    override fun onPause() {
        Log.d("MainActivity", "🟡 onPause (FlutterActivity will dispatch appIsInactive)")
        super.onPause()
    }

    override fun onStop() {
        Log.d("MainActivity", "🔴 onStop (FlutterActivity will dispatch appIsPaused)")
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        Log.d("MainActivity", "🟢 onResume (FlutterActivity dispatched appIsResumed)")
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
