package com.routewhisper.route_whisper_app

import android.app.Application
import android.util.Log
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ProcessLifecycleOwner
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Application class that initializes Mapbox and creates a shared FlutterEngine.
 * The shared engine is used by MainActivity (Flutter host) and the FlutterView
 * embedded in MapActivity for in-nav overlays — both share the same Dart isolate
 * so Provider state is preserved across the activity boundary.
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

        // Cache the engine so MainActivity and MapActivity's FlutterView can use it
        FlutterEngineCache
            .getInstance()
            .put(MainActivity.SHARED_ENGINE_ID, flutterEngine)

        Log.d(TAG, "✅ Shared FlutterEngine created and cached: ${MainActivity.SHARED_ENGINE_ID}")

        // Drive the shared engine's lifecycle channel from the *process* lifecycle, not
        // any single activity's. ProcessLifecycleOwner only fires ON_RESUME when the first
        // activity foregrounds and ON_STOP when the last activity backgrounds — so
        // activity-to-activity hops (MainActivity → MapActivity) don't toggle it. Per-activity
        // dispatch (FlutterActivity's default) caused MainActivity.onStop to clobber the
        // engine into `paused` after MapActivity had already resumed it, which froze setState
        // calls in overlay widgets like POIDashboard.
        ProcessLifecycleOwner.get().lifecycle.addObserver(
            LifecycleEventObserver { _, event ->
                when (event) {
                    Lifecycle.Event.ON_RESUME -> {
                        Log.d(TAG, "🟢 ProcessLifecycle ON_RESUME -> appIsResumed")
                        flutterEngine.lifecycleChannel.appIsResumed()
                    }
                    Lifecycle.Event.ON_PAUSE -> {
                        Log.d(TAG, "🟡 ProcessLifecycle ON_PAUSE -> appIsInactive")
                        flutterEngine.lifecycleChannel.appIsInactive()
                    }
                    Lifecycle.Event.ON_STOP -> {
                        Log.d(TAG, "🔴 ProcessLifecycle ON_STOP -> appIsPaused")
                        flutterEngine.lifecycleChannel.appIsPaused()
                    }
                    else -> Unit
                }
            }
        )
    }
}
