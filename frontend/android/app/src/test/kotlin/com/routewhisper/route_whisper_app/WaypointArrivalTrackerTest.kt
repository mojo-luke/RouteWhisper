package com.routewhisper.route_whisper_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Plain-JUnit tests for WaypointArrivalTracker — no Robolectric needed
 * since the class has zero Android/Mapbox dependencies. Mirrors the
 * arrival/departure decision logic that used to live inline in
 * MapActivity, which couldn't be unit-tested there because MapActivity's
 * layout inflates real Mapbox views.
 */
class WaypointArrivalTrackerTest {

    private lateinit var tracker: WaypointArrivalTracker

    // San Francisco-ish base point, used for departure distance checks.
    private val baseLat = 37.7749
    private val baseLng = -122.4194

    @Before
    fun setup() {
        tracker = WaypointArrivalTracker()
    }

    // --- distanceMeters (Haversine) ---

    @Test
    fun `distanceMeters is zero for identical points`() {
        assertEquals(0.0, tracker.distanceMeters(baseLat, baseLng, baseLat, baseLng), 0.01)
    }

    @Test
    fun `distanceMeters is about 111km per degree of latitude`() {
        val distance = tracker.distanceMeters(0.0, 0.0, 1.0, 0.0)
        assertEquals(111195.0, distance, 100.0)
    }

    // --- onLegTransition ---

    @Test
    fun `onLegTransition fires for an intermediate leg completion`() {
        val completed = tracker.onLegTransition(currentLeg = 1, totalLegs = 3)
        assertEquals(0, completed)
    }

    @Test
    fun `onLegTransition does not fire when leg index has not advanced`() {
        tracker.onLegTransition(currentLeg = 1, totalLegs = 3)
        val secondCall = tracker.onLegTransition(currentLeg = 1, totalLegs = 3)
        assertNull(secondCall)
    }

    @Test
    fun `onLegTransition tracks successive intermediate completions`() {
        assertEquals(0, tracker.onLegTransition(currentLeg = 1, totalLegs = 3))
        assertEquals(1, tracker.onLegTransition(currentLeg = 2, totalLegs = 3))
    }

    @Test
    fun `onLegTransition does not fire when the completed leg is the final leg`() {
        // Advance to the last leg of a 2-leg route (fires, since leg 0 is intermediate).
        assertEquals(0, tracker.onLegTransition(currentLeg = 1, totalLegs = 2))
        // A further transition off the final leg should not report arrival.
        assertNull(tracker.onLegTransition(currentLeg = 2, totalLegs = 2))
    }

    // --- shouldTriggerManualArrival / isArrivalAlreadyTriggered / markArrivalTriggered ---

    @Test
    fun `shouldTriggerManualArrival fires within threshold for an intermediate waypoint`() {
        assertTrue(tracker.shouldTriggerManualArrival(legIndex = 0, totalLegs = 2, distanceRemainingMeters = 30.0))
    }

    @Test
    fun `shouldTriggerManualArrival does not fire outside the arrival threshold`() {
        assertFalse(tracker.shouldTriggerManualArrival(legIndex = 0, totalLegs = 2, distanceRemainingMeters = 100.0))
    }

    @Test
    fun `shouldTriggerManualArrival does not fire for the final leg`() {
        assertFalse(tracker.shouldTriggerManualArrival(legIndex = 1, totalLegs = 2, distanceRemainingMeters = 10.0))
    }

    @Test
    fun `shouldTriggerManualArrival does not fire once the leg is already triggered`() {
        tracker.markArrivalTriggered(0)
        assertFalse(tracker.shouldTriggerManualArrival(legIndex = 0, totalLegs = 2, distanceRemainingMeters = 10.0))
    }

    @Test
    fun `isArrivalAlreadyTriggered dedups the arrival-observer path against the manual path`() {
        assertFalse(tracker.isArrivalAlreadyTriggered(0))
        tracker.markArrivalTriggered(0)
        assertTrue(tracker.isArrivalAlreadyTriggered(0))
        assertFalse(tracker.isArrivalAlreadyTriggered(1))
    }

    // --- departure ---

    @Test
    fun `checkDeparture returns null when not monitoring`() {
        assertNull(tracker.checkDeparture(baseLat, baseLng, speedMph = 30.0))
    }

    @Test
    fun `checkDeparture requires both distance and speed thresholds`() {
        tracker.startDepartureMonitoring(baseLat, baseLng)

        // Far away but stationary (parked, not departed).
        assertNull(tracker.checkDeparture(baseLat + 0.01, baseLng, speedMph = 0.0))

        // Moving fast but still right at the waypoint (GPS jitter).
        assertNull(tracker.checkDeparture(baseLat, baseLng, speedMph = 30.0))
    }

    @Test
    fun `checkDeparture fires once both distance and speed exceed thresholds`() {
        tracker.startDepartureMonitoring(baseLat, baseLng)

        val result = tracker.checkDeparture(baseLat + 0.01, baseLng, speedMph = 30.0)

        requireNotNull(result)
        assertTrue(result.distanceMeters > WaypointArrivalTracker.DEPARTURE_DISTANCE_THRESHOLD_METERS)
        assertEquals(30.0, result.speedMph, 0.01)
    }

    @Test
    fun `checkDeparture does not fire twice for the same departure`() {
        tracker.startDepartureMonitoring(baseLat, baseLng)
        tracker.checkDeparture(baseLat + 0.01, baseLng, speedMph = 30.0)

        val secondCall = tracker.checkDeparture(baseLat + 0.02, baseLng, speedMph = 30.0)

        assertNull(secondCall)
    }

    // --- reset ---

    @Test
    fun `reset clears leg tracking so a new session starts fresh`() {
        tracker.onLegTransition(currentLeg = 1, totalLegs = 3)
        tracker.markArrivalTriggered(1)

        tracker.reset()

        assertFalse(tracker.isArrivalAlreadyTriggered(1))
        assertEquals(0, tracker.onLegTransition(currentLeg = 1, totalLegs = 3))
    }
}
