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
import com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI
import com.mapbox.navigation.core.MapboxNavigation
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import com.mapbox.navigation.core.trip.session.LocationMatcherResult
import com.mapbox.navigation.core.trip.session.LocationObserver
import com.mapbox.navigation.core.trip.session.RouteProgressObserver
import com.mapbox.navigation.core.trip.session.VoiceInstructionsObserver
import android.os.Handler
import android.os.Looper
import com.mapbox.navigation.core.replay.route.ReplayRouteMapper
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
import com.mapbox.navigation.ui.maps.location.NavigationLocationProvider
import com.mapbox.common.location.Location
import com.mapbox.maps.CameraOptions
import com.mapbox.maps.EdgeInsets
import com.mapbox.maps.extension.style.layers.properties.generated.Visibility
import com.mapbox.maps.plugin.animation.camera
import com.mapbox.maps.plugin.locationcomponent.location
import com.mapbox.maps.plugin.gestures.OnMoveListener
import com.mapbox.maps.plugin.gestures.gestures
import com.google.android.material.floatingactionbutton.FloatingActionButton
import android.view.View
import java.util.Locale

@OptIn(ExperimentalPreviewMapboxNavigationAPI::class)
class MapActivity : AppCompatActivity() {

    private companion object {
        private const val TAG = "MapActivity"
    }

    private var mapboxNavigation: MapboxNavigation? = null
    private lateinit var mapView: MapView

    // Location simulation components
    private val simulationHandler = Handler(Looper.getMainLooper())
    private var isSimulating = false
    private val navigationLocationProvider = NavigationLocationProvider()

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

    // Recenter button for manual camera control
    private lateinit var recenterButton: FloatingActionButton
    private var isUserControllingCamera = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_map)

        // Initialize MapView
        mapView = findViewById(R.id.mapView)

        // Initialize UI views
        maneuverView = findViewById(R.id.maneuverView)
        tripProgressView = findViewById(R.id.tripProgressView)
        recenterButton = findViewById<FloatingActionButton>(R.id.recenterButton)

        // Set up recenter button click listener
        recenterButton.setOnClickListener {
            onRecenterButtonClick()
        }

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

            // Set up location component with NavigationLocationProvider
            mapView.location.apply {
                setLocationProvider(navigationLocationProvider)
                enabled = true
                pulsingEnabled = true
                // Create navigation puck with bearing (directional arrow)
                locationPuck = com.mapbox.maps.plugin.locationcomponent.createDefault2DPuck(withBearing = true)
            }

            // Initialize route line rendering
            initializeRouteLine()

            // Initialize navigation camera
            initializeNavigationCamera()

            // Set up gesture listener to detect manual camera control
            setupGestureListener()

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

            // Start REPLAY trip session (for simulation) - this tells SDK to use internal replayer
            mapboxNavigation?.startReplayTripSession()
            Log.d(TAG, "Started replay trip session for simulation")

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

        // Initialize route line view options - render below location puck
        val routeLineViewOptions = MapboxRouteLineViewOptions.Builder(this)
            .routeLineBelowLayerId("mapbox-location-indicator-layer") // Render route below location puck
            .build()
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
            Log.d(TAG, "🎯 Route progress update: distance remaining=${routeProgress.distanceRemaining}")

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

        // Location observer - updates location puck and viewport for camera following
        mapboxNavigation?.registerLocationObserver(object : LocationObserver {
            override fun onNewRawLocation(rawLocation: Location) {
                // Not used
            }

            override fun onNewLocationMatcherResult(locationMatcherResult: LocationMatcherResult) {
                val location = locationMatcherResult.enhancedLocation
                Log.d(TAG, "📍 Location update: lat=${location.latitude}, lng=${location.longitude}, bearing=${location.bearing}")

                // Update location puck via NavigationLocationProvider
                navigationLocationProvider.changePosition(location)

                // Update viewport data source for camera following
                viewportDataSource.onLocationChanged(location)
                viewportDataSource.evaluate()
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

                    // Extract route geometry (encoded polyline) for POI discovery
                    val geometry = primaryRoute.directionsRoute.geometry()
                    if (geometry != null) {
                        Log.d(TAG, "Route geometry: ${geometry.substring(0, minOf(50, geometry.length))}... (${geometry.length} chars)")

                        // Send polyline to Flutter via MainActivity's method channel
                        runOnUiThread {
                            MainActivity.sendRoutePolyline(geometry)
                        }
                    } else {
                        Log.w(TAG, "Route geometry is null - cannot extract polyline for POI discovery")
                    }

                    // Start location simulation along the route
                    startSimulation(primaryRoute)
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

    private fun startSimulation(route: NavigationRoute) {
        Log.d(TAG, "Starting replay simulation for route")

        try {
            // Access the internal MapboxReplayer from navigation
            val mapboxReplayer = mapboxNavigation?.mapboxReplayer
            if (mapboxReplayer == null) {
                Log.e(TAG, "MapboxReplayer is null, cannot start simulation")
                return
            }

            // Clear any existing events
            mapboxReplayer.clearEvents()

            // Convert route geometry to replay events using ReplayRouteMapper
            val replayRouteMapper = ReplayRouteMapper()
            val replayEvents = replayRouteMapper.mapDirectionsRouteGeometry(route.directionsRoute)

            Log.d(TAG, "Generated ${replayEvents.size} replay events from route")

            if (replayEvents.isNotEmpty()) {
                // Push all events to the internal replayer
                mapboxReplayer.pushEvents(replayEvents)

                // Set playback speed (1.5x for faster testing)
                mapboxReplayer.playbackSpeed(1.5)

                // Seek to first location
                mapboxReplayer.seekTo(replayEvents.first())

                // Start playback - this will feed locations into MapboxNavigation automatically
                mapboxReplayer.play()

                Log.d(TAG, "Started replay playback at 1.5x speed")

                // Switch to following mode after 3 seconds
                simulationHandler.postDelayed({
                    navigationCamera.requestNavigationCameraToFollowing()
                    Log.d(TAG, "Switched camera to following mode")
                }, 3000)
            } else {
                Log.e(TAG, "No replay events generated")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start replay simulation", e)
        }
    }

    private fun stopSimulation() {
        Log.d(TAG, "Stopping replay simulation")
        try {
            mapboxNavigation?.mapboxReplayer?.stop()
            mapboxNavigation?.mapboxReplayer?.finish()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping simulation", e)
        }
    }

    private fun setupGestureListener() {
        // Listen for when user starts manually moving the camera
        mapView.gestures.addOnMoveListener(object : OnMoveListener {
            override fun onMoveBegin(detector: com.mapbox.android.gestures.MoveGestureDetector) {
                // User started panning the map
                onUserStartedManualCameraControl()
            }

            override fun onMove(detector: com.mapbox.android.gestures.MoveGestureDetector): Boolean {
                return false // Don't consume the gesture
            }

            override fun onMoveEnd(detector: com.mapbox.android.gestures.MoveGestureDetector) {
                // Move gesture ended
            }
        })

        Log.d(TAG, "Gesture listener set up for manual camera control")
    }

    private fun onUserStartedManualCameraControl() {
        if (!isUserControllingCamera) {
            Log.d(TAG, "User started manual camera control - switching to IDLE mode")
            isUserControllingCamera = true

            // Switch navigation camera to idle mode (allows free camera movement)
            navigationCamera.requestNavigationCameraToIdle()

            // Show recenter button
            recenterButton.visibility = View.VISIBLE
        }
    }

    private fun onRecenterButtonClick() {
        Log.d(TAG, "Recenter button clicked - returning to following mode")
        isUserControllingCamera = false

        // Switch back to following mode
        navigationCamera.requestNavigationCameraToFollowing()

        // Hide recenter button
        recenterButton.visibility = View.GONE
    }

    override fun onDestroy() {
        super.onDestroy()

        // Stop location simulation
        stopSimulation()

        // Clean up voice components
        speechApi.cancel()
        voiceInstructionsPlayer.shutdown()

        // Detach from lifecycle - this will automatically handle cleanup
        // No need to manually stop trip session as MapboxNavigationApp manages it
        MapboxNavigationApp.detach(this)
    }
}
