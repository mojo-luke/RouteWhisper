package com.routewhisper.route_whisper_app.navigation

import android.annotation.SuppressLint
import androidx.activity.ComponentActivity
import com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.base.route.NavigationRoute
import com.mapbox.navigation.core.MapboxNavigation
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import com.mapbox.navigation.core.lifecycle.MapboxNavigationObserver
import com.mapbox.navigation.core.lifecycle.requireMapboxNavigation
import com.mapbox.navigation.core.replay.route.ReplayProgressObserver
import com.mapbox.navigation.core.replay.route.ReplayRouteMapper
import com.mapbox.navigation.ui.maps.location.NavigationLocationProvider
import com.routewhisper.route_whisper_app.ui.MapViewManager
import com.routewhisper.route_whisper_app.ui.RouteLineRenderer

@OptIn(ExperimentalPreviewMapboxNavigationAPI::class)
class NavigationManager(
    private val activity: ComponentActivity,
    private val mapViewManager: MapViewManager,
    private val routeLineRenderer: RouteLineRenderer
) {
    
    private lateinit var routeCalculator: RouteCalculator
    private lateinit var locationTracker: LocationTracker
    private lateinit var replayProgressObserver: ReplayProgressObserver
    private val navigationLocationProvider = NavigationLocationProvider()
    private val replayRouteMapper = ReplayRouteMapper()
    
    // Navigation state
    data class NavigationParams(
        val originLat: Double,
        val originLng: Double,
        val destLat: Double,
        val destLng: Double
    )
    
    private var pendingNavigation: NavigationParams? = null
    
    // Define MapboxNavigation - this will be ready when onAttached is called
    private val mapboxNavigation: MapboxNavigation by requireMapboxNavigation(
        onResumedObserver = object : MapboxNavigationObserver {
            @SuppressLint("MissingPermission")
            override fun onAttached(mapboxNavigation: MapboxNavigation) {
                // Initialize components that need MapboxNavigation
                routeCalculator = RouteCalculator(activity, mapboxNavigation)
                locationTracker = LocationTracker(
                    navigationLocationProvider,
                    mapViewManager.viewportDataSource
                ) { location ->
                    // Set camera to following mode when location updates
                    mapViewManager.setToFollowingMode()
                }
                
                // Register observers
                mapboxNavigation.registerRoutesObserver(routeLineRenderer.routesObserver)
                mapboxNavigation.registerLocationObserver(locationTracker.locationObserver)

                replayProgressObserver = ReplayProgressObserver(mapboxNavigation.mapboxReplayer)
                mapboxNavigation.registerRouteProgressObserver(replayProgressObserver)
                
                // Start pending navigation if we have one
                pendingNavigation?.let { params ->
                    startNavigation(params.originLat, params.originLng, params.destLat, params.destLng)
                    pendingNavigation = null
                }
            }

            override fun onDetached(mapboxNavigation: MapboxNavigation) {
                // Clean up if needed
            }
        }
    )
    
    fun initialize() {
        // Setup MapboxNavigationApp if not already setup
        if (!MapboxNavigationApp.isSetup()) {
            MapboxNavigationApp.setup(NavigationOptions.Builder(activity).build())
        }
        
        // Attach lifecycle to MapboxNavigationApp
        MapboxNavigationApp.attach(activity)
    }
    
    fun destroy() {
        MapboxNavigationApp.detach(activity)
    }
    
    fun scheduleNavigation(originLat: Double, originLng: Double, destLat: Double, destLng: Double) {
        if (::routeCalculator.isInitialized) {
            startNavigation(originLat, originLng, destLat, destLng)
        } else {
            // Store for later when MapboxNavigation is ready
            pendingNavigation = NavigationParams(originLat, originLng, destLat, destLng)
        }
    }
    
    private fun startNavigation(originLat: Double, originLng: Double, destLat: Double, destLng: Double) {
        routeCalculator.calculateRoute(
            originLat, originLng, destLat, destLng,
            object : RouteCalculator.RouteCalculationListener {
                override fun onRouteCalculated(routes: List<NavigationRoute>) {
                    if (routes.isNotEmpty()) {
                        mapViewManager.updateRouteInViewport(routes.first())
                    }
                }
                
                override fun onRouteCalculationFailed(error: String) {
                    // Error already handled in RouteCalculator
                }
                
                override fun onRouteCalculationCanceled() {
                    // Handle cancellation if needed
                }
            }
        )
    }
    
    fun getNavigationLocationProvider(): NavigationLocationProvider = navigationLocationProvider
} 