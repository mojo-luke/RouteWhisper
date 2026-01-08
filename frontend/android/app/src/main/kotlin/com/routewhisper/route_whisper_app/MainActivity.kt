package com.routewhisper.route_whisper_app

import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp

class MainActivity : FlutterActivity() {
    private val methodChannel = "routewhisper.com/navigation"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannel).setMethodCallHandler { call, result ->
            Log.d("MainActivity", "Received method call: ${call.method}")

            when (call.method) {
                "startNavigation" -> handleStartNavigation(call, result)
                "calculateRoute" -> handleCalculateRoute(call, result)
                "openMapView" -> handleOpenMapView(call, result)
                "cancelNavigation" -> handleCancelNavigation(result)
                else -> result.notImplemented()
            }
        }
    }

    internal fun handleStartNavigation(call: MethodCall, result: MethodChannel.Result) {
        val originLat = call.argument<Double>("originLat")
        val originLng = call.argument<Double>("originLng")
        val destLat = call.argument<Double>("destLat")
        val destLng = call.argument<Double>("destLng")

        if (originLat == null || originLng == null || destLat == null || destLng == null) {
            result.error("INVALID_ARGS", "Missing coordinates", null)
            return
        }

        Log.d("MainActivity", "Starting navigation: ($originLat, $originLng) -> ($destLat, $destLng)")

        // Launch MapActivity with coordinates
        val intent = Intent(this, MapActivity::class.java).apply {
            putExtra("originLat", originLat)
            putExtra("originLng", originLng)
            putExtra("destLat", destLat)
            putExtra("destLng", destLng)
        }
        startActivity(intent)

        result.success("Navigation started")
    }

    private fun handleCalculateRoute(call: MethodCall, result: MethodChannel.Result) {
        val originLat = call.argument<Double>("originLat")
        val originLng = call.argument<Double>("originLng")
        val destLat = call.argument<Double>("destLat")
        val destLng = call.argument<Double>("destLng")

        if (originLat == null || originLng == null || destLat == null || destLng == null) {
            result.error("INVALID_ARGS", "Missing coordinates", null)
            return
        }

        Log.d("MainActivity", "Calculate route: ($originLat, $originLng) -> ($destLat, $destLng)")

        // For now, launch MapActivity which will handle route calculation
        val intent = Intent(this, MapActivity::class.java).apply {
            putExtra("originLat", originLat)
            putExtra("originLng", originLng)
            putExtra("destLat", destLat)
            putExtra("destLng", destLng)
        }
        startActivity(intent)

        result.success("Route calculation started")
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

    internal fun handleCancelNavigation(result: MethodChannel.Result) {
        Log.d("MainActivity", "Cancel navigation - clearing routes")

        // Get MapboxNavigation instance and clear routes
        try {
            if (MapboxNavigationApp.isSetup()) {
                val mapboxNavigation = MapboxNavigationApp.current()
                mapboxNavigation?.setNavigationRoutes(emptyList())
                Log.d("MainActivity", "Routes cleared successfully")
            } else {
                Log.d("MainActivity", "MapboxNavigationApp not setup yet")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error clearing routes: ${e.message}")
        }

        result.success("Navigation cancelled")
    }
}
