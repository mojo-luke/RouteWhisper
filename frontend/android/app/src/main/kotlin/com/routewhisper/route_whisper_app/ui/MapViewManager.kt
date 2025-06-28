package com.routewhisper.route_whisper_app.ui

import android.annotation.SuppressLint
import android.content.Context
import com.mapbox.maps.CameraOptions
import com.mapbox.maps.EdgeInsets
import com.mapbox.maps.MapView
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
        // Create a new Mapbox map
        mapView = MapView(context)
        mapView.mapboxMap.setCamera(
            CameraOptions.Builder()
                .center(Constants.DEFAULT_MAP_CENTER)
                .zoom(Constants.DEFAULT_ZOOM)
                .build()
        )

        // Initialize location puck using navigationLocationProvider as its data source
        mapView.location.apply {
            setLocationProvider(navigationLocationProvider)
            locationPuck = createDefault2DPuck()
            enabled = true
        }

        // Set viewportDataSource, which tells the navigationCamera where to look
        viewportDataSource = MapboxNavigationViewportDataSource(mapView.mapboxMap)

        // Set padding for the navigation camera
        val pixelDensity = context.resources.displayMetrics.density
        viewportDataSource.followingPadding = EdgeInsets(
            Constants.CAMERA_PADDING_TOP * pixelDensity,
            Constants.CAMERA_PADDING_LEFT * pixelDensity,
            Constants.CAMERA_PADDING_BOTTOM * pixelDensity,
            Constants.CAMERA_PADDING_RIGHT * pixelDensity
        )

        // Initialize a NavigationCamera - use the camera plugin
        navigationCamera = NavigationCamera(
            mapView.mapboxMap,
            mapView.camera,
            viewportDataSource
        )
        
        return mapView
    }
    
    fun setToOverviewMode() {
        navigationCamera.requestNavigationCameraToOverview()
    }
    
    fun setToFollowingMode() {
        navigationCamera.requestNavigationCameraToFollowing()
    }
    
    fun updateRouteInViewport(route: com.mapbox.navigation.base.route.NavigationRoute) {
        viewportDataSource.onRouteChanged(route)
        viewportDataSource.evaluate()
        setToOverviewMode()
    }
} 