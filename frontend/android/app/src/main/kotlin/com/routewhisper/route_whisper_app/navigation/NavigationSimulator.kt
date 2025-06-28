package com.routewhisper.route_whisper_app.navigation

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.mapbox.navigation.base.route.NavigationRoute
import com.routewhisper.route_whisper_app.ui.MapViewManager
import kotlin.math.*

class NavigationSimulator(
    private val mapViewManager: MapViewManager,
    private val onSimulationComplete: () -> Unit = {}
) {
    
    private var isSimulating = false
    private var simulationHandler: Handler? = null
    private var currentRoutePoints: List<com.mapbox.geojson.Point> = emptyList()
    
    fun startSimulation(route: NavigationRoute) {
        if (isSimulating) {
            Log.w(TAG, "Simulation already running")
            return
        }
        
        Log.d(TAG, "Starting route simulation")
        
        try {
            // Extract route points from geometry
            currentRoutePoints = extractRoutePoints(route)
            
            if (currentRoutePoints.isNotEmpty()) {
                Log.d(TAG, "Simulation: Found ${currentRoutePoints.size} route points")
                
                // Log first few points for debugging
                currentRoutePoints.take(5).forEachIndexed { index, point ->
                    Log.d(TAG, "Route point $index: ${point.latitude()}, ${point.longitude()}")
                }
                
                // Set initial camera focus
                mapViewManager.setInitialFocus(
                    currentRoutePoints[0].latitude(), 
                    currentRoutePoints[0].longitude()
                )
                
                // Start simulation
                isSimulating = true
                simulationHandler = Handler(Looper.getMainLooper())
                stepThroughRoute(0)
                
            } else {
                Log.e(TAG, "No route points found for simulation")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start simulation", e)
        }
    }
    
    fun stopSimulation() {
        Log.d(TAG, "Stopping route simulation")
        isSimulating = false
        simulationHandler?.removeCallbacksAndMessages(null)
        simulationHandler = null
        currentRoutePoints = emptyList()
    }
    
    fun isRunning(): Boolean = isSimulating
    
    // Private methods
    
    private fun extractRoutePoints(route: NavigationRoute): List<com.mapbox.geojson.Point> {
        return try {
            route.directionsRoute.geometry()?.let { geometry ->
                com.mapbox.geojson.utils.PolylineUtils.decode(geometry, 6)
            } ?: emptyList()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to extract route points", e)
            emptyList()
        }
    }
    
    private fun stepThroughRoute(currentIndex: Int) {
        if (!isSimulating || currentIndex >= currentRoutePoints.size) {
            Log.d(TAG, "Simulation completed or stopped")
            isSimulating = false
            onSimulationComplete()
            return
        }
        
        val point = currentRoutePoints[currentIndex]
        val bearing = calculateBearing(currentRoutePoints, currentIndex)
        
        Log.d(TAG, "🚗 Simulation step $currentIndex: ${point.latitude()}, ${point.longitude()}")
        
        // Update location
        mapViewManager.updateLocationDirectly(point.latitude(), point.longitude(), bearing)
        
        // Schedule next update
        simulationHandler?.postDelayed({
            stepThroughRoute(currentIndex + POINT_SKIP_COUNT)
        }, UPDATE_INTERVAL_MS)
    }
    
    private fun calculateBearing(points: List<com.mapbox.geojson.Point>, currentIndex: Int): Double {
        if (currentIndex + 1 >= points.size) return 0.0
        
        val current = points[currentIndex]
        val next = points[currentIndex + 1]
        
        val lat1 = Math.toRadians(current.latitude())
        val lat2 = Math.toRadians(next.latitude())
        val deltaLng = Math.toRadians(next.longitude() - current.longitude())
        
        val y = sin(deltaLng) * cos(lat2)
        val x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLng)
        
        return Math.toDegrees(atan2(y, x))
    }
    
    companion object {
        private const val TAG = "NavigationSimulator"
        private const val UPDATE_INTERVAL_MS = 1500L  // 1.5 seconds between updates
        private const val POINT_SKIP_COUNT = 3        // Skip 3 points for moderate speed
    }
} 