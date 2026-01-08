package com.routewhisper.route_whisper_app

import android.os.Bundle
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import com.mapbox.api.directions.v5.models.RouteOptions
import com.mapbox.geojson.Point
import com.mapbox.maps.MapView
import com.mapbox.maps.Style
import com.mapbox.maps.plugin.locationcomponent.location
import com.mapbox.navigation.base.extensions.applyDefaultNavigationOptions
import com.mapbox.navigation.base.extensions.applyLanguageAndVoiceUnitOptions
import com.mapbox.navigation.base.route.NavigationRoute
import com.mapbox.navigation.base.route.NavigationRouterCallback
import com.mapbox.navigation.base.route.RouterFailure
import com.mapbox.navigation.core.MapboxNavigation
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import com.mapbox.navigation.core.trip.session.LocationMatcherResult
import com.mapbox.navigation.core.trip.session.LocationObserver
import com.mapbox.navigation.core.trip.session.RouteProgressObserver
import com.mapbox.navigation.core.trip.session.VoiceInstructionsObserver
import com.mapbox.navigation.base.formatter.DistanceFormatterOptions
import com.mapbox.navigation.core.formatter.MapboxDistanceFormatter
import com.mapbox.navigation.tripdata.maneuver.api.MapboxManeuverApi
import com.mapbox.navigation.ui.components.maneuver.view.MapboxManeuverView
import com.mapbox.navigation.tripdata.progress.api.MapboxTripProgressApi
import com.mapbox.navigation.tripdata.progress.model.TripProgressUpdateFormatter
import com.mapbox.navigation.ui.components.tripprogress.view.MapboxTripProgressView
import com.mapbox.navigation.voice.api.MapboxSpeechApi
import com.mapbox.navigation.voice.api.MapboxVoiceInstructionsPlayer
import com.mapbox.navigation.voice.model.SpeechAnnouncement
import com.mapbox.navigation.ui.base.util.MapboxNavigationConsumer
import com.mapbox.navigation.ui.maps.route.line.api.MapboxRouteLineApi
import com.mapbox.navigation.ui.maps.route.line.api.MapboxRouteLineView
import com.mapbox.navigation.ui.maps.route.line.model.MapboxRouteLineApiOptions
import com.mapbox.navigation.ui.maps.route.line.model.MapboxRouteLineViewOptions
import com.mapbox.navigation.ui.maps.camera.NavigationCamera
import com.mapbox.navigation.ui.maps.camera.data.MapboxNavigationViewportDataSource
import com.mapbox.maps.CameraOptions
import com.mapbox.maps.EdgeInsets
import com.mapbox.maps.extension.style.layers.properties.generated.Visibility
import com.mapbox.maps.plugin.animation.camera
import com.mapbox.maps.plugin.locationcomponent.location
import java.util.Locale

class MapActivity : AppCompatActivity() {

    private companion object {
        private const val TAG = "MapActivity"
    }

    private var mapboxNavigation: MapboxNavigation? = null
    private lateinit var mapView: MapView

    // Route line components
    private lateinit var routeLineApi: MapboxRouteLineApi
    private lateinit var routeLineView: MapboxRouteLineView

    // Navigation camera components
    private lateinit var navigationCamera: NavigationCamera
    private lateinit var viewportDataSource: MapboxNavigationViewportDataSource

    // Turn-by-turn UI components
    private lateinit var maneuverApi: MapboxManeuverApi
    private lateinit var maneuverView: MapboxManeuverView

    // Trip progress components
    private lateinit var tripProgressApi: MapboxTripProgressApi
    private lateinit var tripProgressView: MapboxTripProgressView

    // Voice guidance components
    private lateinit var speechApi: MapboxSpeechApi
    private lateinit var voiceInstructionsPlayer: MapboxVoiceInstructionsPlayer

    // Voice callback for cleanup after playing
    private val voiceInstructionsPlayerCallback = MapboxNavigationConsumer<SpeechAnnouncement> { value ->
        speechApi.clean(value)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_map)

        // Initialize MapView
        mapView = findViewById(R.id.mapView)

        // Initialize UI views
        maneuverView = findViewById(R.id.maneuverView)
        tripProgressView = findViewById(R.id.tripProgressView)

        // Check if this is view-only mode (just show map without calculating new route)
        val viewOnly = intent.getBooleanExtra("viewOnly", false)

        // Get coordinates from Intent (if provided)
        val originLat = intent.getDoubleExtra("originLat", 0.0)
        val originLng = intent.getDoubleExtra("originLng", 0.0)
        val destLat = intent.getDoubleExtra("destLat", 0.0)
        val destLng = intent.getDoubleExtra("destLng", 0.0)

        Log.d(TAG, "ViewOnly mode: $viewOnly")
        if (!viewOnly) {
            Log.d(TAG, "Received coordinates: Origin($originLat, $originLng), Dest($destLat, $destLng)")
        }

        // Load map style and initialize navigation components
        mapView.mapboxMap.loadStyle(Style.MAPBOX_STREETS) { style ->
            Log.d(TAG, "Map style loaded successfully")

            // Initialize route line rendering
            initializeRouteLine()

            // Initialize navigation camera
            initializeNavigationCamera()

            // Initialize all navigation UI components
            initializeManeuverComponents()
            initializeTripProgress()
            initializeVoiceInstructions()

            // Attach to MapboxNavigationApp lifecycle
            MapboxNavigationApp.attach(this)

            // Get MapboxNavigation instance
            mapboxNavigation = MapboxNavigationApp.current()

            // Register observers for route and location updates
            registerObservers()

            // Start trip session
            mapboxNavigation?.startTripSession()

            // Request route only if not in view-only mode and coordinates are provided
            if (!viewOnly && originLat != 0.0 && originLng != 0.0 && destLat != 0.0 && destLng != 0.0) {
                Log.d(TAG, "Requesting route with provided coordinates")
                requestRoute(
                    Point.fromLngLat(originLng, originLat),
                    Point.fromLngLat(destLng, destLat)
                )
            } else {
                Log.d(TAG, "View-only mode or no coordinates - showing current map state")
            }
        }
    }

    private fun initializeRouteLine() {
        // Initialize route line API options
        val routeLineOptions = MapboxRouteLineApiOptions.Builder().build()
        routeLineApi = MapboxRouteLineApi(routeLineOptions)

        // Initialize route line view options
        val routeLineViewOptions = MapboxRouteLineViewOptions.Builder(this).build()
        routeLineView = MapboxRouteLineView(routeLineViewOptions)

        Log.d(TAG, "Route line components initialized")
    }

    private fun initializeNavigationCamera() {
        // Create viewport data source with padding for UI elements
        viewportDataSource = MapboxNavigationViewportDataSource(
            mapView.mapboxMap
        )

        // Set padding to account for maneuver view at top and trip progress at bottom
        viewportDataSource.overviewPadding = EdgeInsets(140.0, 40.0, 120.0, 40.0)
        viewportDataSource.followingPadding = EdgeInsets(180.0, 40.0, 150.0, 40.0)

        // Create navigation camera
        navigationCamera = NavigationCamera(
            mapView.mapboxMap,
            mapView.camera,
            viewportDataSource
        )

        Log.d(TAG, "Navigation camera initialized")
    }

    private fun initializeManeuverComponents() {
        // Initialize distance formatter
        val distanceFormatterOptions = DistanceFormatterOptions.Builder(this).build()
        val distanceFormatter = MapboxDistanceFormatter(distanceFormatterOptions)

        // Initialize maneuver API with distance formatter
        maneuverApi = MapboxManeuverApi(distanceFormatter)

        Log.d(TAG, "Maneuver components initialized")
    }

    private fun initializeTripProgress() {
        // Initialize trip progress API with formatter
        val formatter = TripProgressUpdateFormatter.Builder(this).build()
        tripProgressApi = MapboxTripProgressApi(formatter)

        Log.d(TAG, "Trip progress initialized")
    }

    private fun initializeVoiceInstructions() {
        // Initialize speech API (v3 reads accessToken from MapboxOptions)
        speechApi = MapboxSpeechApi(this, Locale.US.toLanguageTag())

        // Initialize voice player
        voiceInstructionsPlayer = MapboxVoiceInstructionsPlayer(this, Locale.US.toLanguageTag())

        Log.d(TAG, "Voice instructions initialized")
    }

    private fun registerObservers() {
        // Routes observer - renders route line and updates camera when routes change
        mapboxNavigation?.registerRoutesObserver { routeUpdateResult ->
            val routes = routeUpdateResult.navigationRoutes

            if (routes.isNotEmpty()) {
                // Render route line on map
                routeLineApi.setNavigationRoutes(routes) { value ->
                    mapView.mapboxMap.style?.let { style ->
                        routeLineView.renderRouteDrawData(style, value)
                    }
                }

                // Update camera to show the route
                viewportDataSource.onRouteChanged(routes.first())
                viewportDataSource.evaluate()

                // Zoom camera to show full route (overview mode)
                navigationCamera.requestNavigationCameraToOverview()

                Log.d(TAG, "Route line rendered with ${routes.size} routes and camera zoomed to route")
            } else {
                // Clear route line when no routes
                routeLineApi.clearRouteLine { value ->
                    mapView.mapboxMap.style?.let { style ->
                        routeLineView.renderClearRouteLineValue(style, value)
                    }
                }
                Log.d(TAG, "Route line cleared")
            }
        }

        // Route progress observer - updates maneuvers and trip progress
        mapboxNavigation?.registerRouteProgressObserver(RouteProgressObserver { routeProgress ->
            // Update maneuver view (v3: renderManeuvers takes Expected directly)
            val maneuvers = maneuverApi.getManeuvers(routeProgress)
            maneuverView.renderManeuvers(maneuvers)

            // Update trip progress view
            tripProgressView.render(tripProgressApi.getTripProgress(routeProgress))
        })

        // Voice instructions observer - plays audio guidance (v3: includes cleanup callback)
        mapboxNavigation?.registerVoiceInstructionsObserver(VoiceInstructionsObserver { voiceInstructions ->
            speechApi.generate(voiceInstructions) { expected ->
                expected.fold(
                    { error ->
                        // Use fallback if speech generation fails
                        Log.e(TAG, "Error generating speech: $error")
                        voiceInstructionsPlayer.play(error.fallback, voiceInstructionsPlayerCallback)
                    },
                    { value ->
                        // Play the generated speech
                        voiceInstructionsPlayer.play(value.announcement, voiceInstructionsPlayerCallback)
                    }
                )
            }
        })

        Log.d(TAG, "All observers registered")
    }

    private fun requestRoute(origin: Point, destination: Point) {
        Log.d(TAG, "Requesting route from $origin to $destination")

        val routeOptions = RouteOptions.builder()
            .applyDefaultNavigationOptions()
            .applyLanguageAndVoiceUnitOptions(this) // Sets language/units based on device locale
            .coordinatesList(listOf(origin, destination))
            .build()

        val routesRequestCallback = object : NavigationRouterCallback {
            override fun onRoutesReady(
                routes: List<NavigationRoute>,
                routerOrigin: String
            ) {
                Log.d(TAG, "Routes ready! Received ${routes.size} routes")

                if (routes.isNotEmpty()) {
                    // Set routes to MapboxNavigation - this triggers the routes observer
                    mapboxNavigation?.setNavigationRoutes(routes)

                    val primaryRoute = routes[0]
                    val distance = primaryRoute.directionsRoute.distance() ?: 0.0
                    val duration = primaryRoute.directionsRoute.duration() ?: 0.0

                    Log.d(TAG, "Primary route: distance=${distance}m, duration=${duration}s")
                } else {
                    Log.e(TAG, "No routes received")
                }
            }

            override fun onFailure(
                reasons: List<RouterFailure>,
                routeOptions: RouteOptions
            ) {
                Log.e(TAG, "Route request failed: ${reasons.joinToString()}")
                // TODO: Show error to user
            }

            override fun onCanceled(
                routeOptions: RouteOptions,
                routerOrigin: String
            ) {
                Log.d(TAG, "Route request canceled")
            }
        }

        mapboxNavigation?.requestRoutes(routeOptions, routesRequestCallback)
    }

    override fun onDestroy() {
        super.onDestroy()

        // Clean up voice components
        speechApi.cancel()
        voiceInstructionsPlayer.shutdown()

        // Detach from lifecycle - this will automatically handle cleanup
        // No need to manually stop trip session as MapboxNavigationApp manages it
        MapboxNavigationApp.detach(this)
    }
}
