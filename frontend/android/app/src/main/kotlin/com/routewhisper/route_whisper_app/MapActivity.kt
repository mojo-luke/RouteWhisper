package com.routewhisper.route_whisper_app

import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI
import com.routewhisper.route_whisper_app.navigation.NavigationManager
import com.routewhisper.route_whisper_app.ui.MapViewManager
import com.routewhisper.route_whisper_app.ui.RouteLineRenderer
import com.routewhisper.route_whisper_app.utils.Constants
import com.routewhisper.route_whisper_app.utils.PermissionHelper

@OptIn(ExperimentalPreviewMapboxNavigationAPI::class)
class MapActivity : ComponentActivity() {
    
    private lateinit var permissionHelper: PermissionHelper
    private lateinit var mapViewManager: MapViewManager
    private lateinit var routeLineRenderer: RouteLineRenderer
    private lateinit var navigationManager: NavigationManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        Log.d("MapActivity", "onCreate called")
        
        // Debug: Log all intent extras
        intent.extras?.let { bundle ->
            for (key in bundle.keySet()) {
                Log.d("MapActivity", "Intent extra: $key = ${bundle.get(key)}")
            }
        }

        // Initialize permission helper
        permissionHelper = PermissionHelper(
            activity = this,
            onPermissionGranted = { initializeMapComponents() },
            onPermissionDenied = {
                Toast.makeText(
                    this,
                    "Location permissions denied. Please enable permissions in settings.",
                    Toast.LENGTH_LONG
                ).show()
                finish()
            }
        )

        // Check and request permissions
        permissionHelper.checkAndRequestPermissions()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::navigationManager.isInitialized) {
            navigationManager.destroy()
        }
    }

    private fun initializeMapComponents() {
        Log.d("MapActivity", "Initializing map components")
        
        // Step 1: Create NavigationManager first (without map components)
        navigationManager = NavigationManager(this)
        
        // Step 2: Initialize map view manager
        mapViewManager = MapViewManager(this, navigationManager.getNavigationLocationProvider())
        val mapView = mapViewManager.initializeMapView()
        
        // Step 3: Initialize route line renderer
        routeLineRenderer = RouteLineRenderer(this, mapView.mapboxMap) {
            // Handle route changes if needed
        }
        
        // Step 4: Connect the components to NavigationManager
        navigationManager.setMapComponents(mapViewManager, routeLineRenderer)
        
        // Step 5: Set up state change listeners
        navigationManager.onNavigationStateChanged = { state ->
            handleNavigationStateChange(state)
        }
        
        navigationManager.onNavigationStarted = {
            Toast.makeText(this, "Navigation started", Toast.LENGTH_SHORT).show()
        }
        
        navigationManager.onNavigationCompleted = {
            Toast.makeText(this, "Navigation completed", Toast.LENGTH_SHORT).show()
        }
        
        navigationManager.onNavigationCancelled = {
            Toast.makeText(this, "Navigation cancelled", Toast.LENGTH_SHORT).show()
        }
        
        // Step 6: Initialize NavigationManager
        navigationManager.initialize()
        
        // Step 7: Set the map view as content
        setContentView(mapView)

        // Step 8: Check if we should start navigation immediately
        checkAndStartNavigation()
    }
    
    private fun checkAndStartNavigation() {
        // Check for simulation mode first
        val simulationMode = intent.getBooleanExtra("SIMULATION_MODE", false)
        val shouldStartNavigation = intent.getBooleanExtra(Constants.EXTRA_START_NAVIGATION, false)
        
        if (simulationMode || shouldStartNavigation) {
            Log.d("MapActivity", "Starting navigation - Simulation: $simulationMode, Regular: $shouldStartNavigation")
            
            val originLat = intent.getDoubleExtra("ORIGIN_LAT", Constants.DEFAULT_ORIGIN_LAT)
            val originLng = intent.getDoubleExtra("ORIGIN_LNG", Constants.DEFAULT_ORIGIN_LNG)
            val destLat = intent.getDoubleExtra("DEST_LAT", Constants.DEFAULT_DEST_LAT)
            val destLng = intent.getDoubleExtra("DEST_LNG", Constants.DEFAULT_DEST_LNG)
            
            Log.d("MapActivity", "Navigation coordinates: ($originLat, $originLng) -> ($destLat, $destLng)")
            
            if (simulationMode) {
                Toast.makeText(this, "Starting navigation simulation", Toast.LENGTH_SHORT).show()
            }
            
            navigationManager.scheduleNavigation(originLat, originLng, destLat, destLng)
        } else {
            Log.d("MapActivity", "No navigation requested - showing map only")
            Toast.makeText(this, "Map view ready", Toast.LENGTH_SHORT).show()
        }
    }
    
    private fun handleNavigationStateChange(state: NavigationManager.NavigationState) {
        Log.d("MapActivity", "Navigation state changed to: $state")
        when (state) {
            NavigationManager.NavigationState.IDLE -> {
                title = "RouteWhisper - Ready"
            }
            NavigationManager.NavigationState.CALCULATING -> {
                title = "RouteWhisper - Calculating Route..."
            }
            NavigationManager.NavigationState.READY -> {
                title = "RouteWhisper - Route Ready"
            }
            NavigationManager.NavigationState.NAVIGATING -> {
                title = "RouteWhisper - Navigating"
            }
            NavigationManager.NavigationState.COMPLETED -> {
                title = "RouteWhisper - Arrived"
            }
            NavigationManager.NavigationState.CANCELLED -> {
                title = "RouteWhisper - Cancelled"
            }
            NavigationManager.NavigationState.PAUSED -> {
                title = "RouteWhisper - Paused"
            }
        }
    }
} 