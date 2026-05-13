package com.routewhisper.route_whisper_app

import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.snackbar.Snackbar
import com.mapbox.api.directions.v5.models.RouteOptions
import com.mapbox.geojson.Point
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import com.mapbox.maps.MapView
import com.mapbox.maps.Style
import com.mapbox.maps.plugin.annotation.annotations
import com.mapbox.maps.plugin.annotation.generated.OnPointAnnotationClickListener
import com.mapbox.maps.plugin.annotation.generated.PointAnnotation
import com.mapbox.maps.plugin.annotation.generated.PointAnnotationManager
import com.mapbox.maps.plugin.annotation.generated.PointAnnotationOptions
import com.mapbox.maps.plugin.annotation.generated.createPointAnnotationManager
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
import android.widget.FrameLayout
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngineCache
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
import com.mapbox.maps.CoordinateBounds
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

    companion object {
        private const val TAG = "MapActivity"

        // Store reference to current MapActivity instance for in-place updates
        internal var currentInstance: MapActivity? = null

        // User preference for Mapbox turn-by-turn voice. Default on
        // preserves legacy behavior; MainActivity flips this via the
        // `setTurnByTurnVoiceEnabled` method-channel call when the
        // user toggles the Preferences screen switch. We keep it on
        // the companion so the flag survives MapActivity recreation.
        internal var turnByTurnVoiceEnabled: Boolean = true
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

    // Narration cleanup callback. Different from the turn-by-turn one
    // because we DON'T call speechApi.clean() — narration announcements
    // weren't generated through speechApi, so cleaning them would log
    // an error or no-op. Keeping this empty consumer makes the play()
    // call signature symmetric with the turn-instruction path.
    private val narrationPlayerCallback = MapboxNavigationConsumer<SpeechAnnouncement> { /* no-op */ }

    // Recenter button for manual camera control
    private lateinit var recenterButton: FloatingActionButton
    private var isUserControllingCamera = false

    // Find Stops button for POI discovery during navigation
    private lateinit var findStopsButton: FloatingActionButton
    private lateinit var suggestStopButton: FloatingActionButton

    // In-nav surfaces pushed down from Flutter (Step 6 / Step 7 follow-up).
    private lateinit var budgetChip: TextView
    private lateinit var recommendationCard: View
    private lateinit var recommendationIcon: TextView
    private lateinit var recommendationName: TextView
    private lateinit var recommendationReason: TextView
    private lateinit var recommendationAcceptButton: View
    private lateinit var recommendationDismissButton: View

    // The id of the currently surfaced recommendation. Used as a guard
    // against stale taps after the surface was replaced or cleared.
    private var currentRecommendationPoiId: String? = null

    // Flutter overlay for POI discovery
    private lateinit var flutterContainer: FrameLayout
    private var flutterView: FlutterView? = null

    // POI map annotations — created lazily on first show, cleared on dismiss.
    // Each annotation carries the POI id in its iconImage name so taps can
    // round-trip back to Flutter for confirmation-sheet lookup.
    private var poiAnnotationManager: PointAnnotationManager? = null
    private val poiAnnotations = mutableListOf<PointAnnotation>()
    private val poiIdByAnnotation = mutableMapOf<String, String>()

    // Narration map markers — a separate annotation manager so the layer
    // can be controlled independently of the in-nav POI markers. Markers
    // persist for the whole trip (so the user sees a trail of "everywhere
    // the app pointed something out"), with at most one "active" marker
    // — the place currently being whispered about — that pulses.
    private var narrationAnnotationManager: PointAnnotationManager? = null
    // id (Wikipedia pageid) → annotation, so we can swap a static marker
    // to its active variant (and back) without rebuilding the layer.
    private val narrationAnnotationsById = mutableMapOf<String, PointAnnotation>()
    private var activeNarrationId: String? = null
    private var narrationPulseAnimator: android.animation.ValueAnimator? = null

    // Waypoint arrival and departure tracking
    private var lastWaypointLocation: Point? = null
    private var isMonitoringDeparture = false
    private var lastTriggeredWaypointLeg: Int = -1  // Track which waypoint we've already triggered arrival for
    private var previousLegIndex: Int = 0  // Track previous leg to detect transitions
    private val WAYPOINT_ARRIVAL_THRESHOLD_METERS = 50.0  // 50m arrival threshold
    private var waypointNames: Array<String>? = null  // Waypoint names for UI display

    // Track if navigation was explicitly cancelled by user (vs just closing activity)
    private var isNavigationCancelled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_map)

        // Store reference for in-place route updates
        currentInstance = this

        // Initialize MapView
        mapView = findViewById(R.id.mapView)

        // Initialize UI views
        maneuverView = findViewById(R.id.maneuverView)
        tripProgressView = findViewById(R.id.tripProgressView)
        recenterButton = findViewById<FloatingActionButton>(R.id.recenterButton)
        findStopsButton = findViewById<FloatingActionButton>(R.id.findStopsButton)
        suggestStopButton = findViewById<FloatingActionButton>(R.id.suggestStopButton)
        suggestStopButton.setOnClickListener {
            MainActivity.methodChannelInstance?.invokeMethod("suggestStopRequested", null)
        }
        flutterContainer = findViewById(R.id.flutterContainer)

        // Initialize waypoint progress views
        waypointProgressCard = findViewById(R.id.waypointProgressCard)
        waypointNameText = findViewById(R.id.waypointNameText)
        waypointDistanceText = findViewById(R.id.waypointDistanceText)
        waypointEtaText = findViewById(R.id.waypointEtaText)
        waypointStopIndicator = findViewById(R.id.waypointStopIndicator)

        // In-nav surfaces (budget chip + recommendation banner).
        budgetChip = findViewById(R.id.budgetChip)
        recommendationCard = findViewById(R.id.recommendationCard)
        recommendationIcon = findViewById(R.id.recommendationIcon)
        recommendationName = findViewById(R.id.recommendationName)
        recommendationReason = findViewById(R.id.recommendationReason)
        recommendationAcceptButton = findViewById(R.id.recommendationAcceptButton)
        recommendationDismissButton = findViewById(R.id.recommendationDismissButton)
        recommendationAcceptButton.setOnClickListener {
            val poiId = currentRecommendationPoiId ?: return@setOnClickListener
            MainActivity.methodChannelInstance?.invokeMethod(
                "recommendationAccept",
                mapOf("poiId" to poiId),
            )
            hideRecommendationBanner()
        }
        recommendationDismissButton.setOnClickListener {
            val poiId = currentRecommendationPoiId ?: return@setOnClickListener
            MainActivity.methodChannelInstance?.invokeMethod(
                "recommendationDismiss",
                mapOf("poiId" to poiId),
            )
            hideRecommendationBanner()
        }

        // Set up recenter button click listener
        recenterButton.setOnClickListener {
            onRecenterButtonClick()
        }

        // Set up find stops button click listener
        findStopsButton.setOnClickListener {
            onFindStopsButtonClick()
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

                        // TECHNICAL DEBT: Snackbar instead of rich arrival notification
                        // See TECHNICAL_DEBT.md #2 for planned rich overlay with timer/buttons
                        // This temporary Snackbar provides basic arrival notification
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
        // Gated by the user preference: when off, we don't even
        // generate the speech, saving a network round-trip per
        // instruction and silencing turn-by-turn entirely.
        mapboxNavigation?.registerVoiceInstructionsObserver(VoiceInstructionsObserver { voiceInstructions ->
            if (!turnByTurnVoiceEnabled) return@VoiceInstructionsObserver
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

                // Phase 1 narration: push the fix to Flutter so the
                // NarrationService can fire a whisper when we're close
                // to a fact. Mapbox emits speed in m/s; convert to mph
                // for Flutter's UX-facing threshold.
                val mph = location.speed?.let { it * 2.236936 } ?: 0.0
                MainActivity.sendLocationUpdate(location.latitude, location.longitude, mph)
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
     *
     * Note: Uses Flutter WaypointManager for calculation logic via method channel.
     * This keeps all waypoint logic centralized in Flutter for easier UI updates.
     */
    private fun updateWaypointProgress(routeProgress: com.mapbox.navigation.base.trip.model.RouteProgress) {
        val currentLegProgress = routeProgress.currentLegProgress ?: return
        val legIndex = currentLegProgress.legIndex
        val distanceMeters = currentLegProgress.distanceRemaining
        val durationSeconds = currentLegProgress.durationRemaining

        // Send to Flutter WaypointManager for calculation
        MainActivity.methodChannelInstance?.invokeMethod(
            "calculateWaypointProgress",
            mapOf(
                "legIndex" to legIndex,
                "distanceMeters" to distanceMeters,
                "durationSeconds" to durationSeconds
            ),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    val progressData = result as? Map<*, *>

                    runOnUiThread {
                        if (progressData != null && progressData["shouldShow"] == true) {
                            // Show the card with data from WaypointManager
                            waypointProgressCard.visibility = View.VISIBLE
                            waypointNameText.text = "Next stop: ${progressData["name"]}"
                            waypointDistanceText.text = "${progressData["distanceFormatted"]} mi"
                            waypointEtaText.text = progressData["etaFormatted"] as String
                            waypointStopIndicator.text = progressData["stopIndicator"] as String
                        } else {
                            // Hide the card (final destination or no waypoints)
                            waypointProgressCard.visibility = View.GONE
                        }
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    Log.e(TAG, "Error calculating waypoint progress: $errorMessage")
                    // Fallback: hide the card on error
                    runOnUiThread {
                        waypointProgressCard.visibility = View.GONE
                    }
                }

                override fun notImplemented() {
                    Log.w(TAG, "calculateWaypointProgress not implemented in Flutter")
                    // Fallback: hide the card
                    runOnUiThread {
                        waypointProgressCard.visibility = View.GONE
                    }
                }
            }
        )
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
                // Error is logged; future: show toast/snackbar to user
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
            // Error is logged; future: show dialog to user about waypoint limit
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
                // Error is logged; future: show toast/snackbar to user
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

                // Playback speed for the in-emulator simulation. 1.0x =
                // real time. Higher values (3.0x) get you through a long
                // test route fast, but compress the time between
                // narrations so spacing rules + the active-marker pulse
                // are hard to evaluate. Keep at 1.0x while narration UX
                // is being tuned; bump back up for non-narration testing.
                mapboxReplayer.playbackSpeed(1.0)

                // Seek to first location
                mapboxReplayer.seekTo(replayEvents.first())

                // Start playback - this will feed locations into MapboxNavigation automatically
                mapboxReplayer.play()

                Log.d(TAG, "Started replay playback at 1.0x speed")

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

    private fun onFindStopsButtonClick() {
        // Toggle: if POIs are already on the map, clear them; otherwise ask
        // Flutter to fetch+push (which will call back into showPoisOnMap).
        // The flutterContainer stays hidden — we only attach + reveal it
        // when a marker is tapped and we need to draw the confirmation sheet
        // on top of the map.
        if (poiAnnotations.isNotEmpty()) {
            clearPoisFromMap()
            return
        }

        MainActivity.methodChannelInstance?.invokeMethod(
            "requestPoisOnMap",
            null,
        )
        Log.d(TAG, "Requested POIs from Flutter")
    }

    /**
     * Make the flutterContainer visible (attaching the FlutterView lazily)
     * so a Flutter modal sheet can render on top of the map. Pair every call
     * with [hideFlutterOverlay] when the sheet dismisses, otherwise the
     * default Flutter route (home screen) keeps painting over the map.
     */
    private fun showFlutterOverlayContainer() {
        if (flutterView == null) {
            val engine = FlutterEngineCache
                .getInstance()
                .get(MainActivity.SHARED_ENGINE_ID)
            if (engine == null) {
                Log.e(TAG, "❌ Flutter engine not available")
                return
            }
            // renderTransparently=true makes the underlying SurfaceView use
            // PixelFormat.TRANSLUCENT so anywhere Flutter paints transparent
            // pixels, the native map below shows through. The Dart side must
            // cooperate by pushing a route whose chrome is also transparent —
            // otherwise the home screen's opaque Scaffold covers the map.
            val surfaceView = FlutterSurfaceView(this, true)
            flutterView = FlutterView(this, surfaceView).also { view ->
                view.setBackgroundColor(Color.TRANSPARENT)
                view.attachToFlutterEngine(engine)
                flutterContainer.addView(view)
            }
            flutterContainer.setBackgroundColor(Color.TRANSPARENT)
            Log.d(TAG, "✅ Transparent FlutterView created and attached to engine")
        }
        flutterContainer.visibility = View.VISIBLE
    }

    /**
     * Update navigation route in-place (during active navigation)
     *
     * This method allows updating the route without launching a new MapActivity,
     * which is critical for maintaining the "Never Leave Navigation" UX principle.
     *
     * Called from MainActivity when Flutter requests updateNavigationRoute.
     */
    fun updateNavigationRoute(
        originLat: Double,
        originLng: Double,
        destLat: Double,
        destLng: Double,
        waypoints: List<Point>,
        waypointNames: List<String>?
    ) {
        runOnUiThread {
            Log.d(TAG, "🔄 Updating route in-place with ${waypoints.size} waypoints")

            // Show feedback to user
            Snackbar.make(
                mapView,
                "Updating route...",
                Snackbar.LENGTH_SHORT
            ).show()

            // Reset leg tracking for updated route
            previousLegIndex = 0
            lastTriggeredWaypointLeg = -1

            // For in-nav updates the route MUST start from the user's current
            // location, not the original trip origin — otherwise the puck
            // appears to "rewind" to where the trip began. Fall back to the
            // supplied origin only if location isn't available yet.
            val live = navigationLocationProvider.lastLocation
            val origin = if (live != null) {
                Point.fromLngLat(live.longitude, live.latitude)
            } else {
                Log.w(TAG, "⚠️ No live location during route update; using supplied origin")
                Point.fromLngLat(originLng, originLat)
            }
            val destination = Point.fromLngLat(destLng, destLat)

            if (waypoints.isNotEmpty()) {
                Log.d(TAG, "Recalculating route with ${waypoints.size} waypoints from current location")
                requestRouteWithWaypoints(origin, waypoints, destination)
            } else {
                Log.d(TAG, "Recalculating route without waypoints from current location")
                requestRoute(origin, destination)
            }

            // Note: Route will update automatically when requestRouteWithWaypoints completes
            // via the callback that calls setNavigationRoutes()
        }
    }

    /**
     * Hide the Flutter overlay (called from Flutter via method channel)
     */
    fun hideFlutterOverlay() {
        runOnUiThread {
            flutterContainer.visibility = View.GONE
            Log.d(TAG, "Flutter overlay hidden")
        }
    }

    /**
     * Update the budget chip's text + color from Flutter's WaypointManager.
     * Color tiers mirror BudgetPill: green when slack > 0, amber when 0,
     * red when over. Call [clearBudgetStatusUi] to hide the chip when
     * Flutter has no budget set.
     */
    fun setBudgetStatusUi(usedMinutes: Int, totalMinutes: Int) {
        runOnUiThread {
            val remaining = totalMinutes - usedMinutes
            val (fg, bg) = when {
                remaining > 0 -> Color.parseColor("#7BE08F") to Color.parseColor("#1F3D2A")
                remaining == 0 -> Color.parseColor("#FFC857") to Color.parseColor("#3D331F")
                else -> Color.parseColor("#FF8585") to Color.parseColor("#3D1F1F")
            }
            budgetChip.text = "$usedMinutes / $totalMinutes min slack"
            budgetChip.setTextColor(fg)
            budgetChip.background?.setTint(bg)
            budgetChip.visibility = View.VISIBLE
        }
    }

    fun clearBudgetStatusUi() {
        runOnUiThread { budgetChip.visibility = View.GONE }
    }

    /**
     * Surface a recommendation banner from Flutter's RecommendationService.
     * Replaces any banner currently shown. Tapping a button posts
     * `recommendationAccept` / `recommendationDismiss` back over the
     * method channel with [poiId].
     */
    fun setRecommendationUi(
        poiId: String,
        name: String,
        category: String,
        reason: String,
    ) {
        runOnUiThread {
            currentRecommendationPoiId = poiId
            recommendationIcon.text = emojiForCategory(category)
            recommendationName.text = name
            recommendationReason.text = reason
            recommendationCard.visibility = View.VISIBLE
        }
    }

    fun clearRecommendationUi() {
        runOnUiThread { hideRecommendationBanner() }
    }

    private fun hideRecommendationBanner() {
        currentRecommendationPoiId = null
        recommendationCard.visibility = View.GONE
    }

    /**
     * Phase 1 narration: speak arbitrary text via the Mapbox voice player.
     *
     * We piggyback on MapboxVoiceInstructionsPlayer rather than spinning up a
     * separate Android TextToSpeech engine so that turn-by-turn instructions
     * and our narration share one audio-focus owner. Turn-by-turn voice still
     * preempts because both go through the same player queue, and the SDK
     * prioritizes instruction announcements.
     *
     * Synthesizes a SpeechAnnouncement directly (no speechApi.generate()
     * round-trip) so we can speak plain narration text without needing a
     * VoiceInstructions object. Skips clean() in the callback since this
     * announcement wasn't generated through speechApi and doesn't have a
     * cached audio file to release.
     */
    fun speakNarration(text: String) {
        if (!::voiceInstructionsPlayer.isInitialized) {
            Log.d(TAG, "speakNarration: voice player not yet initialized; dropping")
            return
        }
        val announcement = SpeechAnnouncement.Builder(text).build()
        voiceInstructionsPlayer.play(announcement, narrationPlayerCallback)
        Log.d(TAG, "🗣️ Narration spoken: \"${text.take(80)}...\"")
    }

    /**
     * Add a narration marker to the persistent narration layer. If
     * the id already exists we leave the existing annotation alone
     * (idempotent) — the caller can flip its active state via
     * setActiveNarrationMarker without re-adding.
     */
    fun addNarrationMarker(id: String, lat: Double, lng: Double, title: String) {
        runOnUiThread {
            ensureNarrationAnnotationManager()
            if (narrationAnnotationsById.containsKey(id)) return@runOnUiThread
            val manager = narrationAnnotationManager ?: return@runOnUiThread
            val bitmap = buildNarrationBitmap(active = false)
            val options = PointAnnotationOptions()
                .withPoint(Point.fromLngLat(lng, lat))
                .withIconImage(bitmap)
                .withIconSize(1.0)
                .withTextField(title)
                .withTextOffset(listOf(0.0, 1.6))
                .withTextSize(11.0)
                .withTextColor("#FFFFFF")
                .withTextHaloColor("#000000")
                .withTextHaloWidth(1.5)
            val annotation = manager.create(options)
            narrationAnnotationsById[id] = annotation
            Log.d(TAG, "📍 Narration marker added: $id ($title)")
        }
    }

    /**
     * Promote the marker with [id] to the active (pulsing) style.
     * Pass null to mean "no active marker right now"; the previously-
     * active marker reverts to static.
     */
    fun setActiveNarrationMarker(id: String?) {
        runOnUiThread {
            // Revert the previously active marker (if any) to static.
            activeNarrationId?.let { prev ->
                val manager = narrationAnnotationManager
                val ann = narrationAnnotationsById[prev]
                if (manager != null && ann != null) {
                    ann.iconImageBitmap = buildNarrationBitmap(active = false)
                    ann.iconSize = 1.0
                    manager.update(ann)
                }
            }
            stopNarrationPulse()
            activeNarrationId = id
            if (id == null) return@runOnUiThread

            val manager = narrationAnnotationManager ?: return@runOnUiThread
            val ann = narrationAnnotationsById[id] ?: return@runOnUiThread
            ann.iconImageBitmap = buildNarrationBitmap(active = true)
            ann.iconSize = 1.2
            manager.update(ann)
            startNarrationPulse(ann, manager)
            Log.d(TAG, "📍 Narration marker active: $id")
        }
    }

    /**
     * Wipe every narration marker from the map. Trip-scoped: called
     * on trip end / cancellation. The Discoveries-timeline slice will
     * eventually persist these per-user and rehydrate on next trip.
     */
    fun clearNarrationMarkers() {
        runOnUiThread {
            stopNarrationPulse()
            activeNarrationId = null
            val manager = narrationAnnotationManager ?: return@runOnUiThread
            if (narrationAnnotationsById.isNotEmpty()) {
                manager.delete(narrationAnnotationsById.values.toList())
                narrationAnnotationsById.clear()
            }
            Log.d(TAG, "📍 Narration markers cleared")
        }
    }

    private fun ensureNarrationAnnotationManager() {
        if (narrationAnnotationManager != null) return
        narrationAnnotationManager = mapView.annotations.createPointAnnotationManager()
        // (No click listener here yet — Phase 2 talkback will wire taps
        //  to a "replay / save / dismiss" sheet keyed by the marker id.)
    }

    /**
     * Drive a subtle scale pulse on the active marker by mutating its
     * iconSize between 1.05 and 1.35 on a 1.4s loop. We update at ~12
     * fps which is plenty for a pulse and cheap on Mapbox's
     * annotation pipeline.
     */
    private fun startNarrationPulse(
        annotation: PointAnnotation,
        manager: PointAnnotationManager,
    ) {
        val animator = android.animation.ValueAnimator.ofFloat(1.05f, 1.35f).apply {
            duration = 700
            repeatMode = android.animation.ValueAnimator.REVERSE
            repeatCount = android.animation.ValueAnimator.INFINITE
            interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            addUpdateListener { va ->
                // Only update if this animator is still the active one
                // — defensive, in case a clear/swap races.
                if (narrationPulseAnimator !== this) return@addUpdateListener
                annotation.iconSize = (va.animatedValue as Float).toDouble()
                manager.update(annotation)
            }
        }
        narrationPulseAnimator = animator
        animator.start()
    }

    private fun stopNarrationPulse() {
        narrationPulseAnimator?.cancel()
        narrationPulseAnimator = null
    }

    /**
     * Build the narration marker bitmap — a clean circle with a
     * notification-style halo on the active variant. Single accent
     * color so it reads as "RouteWhisper noticed something" rather
     * than competing with the POI-category palette.
     */
    private fun buildNarrationBitmap(active: Boolean): Bitmap {
        val size = if (active) 112 else 80
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val cx = size / 2f
        val cy = size / 2f
        val accent = Color.parseColor("#4FC3F7") // sky/teal
        if (active) {
            // Outer halo for the active marker — gives it the
            // visual "pulse" punch alongside the size animation.
            val halo = Paint().apply {
                color = Color.parseColor("#664FC3F7")
                style = Paint.Style.FILL
                isAntiAlias = true
            }
            canvas.drawCircle(cx, cy, size / 2f - 2f, halo)
        }
        val fill = Paint().apply {
            color = accent
            style = Paint.Style.FILL
            isAntiAlias = true
        }
        val stroke = Paint().apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = if (active) 6f else 5f
            isAntiAlias = true
        }
        val r = if (active) 28f else 24f
        canvas.drawCircle(cx, cy, r, fill)
        canvas.drawCircle(cx, cy, r, stroke)
        // Speech-bubble dot in the center as a tiny visual hook.
        val dot = Paint().apply {
            color = Color.WHITE
            style = Paint.Style.FILL
            isAntiAlias = true
        }
        canvas.drawCircle(cx, cy, if (active) 7f else 6f, dot)
        return bitmap
    }

    /** Mirrors the emoji set on the Flutter POI model. */
    private fun emojiForCategory(category: String): String = when (category) {
        "gas_station" -> "⛽"
        "restaurant" -> "🍽️"
        "coffee" -> "☕"
        "hotel" -> "🏨"
        "camping" -> "🏕️"
        "attraction" -> "🎯"
        "shopping" -> "🛍️"
        "scenic" -> "🏞️"
        "museum" -> "🏛️"
        "park" -> "🌳"
        "hospital" -> "🏥"
        "pharmacy" -> "💊"
        "bank" -> "🏦"
        "grocery" -> "🛒"
        else -> "📍"
    }

    /**
     * Render POIs as tappable map annotations and animate the camera to a
     * corridor-bounds overview. Replaces any previously shown POIs. Each entry
     * in [pois] is `{id, lat, lng, category}`. [bounds] is
     * `[minLng, minLat, maxLng, maxLat]` (matching POIResponse.corridor_bounds).
     */
    fun showPoisOnMap(pois: List<Map<String, Any>>, bounds: List<Double>) {
        runOnUiThread {
            ensurePoiAnnotationManager()
            clearPoiAnnotationsInternal()

            val manager = poiAnnotationManager ?: return@runOnUiThread
            for (entry in pois) {
                val id = entry["id"] as? String ?: continue
                val lat = (entry["lat"] as? Number)?.toDouble() ?: continue
                val lng = (entry["lng"] as? Number)?.toDouble() ?: continue
                val category = entry["category"] as? String ?: "default"

                val options = PointAnnotationOptions()
                    .withPoint(Point.fromLngLat(lng, lat))
                    .withIconImage(buildPoiBitmap(category))
                    .withIconSize(1.0)

                val annotation = manager.create(options)
                poiAnnotations.add(annotation)
                poiIdByAnnotation[annotation.id] = id
            }

            // Camera overview — Google-style zoom-out so the user can see
            // every POI at once. NavigationCamera is in FOLLOWING by default;
            // switching to IDLE lets us drive the camera manually.
            navigationCamera.requestNavigationCameraToIdle()
            val cameraOptions = mapView.mapboxMap.cameraForCoordinateBounds(
                CoordinateBounds(
                    Point.fromLngLat(bounds[0], bounds[1]),
                    Point.fromLngLat(bounds[2], bounds[3]),
                ),
                EdgeInsets(160.0, 64.0, 240.0, 64.0),
                null,
                null,
            )
            mapView.camera.easeTo(cameraOptions)
            recenterButton.visibility = View.VISIBLE

            Log.d(TAG, "✅ Showing ${poiAnnotations.size} POI markers")
        }
    }

    /** Remove all POI markers and return the camera to follow-mode. */
    fun clearPoisFromMap() {
        runOnUiThread {
            clearPoiAnnotationsInternal()
            navigationCamera.requestNavigationCameraToFollowing()
            recenterButton.visibility = View.GONE
            Log.d(TAG, "POI markers cleared")
        }
    }

    private fun ensurePoiAnnotationManager() {
        if (poiAnnotationManager != null) return
        val manager = mapView.annotations.createPointAnnotationManager()
        manager.addClickListener(OnPointAnnotationClickListener { annotation ->
            val poiId = poiIdByAnnotation[annotation.id]
            if (poiId != null) {
                // Reveal the Flutter overlay container so the confirmation
                // sheet (a Flutter modal) actually draws on screen. Flutter
                // will call back via "hideOverlay" once the sheet dismisses.
                showFlutterOverlayContainer()
                MainActivity.methodChannelInstance?.invokeMethod(
                    "poiTapped",
                    mapOf("poiId" to poiId),
                )
                Log.d(TAG, "POI tapped: $poiId")
            }
            true
        })
        poiAnnotationManager = manager
    }

    private fun clearPoiAnnotationsInternal() {
        val manager = poiAnnotationManager ?: return
        if (poiAnnotations.isNotEmpty()) {
            manager.delete(poiAnnotations.toList())
            poiAnnotations.clear()
        }
        poiIdByAnnotation.clear()
    }

    /**
     * Build a category-tinted circular pin bitmap. Cheap and recognisable at
     * highway speeds; can be replaced with proper drawables later without
     * touching the annotation pipeline.
     */
    private fun buildPoiBitmap(category: String): Bitmap {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val fill = Paint().apply {
            color = colorForCategory(category)
            style = Paint.Style.FILL
            isAntiAlias = true
        }
        val stroke = Paint().apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = 6f
            isAntiAlias = true
        }
        val cx = size / 2f
        val cy = size / 2f
        val radius = size / 2f - 6f
        canvas.drawCircle(cx, cy, radius, fill)
        canvas.drawCircle(cx, cy, radius, stroke)

        val glyph = glyphForCategory(category)
        val textPaint = Paint().apply {
            color = Color.WHITE
            textSize = 44f
            textAlign = Paint.Align.CENTER
            typeface = Typeface.DEFAULT_BOLD
            isAntiAlias = true
        }
        canvas.drawText(glyph, cx, cy + 16f, textPaint)

        return bitmap
    }

    private fun colorForCategory(category: String): Int = when (category) {
        "gas_station" -> Color.parseColor("#1976D2")  // blue
        "restaurant" -> Color.parseColor("#E53935")   // red
        "coffee" -> Color.parseColor("#6D4C41")       // brown
        "scenic" -> Color.parseColor("#43A047")       // green
        "hotel" -> Color.parseColor("#8E24AA")        // purple
        "attraction" -> Color.parseColor("#FB8C00")   // orange
        else -> Color.parseColor("#455A64")           // slate
    }

    private fun glyphForCategory(category: String): String = when (category) {
        "gas_station" -> "G"
        "restaurant" -> "R"
        "coffee" -> "C"
        "scenic" -> "S"
        "hotel" -> "H"
        "attraction" -> "A"
        else -> "•"
    }

    /**
     * Override back button to handle Flutter overlay or finish activity
     */
    override fun onBackPressed() {
        // If Flutter overlay is visible, hide it first
        if (flutterContainer.visibility == View.VISIBLE) {
            Log.d(TAG, "Back button pressed - hiding Flutter overlay")
            hideFlutterOverlay()
            // Also notify Flutter to pop its navigation stack
            MainActivity.methodChannelInstance?.invokeMethod("popRoute", null)
            return
        }

        Log.d(TAG, "Back button pressed - finishing activity, navigation continues")
        // Finish activity normally - navigation will continue in background
        super.onBackPressed()
    }

    override fun onDestroy() {
        super.onDestroy()

        // Clear instance reference
        currentInstance = null

        Log.d(TAG, "MapActivity destroyed - navigation continues in background")

        // Don't stop anything here - navigation should continue running in background
        // even when this activity is destroyed. This allows users to:
        // 1. Press back button to access dashboard and find POIs
        // 2. Reopen navigation view by tapping "View Navigation"
        // 3. Navigation (GPS tracking, voice guidance) continues the whole time
        //
        // Navigation will only stop when:
        // - User explicitly cancels from dashboard (handleCancelNavigation in MainActivity)
        // - App process is killed by system
        // - User completes the trip
        //
        // Note: MapboxNavigationApp is attached to the Application lifecycle (not Activity),
        // so navigation persists across activity destruction.
    }
}
