package com.routewhisper.route_whisper_app.ui

import android.content.Context
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
        if (routeUpdateResult.navigationRoutes.isNotEmpty()) {
            // Generate route geometries asynchronously and render them
            routeLineApi.setNavigationRoutes(routeUpdateResult.navigationRoutes) { value ->
                mapboxMap.style?.apply { 
                    routeLineView.renderRouteDrawData(this, value) 
                }
            }
            
            // Notify that route has changed
            onRouteChanged()
        }
    }
    
    fun clearRoutes() {
        routeLineApi.clearNavigationRoutes { value ->
            mapboxMap.style?.apply { 
                routeLineView.renderRouteDrawData(this, value) 
            }
        }
    }
} 