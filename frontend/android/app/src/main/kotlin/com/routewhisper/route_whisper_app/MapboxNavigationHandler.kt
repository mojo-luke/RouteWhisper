package com.routewhisper.route_whisper_app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import com.mapbox.api.directions.v5.models.RouteOptions
import com.mapbox.geojson.Point
import com.mapbox.navigation.base.extensions.applyDefaultNavigationOptions
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.base.route.NavigationRoute
import com.mapbox.navigation.base.route.NavigationRouterCallback
import com.mapbox.navigation.base.route.RouterFailure
import com.mapbox.navigation.core.MapboxNavigation
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import io.flutter.plugin.common.MethodChannel
import android.app.Activity

class MapboxNavigationHandler(private val context: Context) {
    private var mapboxNavigation: MapboxNavigation? = null
    private var methodChannel: MethodChannel? = null
    
    fun initialize(channel: MethodChannel) {
        this.methodChannel = channel
        MapboxNavigationApp.setup(NavigationOptions.Builder(context).build())
        mapboxNavigation = MapboxNavigationApp.current()
    }
    
    @SuppressLint("MissingPermission")
    fun startNavigation(originLat: Double, originLng: Double, destLat: Double, destLng: Double) {
        if (!hasLocationPermission()) {
            requestLocationPermission()
            return
        }
        
        val origin = Point.fromLngLat(originLng, originLat)
        val destination = Point.fromLngLat(destLng, destLat)
        
        mapboxNavigation?.requestRoutes(
            RouteOptions.builder()
                .applyDefaultNavigationOptions()
                .coordinatesList(listOf(origin, destination))
                .build(),
            object : NavigationRouterCallback {
                override fun onCanceled(routeOptions: RouteOptions, routerOrigin: String) {
                    methodChannel?.invokeMethod("onError", "Route calculation canceled")
                }
                
                override fun onFailure(reasons: List<RouterFailure>, routeOptions: RouteOptions) {
                    methodChannel?.invokeMethod("onError", "Route calculation failed: ${reasons.joinToString()}")
                }
                
                override fun onRoutesReady(routes: List<NavigationRoute>, routerOrigin: String) {
                    mapboxNavigation?.setNavigationRoutes(routes)
                    mapboxNavigation?.startTripSession()
                    
                    // Send route info back to Flutter
                    val routeData = mapOf(
                        "distance" to routes.first().directionsRoute.distance(),
                        "duration" to routes.first().directionsRoute.duration(),
                        "geometry" to routes.first().directionsRoute.geometry()
                    )
                    methodChannel?.invokeMethod("onRouteReady", routeData)
                }
            }
        )
    }
    
    fun stopNavigation() {
        mapboxNavigation?.stopTripSession()
        methodChannel?.invokeMethod("onNavigationStopped", null)
    }
    
    private fun hasLocationPermission(): Boolean {
        return ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == 
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestLocationPermission() {
        if (context is Activity) {
            ActivityCompat.requestPermissions(
                context as Activity,
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                LOCATION_PERMISSION_REQUEST_CODE
            )
        }
    }

    companion object {
        private const val LOCATION_PERMISSION_REQUEST_CODE = 123
    }
} 