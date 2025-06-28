package com.routewhisper.route_whisper_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "routewhisper.com/navigation"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showMap" -> {
                    val intent = Intent(this, MapActivity::class.java)
                    startActivity(intent)
                    result.success("Map shown")
                }
                "startNavigation" -> {
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
                }
                else -> result.notImplemented()
            }
        }
    }
}