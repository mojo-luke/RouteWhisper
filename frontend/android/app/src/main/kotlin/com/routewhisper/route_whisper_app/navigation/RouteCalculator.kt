package com.routewhisper.route_whisper_app.navigation

import android.widget.Toast
import androidx.activity.ComponentActivity
import com.mapbox.api.directions.v5.models.RouteOptions
import com.mapbox.geojson.Point
import com.mapbox.navigation.base.extensions.applyDefaultNavigationOptions
import com.mapbox.navigation.base.route.NavigationRoute
import com.mapbox.navigation.base.route.NavigationRouterCallback
import com.mapbox.navigation.base.route.RouterFailure
import com.mapbox.navigation.core.MapboxNavigation

class RouteCalculator(
    private val activity: ComponentActivity,
    private val mapboxNavigation: MapboxNavigation
) {
    
    interface RouteCalculationListener {
        fun onRouteCalculated(routes: List<NavigationRoute>)
        fun onRouteCalculationFailed(error: String)
        fun onRouteCalculationCanceled()
    }
    
    fun calculateRoute(
        originLat: Double, 
        originLng: Double, 
        destLat: Double, 
        destLng: Double,
        listener: RouteCalculationListener? = null
    ) {
        val origin = Point.fromLngLat(originLng, originLat)
        val destination = Point.fromLngLat(destLng, destLat)

        mapboxNavigation.requestRoutes(
            RouteOptions.builder()
                .applyDefaultNavigationOptions()
                .coordinatesList(listOf(origin, destination))
                .build(),
            object : NavigationRouterCallback {
                override fun onRoutesReady(routes: List<NavigationRoute>, routerOrigin: String) {
                    if (routes.isNotEmpty()) {
                        mapboxNavigation.setNavigationRoutes(routes)
                        listener?.onRouteCalculated(routes)
                    } else {
                        val error = "No routes found"
                        Toast.makeText(activity, error, Toast.LENGTH_SHORT).show()
                        listener?.onRouteCalculationFailed(error)
                    }
                }

                override fun onFailure(reasons: List<RouterFailure>, routeOptions: RouteOptions) {
                    val error = "Failed to calculate route: ${reasons.firstOrNull()?.message ?: "Unknown error"}"
                    Toast.makeText(activity, error, Toast.LENGTH_SHORT).show()
                    listener?.onRouteCalculationFailed(error)
                }

                override fun onCanceled(routeOptions: RouteOptions, routerOrigin: String) {
                    listener?.onRouteCalculationCanceled()
                }
            }
        )
    }
} 