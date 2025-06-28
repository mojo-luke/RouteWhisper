package com.routewhisper.route_whisper_app

import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "routewhisper.com/navigation"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        Log.d("MainActivity", "Setting up method channel")
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            Log.d("MainActivity", "Received method call: ${call.method}")
            
            when (call.method) {
                "openMapView" -> {
                    Log.d("MainActivity", "Opening map...")
                    try {
                        val intent = Intent(this, MapActivity::class.java)
                        
                        // Check if simulation mode parameters are passed
                        val simulationMode = call.argument<Boolean>("simulationMode") ?: false
                        if (simulationMode) {
                            Log.d("MainActivity", "Opening map in simulation mode")
                            intent.putExtra("SIMULATION_MODE", true)
                            intent.putExtra("NAVIGATION_STATE", call.argument<String>("navigationState") ?: "idle")
                            intent.putExtra("ORIGIN_LAT", call.argument<Double>("originLat") ?: 37.7749)
                            intent.putExtra("ORIGIN_LNG", call.argument<Double>("originLng") ?: -122.4194)
                            intent.putExtra("DEST_LAT", call.argument<Double>("destLat") ?: 34.0522)
                            intent.putExtra("DEST_LNG", call.argument<Double>("destLng") ?: -118.2437)
                        }
                        
                        startActivity(intent)
                        result.success("Map opened")
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error opening map", e)
                        result.error("ERROR", "Failed to open map: ${e.message}", null)
                    }
                }
                "startNavigation" -> {
                    Log.d("MainActivity", "Starting navigation...")
                    try {
                        val originLat = call.argument<Double>("originLat") ?: 37.7749
                        val originLng = call.argument<Double>("originLng") ?: -122.4194
                        val destLat = call.argument<Double>("destLat") ?: 34.0522
                        val destLng = call.argument<Double>("destLng") ?: -118.2437
                        
                        val intent = Intent(this, MapActivity::class.java).apply {
                            putExtra("START_NAVIGATION", true)
                            putExtra("ORIGIN_LAT", originLat)
                            putExtra("ORIGIN_LNG", originLng)
                            putExtra("DEST_LAT", destLat)
                            putExtra("DEST_LNG", destLng)
                        }
                        startActivity(intent)
                        result.success("Navigation started")
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error starting navigation", e)
                        result.error("ERROR", "Failed to start navigation: ${e.message}", null)
                    }
                }
                "cancelNavigation" -> {
                    Log.d("MainActivity", "Cancelling navigation...")
                    result.success("Navigation cancelled")
                }
                else -> {
                    Log.d("MainActivity", "Unknown method: ${call.method}")
                    result.notImplemented()
                }
            }
        }
    }
}

// Simple configuration in Constants.kt
object NavigationConstants {
    const val INSTRUCTION_DISTANCE_THRESHOLD = 500.0 // meters
    const val OFF_ROUTE_THRESHOLD = 50.0 // meters  
    const val RECALCULATE_DELAY = 3000L // milliseconds
    const val VOICE_INSTRUCTION_INTERVAL = 10000L // milliseconds
}