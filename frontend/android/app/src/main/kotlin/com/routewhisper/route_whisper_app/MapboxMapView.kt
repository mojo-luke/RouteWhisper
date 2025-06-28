package com.routewhisper.route_whisper_app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.lifecycle.LifecycleOwner
import com.mapbox.geojson.Point
import com.mapbox.maps.CameraOptions
import com.mapbox.maps.MapView
import com.mapbox.maps.plugin.locationcomponent.createDefault2DPuck
import com.mapbox.maps.plugin.locationcomponent.location
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

class MapboxMapView(
    private val context: Context,
    id: Int,
    creationParams: Map<String?, Any?>?,
    messenger: BinaryMessenger,
    private val lifecycleOwner: LifecycleOwner
) : PlatformView, MethodChannel.MethodCallHandler {
    
    private val mapView: MapView
    private val methodChannel: MethodChannel = MethodChannel(messenger, "mapbox_map_$id")
    
    init {
        methodChannel.setMethodCallHandler(this)
        
        // Create MapView - the lifecycle owner will be automatically detected from context
        mapView = MapView(context)
        setupMap()
    }
    
    private fun setupMap() {
        // Set initial camera position (San Francisco)
        mapView.mapboxMap.setCamera(
            CameraOptions.Builder()
                .center(Point.fromLngLat(-122.4194, 37.7749))
                .zoom(12.0)
                .build()
        )
        
        // Enable location if permission is granted
        if (hasLocationPermission()) {
            enableLocationDisplay()
        }
        
        methodChannel.invokeMethod("onMapReady", null)
    }
    
    @SuppressLint("MissingPermission")
    private fun enableLocationDisplay() {
        try {
            mapView.location.apply {
                locationPuck = createDefault2DPuck()
                enabled = true
            }
            methodChannel.invokeMethod("onLocationEnabled", null)
        } catch (e: Exception) {
            // If location plugin fails, just notify map is ready
            methodChannel.invokeMethod("onMapReady", null)
        }
    }
    
    private fun hasLocationPermission(): Boolean {
        return ActivityCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    override fun getView() = mapView
    
    override fun dispose() {
        try {
            mapView.onDestroy()
        } catch (e: Exception) {
            // Ignore cleanup errors
        }
    }
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "enableLocation" -> {
                if (hasLocationPermission()) {
                    enableLocationDisplay()
                    result.success("Location enabled")
                } else {
                    result.error("NO_PERMISSION", "Location permission not granted", null)
                }
            }
            "moveCamera" -> {
                val lat = call.argument<Double>("lat") ?: 0.0
                val lng = call.argument<Double>("lng") ?: 0.0
                val zoom = call.argument<Double>("zoom") ?: 12.0
                
                mapView.mapboxMap.setCamera(
                    CameraOptions.Builder()
                        .center(Point.fromLngLat(lng, lat))
                        .zoom(zoom)
                        .build()
                )
                result.success("Camera moved")
            }
            else -> result.notImplemented()
        }
    }
} 