package com.routewhisper.route_whisper_app.navigation

import android.annotation.SuppressLint
import android.util.Log
import com.mapbox.common.location.Location
import com.mapbox.navigation.core.trip.session.LocationMatcherResult
import com.mapbox.navigation.core.trip.session.LocationObserver
import com.mapbox.navigation.ui.maps.camera.data.MapboxNavigationViewportDataSource
import com.mapbox.navigation.ui.maps.location.NavigationLocationProvider

class LocationTracker(
    private val navigationLocationProvider: NavigationLocationProvider,
    private val viewportDataSource: MapboxNavigationViewportDataSource?,
    private val onLocationUpdate: (Location) -> Unit = {}
) {
    
    val locationObserver = object : LocationObserver {
        override fun onNewRawLocation(rawLocation: Location) {
            Log.d(TAG, "🔄 RAW LOCATION UPDATE: ${rawLocation.latitude}, ${rawLocation.longitude}")
        }

        @SuppressLint("MissingPermission")
        override fun onNewLocationMatcherResult(locationMatcherResult: LocationMatcherResult) {
            val enhancedLocation = locationMatcherResult.enhancedLocation
            
            Log.d(TAG, "🎯 ENHANCED LOCATION UPDATE: ${enhancedLocation.latitude}, ${enhancedLocation.longitude}, bearing: ${enhancedLocation.bearing}")
            
            // Update location puck's position on the map
            navigationLocationProvider.changePosition(
                location = enhancedLocation,
                keyPoints = locationMatcherResult.keyPoints,
            )

            // Update viewportDataSource to trigger camera to follow the location
            viewportDataSource?.let { dataSource ->
                dataSource.onLocationChanged(enhancedLocation)
                dataSource.evaluate()
                Log.d(TAG, "📍 Viewport data source updated")
            }
            
            // Notify callback
            onLocationUpdate(enhancedLocation)
        }
    }
    
    companion object {
        private const val TAG = "LocationTracker"
    }
} 