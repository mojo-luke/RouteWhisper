package com.routewhisper.route_whisper_app.navigation

import android.annotation.SuppressLint
import com.mapbox.common.location.Location
import com.mapbox.navigation.core.trip.session.LocationMatcherResult
import com.mapbox.navigation.core.trip.session.LocationObserver
import com.mapbox.navigation.ui.maps.camera.data.MapboxNavigationViewportDataSource
import com.mapbox.navigation.ui.maps.location.NavigationLocationProvider

class LocationTracker(
    private val navigationLocationProvider: NavigationLocationProvider,
    private val viewportDataSource: MapboxNavigationViewportDataSource,
    private val onLocationUpdate: (Location) -> Unit = {}
) {
    
    val locationObserver = object : LocationObserver {
        override fun onNewRawLocation(rawLocation: Location) {
            // Handle raw location if needed
        }

        @SuppressLint("MissingPermission")
        override fun onNewLocationMatcherResult(locationMatcherResult: LocationMatcherResult) {
            val enhancedLocation = locationMatcherResult.enhancedLocation
            
            // Update location puck's position on the map
            navigationLocationProvider.changePosition(
                location = enhancedLocation,
                keyPoints = locationMatcherResult.keyPoints,
            )

            // Update viewportDataSource to trigger camera to follow the location
            viewportDataSource.onLocationChanged(enhancedLocation)
            viewportDataSource.evaluate()
            
            // Notify callback
            onLocationUpdate(enhancedLocation)
        }
    }
} 