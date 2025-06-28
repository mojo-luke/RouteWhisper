package com.routewhisper.route_whisper_app

import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannel = "routewhisper.com/navigation"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannel).setMethodCallHandler { call, result ->
            Log.d("MainActivity", "Received method call: ${call.method}")
            
            when (call.method) {
                "calculateRoute" -> handleCalculateRoute(call, result)
                "prepareNavigation" -> handlePrepareNavigation(call, result)
                "updateLocation" -> handleUpdateLocation(call, result)
                "cancelNavigation" -> handleCancelNavigation(call, result)
                "openMapView" -> handleOpenMapView(call, result)
                
                // Keep existing methods for compatibility
                "startNavigation" -> handleStartNavigation(call, result)
                else -> result.notImplemented()
            }
        }
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
        
        Log.d("MainActivity", "Calculating route: ($originLat, $originLng) -> ($destLat, $destLng)")
        
        // For now, simulate route calculation success
        // In the future, this could trigger actual route calculation
        result.success("Route calculation started")
        
        // Send mock route data back to Flutter after a delay
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            sendRouteDataToFlutter()
        }, 2000)
    }

    private fun handlePrepareNavigation(call: MethodCall, result: MethodChannel.Result) {
        Log.d("MainActivity", "Preparing navigation")
        // Currently no specific preparation needed
        result.success("Navigation prepared")
    }

    private fun handleUpdateLocation(call: MethodCall, result: MethodChannel.Result) {
        val lat = call.argument<Double>("lat")
        val lng = call.argument<Double>("lng")
        val bearing = call.argument<Double>("bearing") ?: 0.0
        
        if (lat == null || lng == null) {
            result.error("INVALID_ARGS", "Missing coordinates", null)
            return
        }
        
        Log.d("MainActivity", "Location update: $lat, $lng, bearing: $bearing")
        
        // Store these for when MapActivity opens
        // Or send to MapActivity if it's already open
        result.success("Location updated")
    }

    private fun handleCancelNavigation(call: MethodCall, result: MethodChannel.Result) {
        Log.d("MainActivity", "Cancelling navigation")
        // Currently just acknowledge
        result.success("Navigation cancelled")
    }

    private fun handleOpenMapView(call: MethodCall, result: MethodChannel.Result) {
        Log.d("MainActivity", "Opening map view")
        
        val intent = Intent(this, MapActivity::class.java).apply {
            putExtra("ACTION", call.argument<String>("action") ?: "OPEN_MAP")
            putExtra("NAVIGATION_STATE", call.argument<String>("navigationState") ?: "idle")
            putExtra("SIMULATION_MODE", call.argument<Boolean>("simulationMode") ?: true)
        }
        startActivity(intent)
        
        result.success("Map view opened")
    }

    // Keep existing method for compatibility
    private fun handleStartNavigation(call: MethodCall, result: MethodChannel.Result) {
        val originLat = call.argument<Double>("originLat")
        val originLng = call.argument<Double>("originLng")
        val destLat = call.argument<Double>("destLat") 
        val destLng = call.argument<Double>("destLng")
        
        if (originLat == null || originLng == null || destLat == null || destLng == null) {
            result.error("INVALID_ARGS", "Missing coordinates", null)
            return
        }

        Log.d("MainActivity", "Starting navigation (legacy): ($originLat, $originLng) -> ($destLat, $destLng)")
        
        val intent = Intent(this, MapActivity::class.java).apply {
            putExtra("NAVIGATION_STATE", "navigating")
            putExtra("ORIGIN_LAT", originLat)
            putExtra("ORIGIN_LNG", originLng)
            putExtra("SIMULATION_MODE", true)
            putExtra("DEST_LAT", destLat)
            putExtra("DEST_LNG", destLng)
        }
        startActivity(intent)
        
        result.success("Navigation started")
    }

    private fun sendRouteDataToFlutter() {
        Log.d("MainActivity", "Sending route data to Flutter")
        
        // Send mock route points to Flutter
        val routePoints = generateSampleRoutePoints()
        
        Log.d("MainActivity", "Generated ${routePoints.size} route points")
        Log.d("MainActivity", "First point: ${routePoints.firstOrNull()}")
        
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, methodChannel).invokeMethod("routeCalculated", mapOf(
                "routePoints" to routePoints
            ))
            Log.d("MainActivity", "Route data sent to Flutter")
        }
    }

    private fun generateSampleRoutePoints(): List<Map<String, Double>> {
        Log.d("MainActivity", "Generating sample route points")
        
        // Generate sample points from San Francisco to LA for testing
        val points = mutableListOf<Map<String, Double>>()
        
        // Simple interpolation between SF and LA
        val startLat = 37.7749
        val startLng = -122.4194
        val endLat = 34.0522
        val endLng = -118.2437
        
        val numPoints = 100 // Generate 100 points for smooth movement
        
        for (i in 0 until numPoints) {
            val progress = i.toDouble() / (numPoints - 1)
            val lat = startLat + (endLat - startLat) * progress
            val lng = startLng + (endLng - startLng) * progress
            
            points.add(mapOf(
                "lat" to lat,
                "lng" to lng
            ))
        }
        
        Log.d("MainActivity", "Generated ${points.size} points")
        return points
    }
}

// Simple configuration in Constants.kt
object NavigationConstants {
    const val INSTRUCTION_DISTANCE_THRESHOLD = 500.0 // meters
    const val OFF_ROUTE_THRESHOLD = 50.0 // meters  
    const val RECALCULATE_DELAY = 3000L // milliseconds
    const val VOICE_INSTRUCTION_INTERVAL = 10000L // milliseconds
}