package com.routewhisper.route_whisper_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.routewhisper.route_whisper_app.utils.Constants

class MainActivity : FlutterActivity() {
    private val CHANNEL = "routewhisper.com/navigation"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openMapView" -> {
                    val intent = Intent(this, MapActivity::class.java)
                    startActivity(intent)
                    result.success("Map opened")
                }
                "startNavigation" -> {
                    val originLat = call.argument<Double>("originLat") ?: Constants.DEFAULT_ORIGIN_LAT
                    val originLng = call.argument<Double>("originLng") ?: Constants.DEFAULT_ORIGIN_LNG
                    val destLat = call.argument<Double>("destLat") ?: Constants.DEFAULT_DEST_LAT
                    val destLng = call.argument<Double>("destLng") ?: Constants.DEFAULT_DEST_LNG
                    
                    val intent = Intent(this, MapActivity::class.java).apply {
                        putExtra(Constants.EXTRA_START_NAVIGATION, true)
                        putExtra(Constants.EXTRA_ORIGIN_LAT, originLat)
                        putExtra(Constants.EXTRA_ORIGIN_LNG, originLng)
                        putExtra(Constants.EXTRA_DEST_LAT, destLat)
                        putExtra(Constants.EXTRA_DEST_LNG, destLng)
                    }
                    startActivity(intent)
                    result.success("Navigation started")
                }
                else -> result.notImplemented()
            }
        }
    }
}