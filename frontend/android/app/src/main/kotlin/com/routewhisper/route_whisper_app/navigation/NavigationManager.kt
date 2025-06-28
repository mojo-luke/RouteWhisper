package com.routewhisper.route_whisper_app.navigation

import android.annotation.SuppressLint
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.lifecycle.LifecycleOwner
import com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.base.route.NavigationRoute
import com.mapbox.navigation.core.MapboxNavigation
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import com.mapbox.navigation.core.lifecycle.MapboxNavigationObserver
import com.mapbox.navigation.core.lifecycle.requireMapboxNavigation
import com.mapbox.navigation.core.replay.route.ReplayProgressObserver
import com.mapbox.navigation.core.replay.route.ReplayRouteMapper
import com.mapbox.navigation.core.trip.session.LocationMatcherResult
import com.mapbox.navigation.core.trip.session.LocationObserver
import com.mapbox.navigation.ui.maps.location.NavigationLocationProvider
import com.routewhisper.route_whisper_app.ui.MapViewManager
import com.routewhisper.route_whisper_app.ui.RouteLineRenderer
import io.flutter.plugin.common.MethodChannel
import com.mapbox.maps.CameraOptions
import com.mapbox.geojson.Point

@OptIn(ExperimentalPreviewMapboxNavigationAPI::class)
class NavigationManager(
    private val activity: ComponentActivity,
    private var mapViewManager: MapViewManager? = null,
    private var routeLineRenderer: RouteLineRenderer? = null,
    private val methodChannel: MethodChannel? = null
) {
    
    // ===== NAVIGATION STATE MANAGEMENT =====
    
    enum class NavigationState {
        IDLE,           // Not navigating, no route
        CALCULATING,    // Calculating route
        READY,          // Route calculated, ready to start
        NAVIGATING,     // Active navigation in progress
        PAUSED,         // Navigation paused (future feature)
        COMPLETED,      // Navigation completed/arrived
        CANCELLED       // Navigation cancelled by user
    }
    
    data class NavigationConfig(
        val voiceEnabled: Boolean = true,
        val instructionDistance: Double = 500.0, // meters before turn
        val recalculateThreshold: Double = 50.0,  // meters off route
        val autoStartNavigation: Boolean = true,   // start navigation immediately after route calculation
        val enableSimulation: Boolean = true  // Enable simulation mode
    )
    
    // State management
    private var currentState = NavigationState.IDLE
    private val config = NavigationConfig()
    private var currentRoutes: List<NavigationRoute> = emptyList()
    
    // Callbacks for state changes
    var onNavigationStateChanged: ((NavigationState) -> Unit)? = null
    var onRouteCalculated: ((List<NavigationRoute>) -> Unit)? = null
    var onNavigationStarted: (() -> Unit)? = null
    var onNavigationCompleted: (() -> Unit)? = null
    var onNavigationCancelled: (() -> Unit)? = null
    
    // ===== EXISTING NAVIGATION COMPONENTS =====
    
    private lateinit var routeCalculator: RouteCalculator
    private lateinit var locationTracker: LocationTracker
    private lateinit var replayProgressObserver: ReplayProgressObserver
    private val navigationLocationProvider = NavigationLocationProvider()
    private val replayRouteMapper = ReplayRouteMapper()
    
    // Navigation parameters
    data class NavigationParams(
        val originLat: Double,
        val originLng: Double,
        val destLat: Double,
        val destLng: Double
    )
    
    private var pendingNavigation: NavigationParams? = null
    
    // ===== STATE MANAGEMENT METHODS =====
    
    private fun setState(newState: NavigationState) {
        if (currentState != newState) {
            val previousState = currentState
            currentState = newState
            
            Log.d(TAG, "Navigation state changed: $previousState -> $newState")
            
            // Notify observers
            onNavigationStateChanged?.invoke(newState)
            
            // Send to Flutter
            sendStateToFlutter(newState)
            
            // Handle state-specific logic
            handleStateChange(newState)
        }
    }
    
    private fun sendStateToFlutter(state: NavigationState) {
        methodChannel?.invokeMethod("navigationStateChanged", mapOf(
            "state" to state.name,
            "isNavigating" to (state == NavigationState.NAVIGATING),
            "canStart" to (state == NavigationState.READY),
            "canCancel" to (state in listOf(NavigationState.CALCULATING, NavigationState.READY, NavigationState.NAVIGATING))
        ))
    }
    
    private fun handleStateChange(newState: NavigationState) {
        when (newState) {
            NavigationState.READY -> {
                if (config.autoStartNavigation) {
                    startActiveNavigation()
                }
            }
            NavigationState.NAVIGATING -> {
                startRouteSimulation() // Add simulation when navigation starts
                onNavigationStarted?.invoke()
            }
            NavigationState.COMPLETED -> {
                stopRouteSimulation() // Stop simulation when complete
                onNavigationCompleted?.invoke()
            }
            NavigationState.CANCELLED -> {
                stopRouteSimulation() // Stop simulation when cancelled
                onNavigationCancelled?.invoke()
            }
            else -> { /* No special handling needed */ }
        }
    }
    
    // ===== ROUTE SIMULATION METHODS =====
    
    private fun startRouteSimulation() {
        if (config.enableSimulation && currentRoutes.isNotEmpty()) {
            Log.d(TAG, "Starting route simulation")
            
            val primaryRoute = currentRoutes.first()
            
            try {
                // 1. Set navigation routes
                Log.d(TAG, "Setting navigation routes for simulation")
                mapboxNavigation.setNavigationRoutes(currentRoutes)
                
                // 2. DISABLE conflicting location systems for manual simulation
                Log.d(TAG, "Disabling conflicting location observers for manual simulation")
                mapboxNavigation.unregisterLocationObserver(locationTracker.locationObserver)
                
                // 3. Don't start trip session - this prevents LocationObserver conflicts
                Log.d(TAG, "Skipping trip session to avoid location conflicts")
                
                // 4. Start manual simulation
                Log.d(TAG, "Starting manual location simulation")
                startManualLocationSimulation(primaryRoute)
                
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start route simulation", e)
            }
        } else {
            Log.w(TAG, "Cannot start simulation: routes empty=${currentRoutes.isEmpty()} or simulation disabled=${!config.enableSimulation}")
        }
    }

    // Manual simulation using route coordinates
    private fun startManualLocationSimulation(route: NavigationRoute) {
        try {
            // Get the route geometry points
            val routePoints = route.directionsRoute.geometry()?.let { geometry ->
                com.mapbox.geojson.utils.PolylineUtils.decode(geometry, 6)
            } ?: emptyList()
            
            Log.d(TAG, "Manual simulation: Found ${routePoints.size} route points")
            
            if (routePoints.isNotEmpty()) {
                // Log first few points for debugging
                routePoints.take(5).forEachIndexed { index, point ->
                    Log.d(TAG, "Route point $index: ${point.latitude()}, ${point.longitude()}")
                }
                
                // Set initial camera focus and following mode ONCE
                mapViewManager?.setInitialFocus(routePoints[0].latitude(), routePoints[0].longitude())
                
                // Start stepping through the points
                simulateLocationAlongRoute(routePoints, 0)
            } else {
                Log.e(TAG, "No route points found for manual simulation")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start manual location simulation", e)
        }
    }

    // Simulate movement along route points
    private fun simulateLocationAlongRoute(routePoints: List<com.mapbox.geojson.Point>, currentIndex: Int) {
        if (currentIndex >= routePoints.size || !isNavigating()) {
            Log.d(TAG, "Manual simulation completed or navigation stopped")
            setState(NavigationState.COMPLETED)
            return
        }
        
        val point = routePoints[currentIndex]
        val bearing = calculateBearing(routePoints, currentIndex)
        
        Log.d(TAG, "🚗 Manual simulation step $currentIndex: ${point.latitude()}, ${point.longitude()}")
        
        // Use the updated direct method (no forced camera focus)
        mapViewManager?.updateLocationDirectly(point.latitude(), point.longitude(), bearing)
        
        // Schedule next update
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            simulateLocationAlongRoute(routePoints, currentIndex + 3) // Skip 3 points for moderate speed
        }, 1500) // 1.5 second intervals
    }

    // Calculate bearing between points
    private fun calculateBearing(points: List<com.mapbox.geojson.Point>, currentIndex: Int): Double {
        if (currentIndex + 1 >= points.size) return 0.0
        
        val current = points[currentIndex]
        val next = points[currentIndex + 1]
        
        val lat1 = Math.toRadians(current.latitude())
        val lat2 = Math.toRadians(next.latitude())
        val deltaLng = Math.toRadians(next.longitude() - current.longitude())
        
        val y = Math.sin(deltaLng) * Math.cos(lat2)
        val x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(deltaLng)
        
        return Math.toDegrees(Math.atan2(y, x))
    }

    private fun stopRouteSimulation() {
        if (config.enableSimulation) {
            Log.d(TAG, "Stopping route simulation")
            try {
                // Clear any scheduled updates
                android.os.Handler(android.os.Looper.getMainLooper()).removeCallbacksAndMessages(null)
                
                // Re-enable location observer if needed
                Log.d(TAG, "Re-registering location observer")
                mapboxNavigation.registerLocationObserver(locationTracker.locationObserver)
                
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping simulation", e)
            }
        }
    }
    
    // ===== PUBLIC API =====
    
    fun getCurrentState(): NavigationState = currentState
    
    fun isNavigating(): Boolean = currentState == NavigationState.NAVIGATING
    
    fun canStartNavigation(): Boolean = currentState == NavigationState.READY
    
    fun canCancelNavigation(): Boolean = currentState in listOf(
        NavigationState.CALCULATING, 
        NavigationState.READY, 
        NavigationState.NAVIGATING
    )
    
    fun startNavigation() {
        when (currentState) {
            NavigationState.READY -> startActiveNavigation()
            NavigationState.IDLE -> {
                Log.w(TAG, "Cannot start navigation: No route calculated")
                sendErrorToFlutter("No route available. Calculate a route first.")
            }
            else -> {
                Log.w(TAG, "Cannot start navigation from state: $currentState")
                sendErrorToFlutter("Navigation already in progress or calculating")
            }
        }
    }
    
    fun cancelNavigation() {
        if (canCancelNavigation()) {
            setState(NavigationState.CANCELLED)
            clearCurrentRoute()
            setState(NavigationState.IDLE)
        }
    }
    
    fun pauseNavigation() {
        if (currentState == NavigationState.NAVIGATING) {
            mapboxNavigation.mapboxReplayer.stop()
            setState(NavigationState.PAUSED)
        }
    }
    
    fun resumeNavigation() {
        if (currentState == NavigationState.PAUSED) {
            mapboxNavigation.mapboxReplayer.play()
            setState(NavigationState.NAVIGATING)
        }
    }
    
    // Set the map components after they're created
    fun setMapComponents(mapViewManager: MapViewManager, routeLineRenderer: RouteLineRenderer) {
        this.mapViewManager = mapViewManager
        this.routeLineRenderer = routeLineRenderer
    }
    
    // ===== EXISTING MAPBOX NAVIGATION INTEGRATION =====
    
    // Fix: Use the activity as LifecycleOwner
    private val mapboxNavigation: MapboxNavigation by (activity as LifecycleOwner).requireMapboxNavigation(
        onResumedObserver = object : MapboxNavigationObserver {
            @SuppressLint("MissingPermission")
            override fun onAttached(mapboxNavigation: MapboxNavigation) {
                Log.d(TAG, "MapboxNavigation attached")
                
                // Initialize components that need MapboxNavigation
                routeCalculator = RouteCalculator(activity, mapboxNavigation)
                
                // Initialize LocationTracker (this handles location updates properly)
                locationTracker = LocationTracker(
                    navigationLocationProvider,
                    mapViewManager?.viewportDataSource
                ) { location ->
                    // Handle location updates during navigation
                    Log.d(TAG, "🚗 Navigation callback - Location update: ${location.latitude}, ${location.longitude}")
                    if (isNavigating()) {
                        // Update the viewport data source directly with the new location
                        mapViewManager?.viewportDataSource?.let { dataSource ->
                            dataSource.onLocationChanged(location)
                            dataSource.evaluate()
                        }
                        mapViewManager?.setToFollowingMode()
                    }
                }
                
                // Register observers - Use the existing LocationTracker
                routeLineRenderer?.let { renderer ->
                    mapboxNavigation.registerRoutesObserver(renderer.routesObserver)
                }
                
                // Register the LocationTracker's observer (this connects simulation to location provider)
                mapboxNavigation.registerLocationObserver(locationTracker.locationObserver)

                // Initialize replay observer
                replayProgressObserver = ReplayProgressObserver(mapboxNavigation.mapboxReplayer)
                mapboxNavigation.registerRouteProgressObserver(replayProgressObserver)
                
                Log.d(TAG, "All navigation observers registered")
                
                // Start pending navigation if we have one
                pendingNavigation?.let { params ->
                    calculateAndStartNavigation(params.originLat, params.originLng, params.destLat, params.destLng)
                    pendingNavigation = null
                }
            }

            override fun onDetached(mapboxNavigation: MapboxNavigation) {
                Log.d(TAG, "MapboxNavigation detached")
                setState(NavigationState.CANCELLED)
            }
        }
    )
    
    fun initialize() {
        Log.d(TAG, "Initializing NavigationManager")
        
        // Setup MapboxNavigationApp if not already setup
        if (!MapboxNavigationApp.isSetup()) {
            MapboxNavigationApp.setup(NavigationOptions.Builder(activity).build())
        }
        
        // Attach lifecycle to MapboxNavigationApp
        MapboxNavigationApp.attach(activity)
        
        // Initialize in IDLE state
        setState(NavigationState.IDLE)
    }
    
    fun destroy() {
        setState(NavigationState.CANCELLED)
        MapboxNavigationApp.detach(activity)
    }
    
    fun scheduleNavigation(originLat: Double, originLng: Double, destLat: Double, destLng: Double) {
        if (::routeCalculator.isInitialized) {
            calculateAndStartNavigation(originLat, originLng, destLat, destLng)
        } else {
            // Store for later when MapboxNavigation is ready
            pendingNavigation = NavigationParams(originLat, originLng, destLat, destLng)
            setState(NavigationState.CALCULATING)
        }
    }
    
    private fun calculateAndStartNavigation(originLat: Double, originLng: Double, destLat: Double, destLng: Double) {
        setState(NavigationState.CALCULATING)
        
        routeCalculator.calculateRoute(
            originLat, originLng, destLat, destLng,
            object : RouteCalculator.RouteCalculationListener {
                override fun onRouteCalculated(routes: List<NavigationRoute>) {
                    if (routes.isNotEmpty()) {
                        Log.d(TAG, "Route calculated successfully")
                        currentRoutes = routes  // Store routes for simulation
                        mapViewManager?.updateRouteInViewport(routes.first())
                        onRouteCalculated?.invoke(routes)
                        setState(NavigationState.READY)
                    } else {
                        setState(NavigationState.IDLE)
                        sendErrorToFlutter("No route found")
                    }
                }
                
                override fun onRouteCalculationFailed(error: String) {
                    setState(NavigationState.IDLE)
                    sendErrorToFlutter("Route calculation failed: $error")
                }
                
                override fun onRouteCalculationCanceled() {
                    setState(NavigationState.CANCELLED)
                    setState(NavigationState.IDLE)
                }
            }
        )
    }
    
    private fun startActiveNavigation() {
        if (currentState == NavigationState.READY) {
            Log.d(TAG, "Starting active navigation")
            setState(NavigationState.NAVIGATING)
        }
    }
    
    private fun clearCurrentRoute() {
        currentRoutes = emptyList()
        routeLineRenderer?.clearRoutes()
    }
    
    private fun sendErrorToFlutter(error: String) {
        methodChannel?.invokeMethod("navigationError", mapOf("error" to error))
    }
    
    fun getNavigationLocationProvider(): NavigationLocationProvider = navigationLocationProvider
    
    fun testLocationPuck() {
        Log.d(TAG, "Testing location puck with manual location")
        
        // Create a test location at San Francisco
        val testLocation = com.mapbox.common.location.Location.Builder()
            .latitude(37.7749)
            .longitude(-122.4194)
            .bearing(0.0)
            .build()
        
        // Manually update the location provider
        navigationLocationProvider.changePosition(testLocation, emptyList())
        
        Log.d(TAG, "Manual location set to: ${testLocation.latitude}, ${testLocation.longitude}")
        
        // Force camera to follow the location
        mapViewManager?.setToFollowingMode()
    }
    
    companion object {
        private const val TAG = "NavigationManager"
    }
} 