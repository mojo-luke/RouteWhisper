package com.routewhisper.route_whisper_app.ui

import android.content.Context
import android.util.Log
import com.mapbox.maps.MapboxMap
import com.mapbox.navigation.core.directions.session.RoutesObserver
import com.mapbox.navigation.ui.maps.route.line.api.MapboxRouteLineApi
import com.mapbox.navigation.ui.maps.route.line.api.MapboxRouteLineView
import com.mapbox.navigation.ui.maps.route.line.model.MapboxRouteLineApiOptions
import com.mapbox.navigation.ui.maps.route.line.model.MapboxRouteLineViewOptions

class RouteLineRenderer(
    context: Context,
    private val mapboxMap: MapboxMap,
    private val onRouteChanged: () -> Unit = {}
) {
    
    private val routeLineApi = MapboxRouteLineApi(MapboxRouteLineApiOptions.Builder().build())
    private val routeLineView = MapboxRouteLineView(MapboxRouteLineViewOptions.Builder(context).build())
    
    val routesObserver = RoutesObserver { routeUpdateResult ->
        Log.d(TAG, "RoutesObserver triggered with ${routeUpdateResult.navigationRoutes.size} routes")
        
        if (routeUpdateResult.navigationRoutes.isNotEmpty()) {
            Log.d(TAG, "Rendering route line for navigation")
            
            // Generate route geometries asynchronously and render them
            routeLineApi.setNavigationRoutes(routeUpdateResult.navigationRoutes) { value ->
                Log.d(TAG, "Route line API callback received")
                mapboxMap.style?.apply { 
                    routeLineView.renderRouteDrawData(this, value)
                    Log.d(TAG, "Route line rendered to map style")
                } ?: Log.e(TAG, "Map style is null - cannot render route line")
            }
            
            // Notify that route has changed
            onRouteChanged()
        } else {
            Log.d(TAG, "No routes to render - clearing route lines")
            clearRoutes()
        }
    }
    
    fun clearRoutes() {
        Log.d(TAG, "Clearing route lines")
        routeLineApi.setNavigationRoutes(emptyList()) { value ->
            mapboxMap.style?.apply { 
                routeLineView.renderRouteDrawData(this, value) 
            }
        }
    }
    
    companion object {
        private const val TAG = "RouteLineRenderer"
    }
} 