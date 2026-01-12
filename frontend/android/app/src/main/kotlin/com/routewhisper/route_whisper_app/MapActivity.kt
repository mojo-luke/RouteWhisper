package com.routewhisper.route_whisper_app

import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.snackbar.Snackbar
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
import com.mapbox.navigation.core.arrival.ArrivalObserver
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

    // Waypoint progress UI components (Google Maps style)
    private lateinit var waypointProgressCard: View
    private lateinit var waypointNameText: TextView
    private lateinit var waypointDistanceText: TextView
    private lateinit var waypointEtaText: TextView
    private lateinit var waypointStopIndicator: TextView

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

    // Waypoint arrival and departure tracking
    private var lastWaypointLocation: Point? = null
    private var isMonitoringDeparture = false
    private var lastTriggeredWaypointLeg: Int = -1  // Track which waypoint we've already triggered arrival for
    private var previousLegIndex: Int = 0  // Track previous leg to detect transitions
    private val WAYPOINT_ARRIVAL_THRESHOLD_METERS = 50.0  // 50m arrival threshold
    private var waypointNames: Array<String>? = null  // Waypoint names for UI display

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_map)

        // Initialize MapView
        mapView = findViewById(R.id.mapView)

        // Initialize UI views
        maneuverView = findViewById(R.id.maneuverView)
        tripProgressView = findViewById(R.id.tripProgressView)
        recenterButton = findViewById<FloatingActionButton>(R.id.recenterButton)

        // Initialize waypoint progress views
        waypointProgressCard = findViewById(R.id.waypointProgressCard)
        waypointNameText = findViewById(R.id.waypointNameText)
        waypointDistanceText = findViewById(R.id.waypointDistanceText)
        waypointEtaText = findViewById(R.id.waypointEtaText)
        waypointStopIndicator = findViewById(R.id.waypointStopIndicator)

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

        // Get waypoints from Intent (if provided) - flat array [lng1, lat1, lng2, lat2, ...]
        val waypointsArray = intent.getDoubleArrayExtra("waypoints")
        val waypointPoints = if (waypointsArray != null && waypointsArray.isNotEmpty()) {
            // Convert flat array back to List of Points
            waypointsArray.toList().chunked(2).map { (lng, lat) ->
                Point.fromLngLat(lng, lat)
            }
        } else {
            emptyList()
        }

        // Get waypoint names from Intent (if provided)
        waypointNames = intent.getStringArrayExtra("waypointNames")
        if (waypointNames != null && waypointNames!!.isNotEmpty()) {
            Log.d(TAG, "Received ${waypointNames!!.size} waypoint names: ${waypointNames!!.joinToString(", ")}")
        }

        Log.d(TAG, "ViewOnly mode: $viewOnly")
        if (!viewOnly) {
            if (waypointPoints.isNotEmpty()) {
                Log.d(TAG, "Received coordinates with ${waypointPoints.size} waypoints: Origin($originLat, $originLng), Dest($destLat, $destLng)")
            } else {
                Log.d(TAG, "Received coordinates: Origin($originLat, $originLng), Dest($destLat, $destLng)")
            }
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
            Log.d(TAG, "MapboxNavigation initialized, arrival threshold: default ~50m")

            // Register observers for route and location updates
            registerObservers()

            // Start REPLAY trip session (for simulation) - this tells SDK to use internal replayer
            mapboxNavigation?.startReplayTripSession()
            Log.d(TAG, "Started replay trip session for simulation")

            // Reset leg tracking for new navigation session
            previousLegIndex = 0
            lastTriggeredWaypointLeg = -1

            // Request route only if not in view-only mode and coordinates are provided
            if (!viewOnly && originLat != 0.0 && originLng != 0.0 && destLat != 0.0 && destLng != 0.0) {
                val origin = Point.fromLngLat(originLng, originLat)
                val destination = Point.fromLngLat(destLng, destLat)

                if (waypointPoints.isNotEmpty()) {
                    Log.d(TAG, "Requesting route with ${waypointPoints.size} waypoints")
                    requestRouteWithWaypoints(origin, waypointPoints, destination)
                } else {
                    Log.d(TAG, "Requesting route without waypoints")
                    requestRoute(origin, destination)
                }
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
            val currentLeg = routeProgress.currentLegProgress?.legIndex ?: -1
            val legRemaining = routeProgress.currentLegProgress?.distanceRemaining ?: 0.0

            Log.d(TAG, "🎯 Route progress: leg=$currentLeg, legRemaining=${legRemaining}m, totalRemaining=${routeProgress.distanceRemaining}m")

            // Detect leg transitions - this works even at high simulation speeds
            if (currentLeg > previousLegIndex && currentLeg >= 0) {
                Log.d(TAG, "🔄 LEG TRANSITION DETECTED: $previousLegIndex → $currentLeg")

                // We've completed the previous leg, so trigger arrival for it
                val completedLegIndex = previousLegIndex

                // Only trigger for intermediate waypoints (not final destination)
                val route = routeProgress.navigationRoute.directionsRoute
                val totalLegs = route.legs()?.size ?: 0

                if (completedLegIndex < totalLegs - 1) {
                    Log.d(TAG, "📍 WAYPOINT ARRIVAL (via leg transition): Completed leg $completedLegIndex")

                    // Get the destination coordinates of the completed leg
                    val coordinates = route.legs()?.get(completedLegIndex)?.steps()?.lastOrNull()?.maneuver()?.location()

                    if (coordinates != null) {
                        val waypointLocation = Point.fromLngLat(coordinates.longitude(), coordinates.latitude())

                        // Start monitoring for departure
                        startDepartureMonitoring(waypointLocation)

                        // TODO: TECHNICAL DEBT - Replace with full arrival notification UI
                        // This is a temporary Snackbar notification. The full implementation
                        // should include:
                        // - Overlay dialog with waypoint name and estimated stop duration
                        // - Live timer showing elapsed stop time
                        // - "I'm Here" acknowledgment button
                        // - "Continue" button for manual departure
                        // - "Skip" button to skip this waypoint
                        // See: /Users/lukesimmons/.claude/plans/bright-seeking-valley.md
                        // Phase 4, Step 4C: waypoint_arrival_notification.dart equivalent
                        runOnUiThread {
                            val waypointName = if (waypointNames != null && completedLegIndex < waypointNames!!.size) {
                                waypointNames!![completedLegIndex]
                            } else {
                                "waypoint ${completedLegIndex + 1}"
                            }

                            Snackbar.make(
                                mapView,
                                "📍 Arrived at $waypointName",
                                Snackbar.LENGTH_LONG
                            ).setAction("Continue") {
                                // User manually confirmed departure - auto-departure will also trigger
                                Log.d(TAG, "User manually confirmed departure from $waypointName")
                            }.show()
                        }

                        // Notify Flutter about arrival
                        Log.d(TAG, "Attempting to send waypoint arrival to Flutter for leg $completedLegIndex")
                        runOnUiThread {
                            try {
                                MainActivity.sendWaypointArrived(
                                    completedLegIndex,
                                    coordinates.latitude(),
                                    coordinates.longitude()
                                )
                                Log.d(TAG, "✅ sendWaypointArrived call completed")
                            } catch (e: Exception) {
                                Log.e(TAG, "❌ Error calling sendWaypointArrived: ${e.message}", e)
                            }
                        }
                    }
                }

                previousLegIndex = currentLeg
            } else if (currentLeg >= 0 && previousLegIndex < 0) {
                // Initialize previousLegIndex on first valid update
                previousLegIndex = currentLeg
                Log.d(TAG, "🎯 Initial leg: $currentLeg")
            }

            // Update maneuver view (v3: renderManeuvers takes Expected directly)
            val maneuvers = maneuverApi.getManeuvers(routeProgress)
            maneuverView.renderManeuvers(maneuvers)

            // Update trip progress view
            tripProgressView.render(tripProgressApi.getTripProgress(routeProgress))

            // Update waypoint progress card (Google Maps style)
            updateWaypointProgress(routeProgress)

            // Manual waypoint arrival detection (fallback if ArrivalObserver doesn't fire)
            // Note: With leg transition detection above, this is now a secondary backup
            checkManualWaypointArrival(routeProgress)
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

                // Check departure conditions if monitoring
                checkDepartureConditions(location)
            }
        })

        // Arrival observer - detects when user arrives at waypoints
        mapboxNavigation?.registerArrivalObserver(object : ArrivalObserver {
            override fun onWaypointArrival(routeProgress: com.mapbox.navigation.base.trip.model.RouteProgress) {
                val legIndex = routeProgress.currentLegProgress?.legIndex ?: return

                // Avoid duplicate triggers if manual detection already fired
                if (lastTriggeredWaypointLeg == legIndex) {
                    Log.d(TAG, "⏭️ Skipping duplicate arrival for leg $legIndex (already triggered)")
                    return
                }

                Log.d(TAG, "📍 ARRIVAL: Waypoint at leg $legIndex")

                // Get waypoint coordinates from the route's coordinate list
                // Leg N goes to waypoint N (leg 0 -> waypoint 0, leg 1 -> waypoint 1, etc.)
                val route = routeProgress.navigationRoute.directionsRoute
                val coordinates = route.legs()?.get(legIndex)?.steps()?.lastOrNull()?.maneuver()?.location()

                if (coordinates != null) {
                    val waypointLocation = Point.fromLngLat(coordinates.longitude(), coordinates.latitude())

                    // Mark this waypoint as triggered
                    lastTriggeredWaypointLeg = legIndex

                    // Start monitoring for departure
                    startDepartureMonitoring(waypointLocation)

                    // Notify Flutter about arrival
                    runOnUiThread {
                        MainActivity.sendWaypointArrived(
                            legIndex,
                            coordinates.latitude(),
                            coordinates.longitude()
                        )
                    }
                } else {
                    Log.w(TAG, "Could not get waypoint coordinates for leg $legIndex")
                }
            }

            override fun onNextRouteLegStart(routeLegProgress: com.mapbox.navigation.base.trip.model.RouteLegProgress) {
                val legIndex = routeLegProgress.legIndex
                Log.d(TAG, "🚀 Starting leg $legIndex")
            }

            override fun onFinalDestinationArrival(routeProgress: com.mapbox.navigation.base.trip.model.RouteProgress) {
                Log.d(TAG, "🏁 Arrived at final destination")

                runOnUiThread {
                    MainActivity.sendDestinationArrived()
                }
            }
        })

        Log.d(TAG, "All observers registered")
    }

    private fun startDepartureMonitoring(waypointLocation: Point) {
        lastWaypointLocation = waypointLocation
        isMonitoringDeparture = true
        Log.d(TAG, "🔍 Started departure monitoring for waypoint at (${waypointLocation.latitude()}, ${waypointLocation.longitude()})")
    }

    private fun checkDepartureConditions(currentLocation: Location) {
        if (!isMonitoringDeparture || lastWaypointLocation == null) return

        val distance = calculateDistance(
            lastWaypointLocation!!.latitude(),
            lastWaypointLocation!!.longitude(),
            currentLocation.latitude,
            currentLocation.longitude
        )

        // Convert speed from m/s to mph (handle null speed)
        val speedMph = (currentLocation.speed ?: 0f).toDouble() * 2.23694

        // Departure conditions: >50m away AND >5mph speed
        if (distance > 50.0 && speedMph > 5.0) {
            Log.d(TAG, "🚗 Auto-departure detected: ${String.format("%.1f", distance)}m away, ${String.format("%.1f", speedMph)}mph")

            runOnUiThread {
                MainActivity.sendAutoDepartureDetected(distance, speedMph)
            }

            // Stop monitoring once departure detected
            isMonitoringDeparture = false
            lastWaypointLocation = null
        }
    }

    /**
     * Calculate distance between two coordinates using Haversine formula
     * Returns distance in meters
     */
    private fun calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val R = 6371000.0 // Earth radius in meters
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLon / 2) * Math.sin(dLon / 2)
        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return R * c
    }

    /**
     * Manual waypoint arrival detection (fallback if ArrivalObserver doesn't trigger)
     * Checks if we're within 50m of the next waypoint destination
     */
    private fun checkManualWaypointArrival(routeProgress: com.mapbox.navigation.base.trip.model.RouteProgress) {
        val currentLegProgress = routeProgress.currentLegProgress ?: return
        val legIndex = currentLegProgress.legIndex
        val distanceToWaypoint = currentLegProgress.distanceRemaining

        // Only check intermediate waypoints (not final destination)
        val route = routeProgress.navigationRoute.directionsRoute
        val totalLegs = route.legs()?.size ?: 0
        val isIntermediateWaypoint = legIndex < totalLegs - 1

        // Check if:
        // 1. This is an intermediate waypoint (not final destination)
        // 2. We're within arrival threshold
        // 3. We haven't already triggered arrival for this waypoint
        if (isIntermediateWaypoint &&
            distanceToWaypoint <= WAYPOINT_ARRIVAL_THRESHOLD_METERS &&
            lastTriggeredWaypointLeg != legIndex) {

            Log.d(TAG, "📍 MANUAL ARRIVAL DETECTED: Waypoint at leg $legIndex, distance=${String.format("%.1f", distanceToWaypoint)}m")

            // Get waypoint coordinates
            val coordinates = route.legs()?.get(legIndex)?.steps()?.lastOrNull()?.maneuver()?.location()

            if (coordinates != null) {
                val waypointLocation = Point.fromLngLat(coordinates.longitude(), coordinates.latitude())

                // Mark this waypoint as triggered
                lastTriggeredWaypointLeg = legIndex

                // Start monitoring for departure
                startDepartureMonitoring(waypointLocation)

                // Notify Flutter about arrival
                runOnUiThread {
                    MainActivity.sendWaypointArrived(
                        legIndex,
                        coordinates.latitude(),
                        coordinates.longitude()
                    )
                }
            } else {
                Log.w(TAG, "Could not get waypoint coordinates for leg $legIndex")
            }
        }
    }

    /**
     * Update waypoint progress card with current leg information (Google Maps style)
     * Shows next waypoint name, distance, ETA, and progress indicator
     */
    private fun updateWaypointProgress(routeProgress: com.mapbox.navigation.base.trip.model.RouteProgress) {
        val currentLegProgress = routeProgress.currentLegProgress ?: return
        val legIndex = currentLegProgress.legIndex

        // Get total number of legs and intermediate waypoints
        val route = routeProgress.navigationRoute.directionsRoute
        val totalLegs = route.legs()?.size ?: 0
        val intermediateWaypointCount = if (totalLegs > 0) totalLegs - 1 else 0

        // Only show waypoint card for intermediate waypoints (not final destination)
        val isIntermediateWaypoint = legIndex < totalLegs - 1

        if (isIntermediateWaypoint && waypointNames != null && legIndex < waypointNames!!.size) {
            // Show the card
            runOnUiThread {
                waypointProgressCard.visibility = View.VISIBLE

                // Update waypoint name
                val waypointName = waypointNames!![legIndex]
                waypointNameText.text = "Next stop: $waypointName"

                // Update distance (convert meters to miles)
                val distanceMeters = currentLegProgress.distanceRemaining
                val distanceMiles = distanceMeters * 0.000621371
                waypointDistanceText.text = String.format("%.1f mi", distanceMiles)

                // Update ETA (convert seconds to minutes)
                val durationSeconds = currentLegProgress.durationRemaining
                val durationMinutes = (durationSeconds / 60).toInt()
                waypointEtaText.text = "$durationMinutes min"

                // Update stop indicator
                val stopNumber = legIndex + 1
                waypointStopIndicator.text = "Stop $stopNumber of $intermediateWaypointCount"
            }
        } else {
            // Hide the card for final destination or when no waypoint names
            runOnUiThread {
                waypointProgressCard.visibility = View.GONE
            }
        }
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

    /**
     * Request route with waypoints
     *
     * Creates a route that goes through the specified waypoints in order:
     * origin -> waypoint1 -> waypoint2 -> ... -> destination
     *
     * Mapbox Navigation SDK supports up to 25 waypoints (27 total coordinates with origin/destination)
     */
    private fun requestRouteWithWaypoints(origin: Point, waypoints: List<Point>, destination: Point) {
        Log.d(TAG, "Requesting route with waypoints:")
        Log.d(TAG, "  Origin: $origin")
        waypoints.forEachIndexed { index, waypoint ->
            Log.d(TAG, "  Waypoint ${index + 1}: $waypoint")
        }
        Log.d(TAG, "  Destination: $destination")

        // Build coordinates list: [origin, waypoint1, waypoint2, ..., destination]
        val coordinatesList = buildList {
            add(origin)
            addAll(waypoints)
            add(destination)
        }

        // Validate waypoint count (Mapbox supports up to 25 waypoints = 27 total coordinates)
        if (coordinatesList.size > 27) {
            Log.e(TAG, "Too many waypoints! Mapbox supports max 25 waypoints (27 total coordinates). Got: ${coordinatesList.size}")
            // TODO: Show error to user
            return
        }

        Log.d(TAG, "Building route with ${coordinatesList.size} total coordinates (${waypoints.size} waypoints)")

        // Note: Mapbox automatically creates route legs between each coordinate
        // No need to explicitly mark waypoint indices - legs are created implicitly
        val routeOptions = RouteOptions.builder()
            .applyDefaultNavigationOptions()
            .applyLanguageAndVoiceUnitOptions(this)
            .coordinatesList(coordinatesList) // Pass all coordinates - legs created automatically
            .build()

        val routesRequestCallback = object : NavigationRouterCallback {
            override fun onRoutesReady(
                routes: List<NavigationRoute>,
                routerOrigin: String
            ) {
                Log.d(TAG, "Routes with waypoints ready! Received ${routes.size} routes")

                if (routes.isNotEmpty()) {
                    // Set routes to MapboxNavigation
                    mapboxNavigation?.setNavigationRoutes(routes)

                    val primaryRoute = routes[0]
                    val distance = primaryRoute.directionsRoute.distance() ?: 0.0
                    val duration = primaryRoute.directionsRoute.duration() ?: 0.0
                    val legs = primaryRoute.directionsRoute.legs()
                    val legCount = legs?.size ?: 0

                    Log.d(TAG, "Primary route with waypoints: distance=${distance}m, duration=${duration}s")
                    Log.d(TAG, "Route has $legCount legs")

                    // Log each leg for debugging
                    legs?.forEachIndexed { index, leg ->
                        val legDistance = leg.distance() ?: 0.0
                        Log.d(TAG, "  Leg $index: distance=${legDistance}m")
                    }

                    // Extract route geometry for POI discovery
                    val geometry = primaryRoute.directionsRoute.geometry()
                    if (geometry != null) {
                        Log.d(TAG, "Route geometry: ${geometry.substring(0, minOf(50, geometry.length))}... (${geometry.length} chars)")

                        // Send polyline to Flutter
                        runOnUiThread {
                            MainActivity.sendRoutePolyline(geometry)
                        }
                    } else {
                        Log.w(TAG, "Route geometry is null")
                    }

                    // Start simulation along the route
                    startSimulation(primaryRoute)
                } else {
                    Log.e(TAG, "No routes with waypoints received")
                }
            }

            override fun onFailure(
                reasons: List<RouterFailure>,
                routeOptions: RouteOptions
            ) {
                Log.e(TAG, "Route request with waypoints failed: ${reasons.joinToString()}")
                // TODO: Show error to user
            }

            override fun onCanceled(
                routeOptions: RouteOptions,
                routerOrigin: String
            ) {
                Log.d(TAG, "Route request with waypoints canceled")
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

                // Set playback speed (3.0x for faster testing)
                mapboxReplayer.playbackSpeed(3.0)

                // Seek to first location
                mapboxReplayer.seekTo(replayEvents.first())

                // Start playback - this will feed locations into MapboxNavigation automatically
                mapboxReplayer.play()

                Log.d(TAG, "Started replay playback at 3.0x speed")

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
