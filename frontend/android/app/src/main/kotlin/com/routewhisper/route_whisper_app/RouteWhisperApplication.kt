package com.routewhisper.route_whisper_app

import android.app.Application
import android.util.Log
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Application class that initializes Mapbox and creates a shared FlutterEngine.
 * The shared engine allows MainActivity and TransparentFlutterActivity to share
 * the same Flutter state and avoid engine conflicts.
 */
class RouteWhisperApplication : Application() {

    companion object {
        private const val TAG = "RouteWhisperApp"
    }

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

        // Create and cache a shared FlutterEngine for use by multiple activities
        Log.d(TAG, "Creating shared FlutterEngine...")

        val flutterEngine = FlutterEngine(this)

        // Start executing Dart code to initialize Flutter
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )

        // Cache the engine so MainActivity and TransparentFlutterActivity can use it
        FlutterEngineCache
            .getInstance()
            .put(MainActivity.SHARED_ENGINE_ID, flutterEngine)

        Log.d(TAG, "✅ Shared FlutterEngine created and cached: ${MainActivity.SHARED_ENGINE_ID}")
    }
}
