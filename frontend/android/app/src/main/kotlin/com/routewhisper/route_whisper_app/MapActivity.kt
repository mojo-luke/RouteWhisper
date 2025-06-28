package com.routewhisper.route_whisper_app

import android.os.Bundle
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
        // Initialize navigation manager first
        navigationManager = NavigationManager(this, mapViewManager, routeLineRenderer)
        navigationManager.initialize()
        
        // Initialize map view manager
        mapViewManager = MapViewManager(this, navigationManager.getNavigationLocationProvider())
        val mapView = mapViewManager.initializeMapView()
        
        // Initialize route line renderer
        routeLineRenderer = RouteLineRenderer(this, mapView.mapboxMap) {
            // Handle route changes if needed
        }
        
        // Set the map view as content
        setContentView(mapView)

        // Check if we should start navigation immediately
        val shouldStartNavigation = intent.getBooleanExtra(Constants.EXTRA_START_NAVIGATION, false)
        if (shouldStartNavigation) {
            val originLat = intent.getDoubleExtra(Constants.EXTRA_ORIGIN_LAT, Constants.DEFAULT_ORIGIN_LAT)
            val originLng = intent.getDoubleExtra(Constants.EXTRA_ORIGIN_LNG, Constants.DEFAULT_ORIGIN_LNG)
            val destLat = intent.getDoubleExtra(Constants.EXTRA_DEST_LAT, Constants.DEFAULT_DEST_LAT)
            val destLng = intent.getDoubleExtra(Constants.EXTRA_DEST_LNG, Constants.DEFAULT_DEST_LNG)
            
            navigationManager.scheduleNavigation(originLat, originLng, destLat, destLng)
        }
    }
} 