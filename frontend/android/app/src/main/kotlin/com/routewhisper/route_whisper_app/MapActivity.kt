package com.routewhisper.route_whisper_app

import android.os.Bundle
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import com.mapbox.api.directions.v5.models.RouteOptions
import com.mapbox.geojson.Point
import com.mapbox.maps.MapView
import com.mapbox.maps.Style
import com.mapbox.navigation.base.extensions.applyDefaultNavigationOptions
import com.mapbox.navigation.base.route.NavigationRoute
import com.mapbox.navigation.base.route.NavigationRouterCallback
import com.mapbox.navigation.base.route.RouterFailure
import com.mapbox.navigation.core.MapboxNavigation
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import com.mapbox.navigation.core.trip.session.RouteProgressObserver
import com.mapbox.navigation.ui.maps.route.line.api.MapboxRouteLineApi
import com.mapbox.navigation.ui.maps.route.line.api.MapboxRouteLineView
import com.mapbox.navigation.ui.maps.route.line.model.MapboxRouteLineApiOptions
import com.mapbox.navigation.ui.maps.route.line.model.MapboxRouteLineViewOptions

class MapActivity : AppCompatActivity() {

    private companion object {
        private const val TAG = "MapActivity"
    }

    private var mapboxNavigation: MapboxNavigation? = null
    private lateinit var mapView: MapView

    // Route line components
    private lateinit var routeLineApi: MapboxRouteLineApi
    private lateinit var routeLineView: MapboxRouteLineView

    // Navigation camera components (TODO: implement in next iteration)
    // private lateinit var viewportDataSource: MapboxNavigationViewportDataSource
    // private lateinit var navigationCamera: NavigationCamera

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_map)

        // Initialize MapView
        mapView = findViewById(R.id.mapView)

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

            // Initialize route line components
            initializeRouteLineComponents(style)

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

    private fun initializeRouteLineComponents(style: Style) {
        // Configure route line API
        val routeLineApiOptions = MapboxRouteLineApiOptions.Builder()
            .vanishingRouteLineEnabled(true)
            .build()

        routeLineApi = MapboxRouteLineApi(routeLineApiOptions)

        // Configure route line view
        val routeLineViewOptions = MapboxRouteLineViewOptions.Builder(this)
            .routeLineBelowLayerId("road-label")
            .build()

        routeLineView = MapboxRouteLineView(routeLineViewOptions)

        Log.d(TAG, "Route line components initialized")
    }

    // TODO: Implement navigation camera in next iteration
    // The v3 API for NavigationCamera requires different setup

    private fun registerObservers() {
        // Routes observer - updates route line when routes change
        mapboxNavigation?.registerRoutesObserver { routeUpdateResult ->
            val routes = routeUpdateResult.navigationRoutes

            if (routes.isNotEmpty()) {
                // Update route line
                val alternativesMetadata = mapboxNavigation?.getAlternativeMetadataFor(routes) ?: emptyList()
                routeLineApi.setNavigationRoutes(routes, alternativesMetadata) { value ->
                    mapView.mapboxMap.style?.let { style ->
                        routeLineView.renderRouteDrawData(style, value)
                    }
                }

                Log.d(TAG, "Route line updated with ${routes.size} routes")
            } else {
                // Clear route line when no routes - just let it be empty
                Log.d(TAG, "No routes - route line cleared")
            }
        }

        // Route progress observer - updates vanishing route line
        mapboxNavigation?.registerRouteProgressObserver(RouteProgressObserver { routeProgress ->
            routeLineApi.updateWithRouteProgress(routeProgress) { result ->
                mapView.mapboxMap.style?.let { style ->
                    routeLineView.renderRouteLineUpdate(style, result)
                }
            }
        })

        Log.d(TAG, "Observers registered")
    }

    private fun requestRoute(origin: Point, destination: Point) {
        Log.d(TAG, "Requesting route from $origin to $destination")

        val routeOptions = RouteOptions.builder()
            .applyDefaultNavigationOptions()
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

        // Detach from lifecycle - this will automatically handle cleanup
        // No need to manually stop trip session as MapboxNavigationApp manages it
        MapboxNavigationApp.detach(this)
    }
}
