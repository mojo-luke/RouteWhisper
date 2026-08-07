package com.routewhisper.route_whisper_app

/**
 * Waypoint arrival + departure detection, extracted out of MapActivity so
 * it's testable without a live Mapbox/Android environment (MapActivity's
 * layout inflates real Mapbox views that can't run under Robolectric).
 *
 * Two independent triggers feed the same dedup state: Mapbox's
 * ArrivalObserver, and a manual leg-transition/distance fallback that
 * MapActivity's RouteProgressObserver runs on every tick (kept because the
 * ArrivalObserver can miss triggers at high simulation speeds) — whichever
 * fires first for a given leg wins, and [lastTriggeredWaypointLeg] is what
 * prevents the other path from firing again for that same leg.
 */
class WaypointArrivalTracker {
    companion object {
        const val ARRIVAL_THRESHOLD_METERS = 50.0
        const val DEPARTURE_DISTANCE_THRESHOLD_METERS = 50.0
        const val DEPARTURE_SPEED_THRESHOLD_MPH = 5.0
    }

    data class DepartureResult(val distanceMeters: Double, val speedMph: Double)

    private var previousLegIndex: Int = 0
    private var lastTriggeredWaypointLeg: Int = -1
    private var isMonitoringDeparture = false
    private var lastWaypointLat: Double? = null
    private var lastWaypointLng: Double? = null

    /** Haversine distance between two lat/lng points, in meters. */
    fun distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val earthRadiusMeters = 6371000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2)
        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return earthRadiusMeters * c
    }

    /**
     * Call on every route-progress tick. Detects a completed leg via the
     * leg-index transition (works even when Mapbox's ArrivalObserver
     * doesn't fire, e.g. at high simulation speeds). Returns the completed
     * leg index to report arrival for, or null if this isn't a fresh
     * transition or the completed leg was the final destination.
     */
    fun onLegTransition(currentLeg: Int, totalLegs: Int): Int? {
        if (currentLeg > previousLegIndex && currentLeg >= 0) {
            val completedLegIndex = previousLegIndex
            previousLegIndex = currentLeg
            return if (completedLegIndex < totalLegs - 1) completedLegIndex else null
        } else if (currentLeg >= 0 && previousLegIndex < 0) {
            previousLegIndex = currentLeg
        }
        return null
    }

    /**
     * True if [legIndex]'s arrival was already reported by either
     * detection path. Read-only — callers resolve waypoint coordinates
     * before committing to the trigger, so marking is a separate step
     * ([markArrivalTriggered]) done only once that lookup succeeds.
     */
    fun isArrivalAlreadyTriggered(legIndex: Int): Boolean = lastTriggeredWaypointLeg == legIndex

    /** Marks [legIndex] as triggered so the other detection path dedups against it. */
    fun markArrivalTriggered(legIndex: Int) {
        lastTriggeredWaypointLeg = legIndex
    }

    /**
     * Manual fallback arrival check, run alongside [onLegTransition] on
     * every route-progress tick. True if this is an intermediate waypoint
     * within the arrival threshold that hasn't already been triggered by
     * either detection path. Read-only; call [markArrivalTriggered] once
     * the caller has confirmed waypoint coordinates for this leg.
     */
    fun shouldTriggerManualArrival(legIndex: Int, totalLegs: Int, distanceRemainingMeters: Double): Boolean {
        val isIntermediateWaypoint = legIndex < totalLegs - 1
        return isIntermediateWaypoint &&
            distanceRemainingMeters <= ARRIVAL_THRESHOLD_METERS &&
            !isArrivalAlreadyTriggered(legIndex)
    }

    /** Begin watching for departure from the waypoint at (lat, lng). */
    fun startDepartureMonitoring(lat: Double, lng: Double) {
        lastWaypointLat = lat
        lastWaypointLng = lng
        isMonitoringDeparture = true
    }

    /**
     * Call on every location update while monitoring. Departure requires
     * both moving more than [DEPARTURE_DISTANCE_THRESHOLD_METERS] away
     * AND exceeding [DEPARTURE_SPEED_THRESHOLD_MPH] — distance alone could
     * just be GPS drift while parked. Clears monitoring state once it
     * fires so it doesn't report the same departure twice.
     */
    fun checkDeparture(currentLat: Double, currentLng: Double, speedMph: Double): DepartureResult? {
        val lat = lastWaypointLat
        val lng = lastWaypointLng
        if (!isMonitoringDeparture || lat == null || lng == null) return null

        val distance = distanceMeters(lat, lng, currentLat, currentLng)
        if (distance > DEPARTURE_DISTANCE_THRESHOLD_METERS && speedMph > DEPARTURE_SPEED_THRESHOLD_MPH) {
            isMonitoringDeparture = false
            lastWaypointLat = null
            lastWaypointLng = null
            return DepartureResult(distance, speedMph)
        }
        return null
    }

    /** Reset leg tracking for a new or updated navigation session. */
    fun reset() {
        previousLegIndex = 0
        lastTriggeredWaypointLeg = -1
    }
}
