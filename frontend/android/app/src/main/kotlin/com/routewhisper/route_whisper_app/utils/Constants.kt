package com.routewhisper.route_whisper_app.utils

import com.mapbox.geojson.Point

object Constants {
    // Default map location (San Francisco)
    val DEFAULT_MAP_CENTER = Point.fromLngLat(-122.43539772352648, 37.77440680146262)
    const val DEFAULT_ZOOM = 14.0
    
    // Navigation defaults
    const val DEFAULT_ORIGIN_LAT = 37.7749
    const val DEFAULT_ORIGIN_LNG = -122.4194
    const val DEFAULT_DEST_LAT = 34.0522
    const val DEFAULT_DEST_LNG = -118.2437
    
    // Intent extras
    const val EXTRA_START_NAVIGATION = "START_NAVIGATION"
    const val EXTRA_ORIGIN_LAT = "ORIGIN_LAT"
    const val EXTRA_ORIGIN_LNG = "ORIGIN_LNG"
    const val EXTRA_DEST_LAT = "DEST_LAT"
    const val EXTRA_DEST_LNG = "DEST_LNG"
    
    // Camera padding (multiplied by density)
    const val CAMERA_PADDING_TOP = 180.0
    const val CAMERA_PADDING_LEFT = 40.0
    const val CAMERA_PADDING_BOTTOM = 150.0
    const val CAMERA_PADDING_RIGHT = 40.0
    
    // Permissions
    val REQUIRED_PERMISSIONS = arrayOf(
        android.Manifest.permission.ACCESS_COARSE_LOCATION,
        android.Manifest.permission.ACCESS_FINE_LOCATION
    )
} 