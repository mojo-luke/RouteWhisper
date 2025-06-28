package com.routewhisper.route_whisper_app.ui

import android.annotation.SuppressLint
import android.content.Context
import android.util.Log
import com.mapbox.maps.CameraOptions
import com.mapbox.maps.EdgeInsets
import com.mapbox.maps.MapView
import com.mapbox.maps.plugin.animation.camera
import com.mapbox.maps.plugin.locationcomponent.createDefault2DPuck
import com.mapbox.maps.plugin.locationcomponent.location
import com.mapbox.navigation.ui.maps.camera.NavigationCamera
import com.mapbox.navigation.ui.maps.camera.data.MapboxNavigationViewportDataSource
import com.mapbox.navigation.ui.maps.location.NavigationLocationProvider
import com.routewhisper.route_whisper_app.utils.Constants

class MapViewManager(
    private val context: Context,
    private val navigationLocationProvider: NavigationLocationProvider
) {
    
    lateinit var mapView: MapView
    lateinit var viewportDataSource: MapboxNavigationViewportDataSource
    lateinit var navigationCamera: NavigationCamera
    
    @SuppressLint("MissingPermission")
    fun initializeMapView(): MapView {
        Log.d(TAG, "Initializing MapView")
        
        // Create a new Mapbox map
        mapView = MapView(context)
        
        // FIRST: Set up location component BEFORE setting camera
        mapView.location.apply {
            Log.d(TAG, "Setting up location component")
            setLocationProvider(navigationLocationProvider)
            
            // Create a more visible puck with higher visibility
            locationPuck = createDefault2DPuck(withBearing = true).apply {
                // The puck should be visible by default
                Log.d(TAG, "Location puck configured with bearing")
            }
            
            enabled = true
            pulsingEnabled = true  // Add pulsing for better visibility
            Log.d(TAG, "Location component enabled: $enabled, pulsing: $pulsingEnabled")
        }
        
        // THEN: Set initial camera to San Francisco ONLY for initial setup
        mapView.mapboxMap.setCamera(
            CameraOptions.Builder()
                .center(Constants.DEFAULT_MAP_CENTER)
                .zoom(Constants.DEFAULT_ZOOM)
                .build()
        )
        Log.d(TAG, "Initial camera set to San Francisco")

        // Set viewportDataSource - this is critical for following mode
        viewportDataSource = MapboxNavigationViewportDataSource(mapView.mapboxMap)

        // Set appropriate padding for navigation view
        val pixelDensity = context.resources.displayMetrics.density
        viewportDataSource.followingPadding = EdgeInsets(
            100.0 * pixelDensity,  // top
            40.0 * pixelDensity,   // left  
            200.0 * pixelDensity,  // bottom - more space for navigation info
            40.0 * pixelDensity    // right
        )

        // Initialize NavigationCamera
        navigationCamera = NavigationCamera(
            mapView.mapboxMap,
            mapView.camera,
            viewportDataSource
        )
        
        Log.d(TAG, "MapView initialization complete")
        return mapView
    }
    
    fun setToOverviewMode() {
        Log.d(TAG, "Setting camera to overview mode")
        navigationCamera.requestNavigationCameraToOverview()
    }
    
    fun setToFollowingMode() {
        Log.d(TAG, "Setting camera to following mode")
        // ONLY call the navigation camera - don't override it!
        navigationCamera.requestNavigationCameraToFollowing()
        Log.d(TAG, "Camera set to follow navigation location updates")
    }
    
    fun updateRouteInViewport(route: com.mapbox.navigation.base.route.NavigationRoute) {
        Log.d(TAG, "Updating route in viewport")
        viewportDataSource.onRouteChanged(route)
        viewportDataSource.evaluate()
        setToOverviewMode()  // Show full route first
    }
    
    // NEW: Direct location update method - FIXED VERSION
    fun updateLocationDirectly(lat: Double, lng: Double, bearing: Double = 0.0) {
        Log.d(TAG, "🎯 DIRECT location update: $lat, $lng, bearing: $bearing")
        
        // Create location object
        val location = com.mapbox.common.location.Location.Builder()
            .latitude(lat)
            .longitude(lng)
            .bearing(bearing)
            .build()
        
        // Method 1: Update via NavigationLocationProvider
        navigationLocationProvider.changePosition(location, emptyList())
        
        // Method 2: Update viewport data source for smooth following
        viewportDataSource.onLocationChanged(location)
        viewportDataSource.evaluate()
        
        // Method 3: REMOVED - Don't force camera focus every time!
        // This was causing the zoom out/in behavior
        // focusOnLocation(lat, lng, 16.0)
        
        Log.d(TAG, "✅ Direct location update completed (smooth)")
    }
    
    // Add a method for initial focus only
    fun setInitialFocus(lat: Double, lng: Double) {
        Log.d(TAG, "Setting initial camera focus: $lat, $lng")
        focusOnLocation(lat, lng, 16.0)
        // Set to following mode after initial focus
        setToFollowingMode()
    }
    
    // Force focus on actual location coordinates (for debugging)
    fun focusOnLocation(lat: Double, lng: Double, zoom: Double = 16.0) {
        Log.d(TAG, "Manually focusing camera on location: $lat, $lng")
        mapView.camera.easeTo(
            CameraOptions.Builder()
                .center(com.mapbox.geojson.Point.fromLngLat(lng, lat))
                .zoom(zoom)
                .build()
        )
    }
    
    companion object {
        private const val TAG = "MapViewManager"
    }
} 