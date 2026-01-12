package com.routewhisper.route_whisper_app

import android.app.Application
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp

class RouteWhisperApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        // Initialize MapboxNavigationApp for SDK v3
        // Access token is automatically read from res/values/mapbox_access_token.xml
        // Note: Default arrival detection is 40 meters - waypoint arrivals should work
        if (!MapboxNavigationApp.isSetup()) {
            MapboxNavigationApp.setup {
                NavigationOptions.Builder(this)
                    .build()
            }
        }
    }
}
