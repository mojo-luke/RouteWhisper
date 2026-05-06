package com.routewhisper.route_whisper_app

import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.mockk.*
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class MainActivityTest {

    private lateinit var activity: MainActivity
    private lateinit var mockFlutterEngine: FlutterEngine

    @Before
    fun setup() {
        // MainActivity uses a cached shared FlutterEngine (created by
        // RouteWhisperApplication in production). In test, populate the cache
        // with a mock so Robolectric can construct the activity without
        // failing in FlutterActivityAndFragmentDelegate.setUpFlutterEngine.
        mockFlutterEngine = mockk(relaxed = true)
        every {
            mockFlutterEngine.dartExecutor.binaryMessenger
        } returns mockk(relaxed = true)
        FlutterEngineCache.getInstance().put(
            MainActivity.SHARED_ENGINE_ID,
            mockFlutterEngine,
        )

        activity = Robolectric.buildActivity(MainActivity::class.java)
            .create()
            .get()

        activity.configureFlutterEngine(mockFlutterEngine)
    }

    @After
    fun tearDown() {
        FlutterEngineCache.getInstance().remove(MainActivity.SHARED_ENGINE_ID)
        unmockkAll()
    }

    @Test
    fun `startNavigation with valid coordinates launches MapActivity`() {
        // Arrange
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val arguments = mapOf(
            "originLat" to 37.7749,
            "originLng" to -122.4194,
            "destLat" to 34.0522,
            "destLng" to -118.2437
        )
        val call = MethodCall("calculateRoute", arguments)

        // Act
        activity.handleCalculateRoute(call, result)

        // Assert - verify Intent was created with correct extras
        val shadowActivity = shadowOf(activity)
        val startedIntent = shadowActivity.nextStartedActivity

        assert(startedIntent != null) { "Intent should have been started" }
        assert(startedIntent.component?.className == "com.routewhisper.route_whisper_app.MapActivity") {
            "Should launch MapActivity"
        }
        assert(startedIntent.getDoubleExtra("originLat", 0.0) == 37.7749) {
            "Should pass originLat"
        }
        assert(startedIntent.getDoubleExtra("originLng", 0.0) == -122.4194) {
            "Should pass originLng"
        }
        assert(startedIntent.getDoubleExtra("destLat", 0.0) == 34.0522) {
            "Should pass destLat"
        }
        assert(startedIntent.getDoubleExtra("destLng", 0.0) == -118.2437) {
            "Should pass destLng"
        }

        // Verify success was called
        verify { result.success("Route calculation started") }
    }

    @Test
    fun `startNavigation with missing originLat returns error`() {
        // Arrange
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val arguments = mapOf(
            "originLng" to -122.4194,
            "destLat" to 34.0522,
            "destLng" to -118.2437
        )
        val call = MethodCall("calculateRoute", arguments)

        // Act
        activity.handleCalculateRoute(call, result)

        // Assert
        verify { result.error("INVALID_ARGS", "Missing coordinates", null) }

        // Verify no activity was started
        val shadowActivity = shadowOf(activity)
        val startedIntent = shadowActivity.nextStartedActivity
        assert(startedIntent == null) { "No activity should be started with invalid args" }
    }

    @Test
    fun `startNavigation with missing originLng returns error`() {
        // Arrange
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val arguments = mapOf(
            "originLat" to 37.7749,
            "destLat" to 34.0522,
            "destLng" to -118.2437
        )
        val call = MethodCall("calculateRoute", arguments)

        // Act
        activity.handleCalculateRoute(call, result)

        // Assert
        verify { result.error("INVALID_ARGS", "Missing coordinates", null) }
    }

    @Test
    fun `startNavigation with missing destLat returns error`() {
        // Arrange
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val arguments = mapOf(
            "originLat" to 37.7749,
            "originLng" to -122.4194,
            "destLng" to -118.2437
        )
        val call = MethodCall("calculateRoute", arguments)

        // Act
        activity.handleCalculateRoute(call, result)

        // Assert
        verify { result.error("INVALID_ARGS", "Missing coordinates", null) }
    }

    @Test
    fun `startNavigation with missing destLng returns error`() {
        // Arrange
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val arguments = mapOf(
            "originLat" to 37.7749,
            "originLng" to -122.4194,
            "destLat" to 34.0522
        )
        val call = MethodCall("calculateRoute", arguments)

        // Act
        activity.handleCalculateRoute(call, result)

        // Assert
        verify { result.error("INVALID_ARGS", "Missing coordinates", null) }
    }

    @Test
    fun `startNavigation with all null coordinates returns error`() {
        // Arrange
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val arguments = emptyMap<String, Any>()
        val call = MethodCall("calculateRoute", arguments)

        // Act
        activity.handleCalculateRoute(call, result)

        // Assert
        verify { result.error("INVALID_ARGS", "Missing coordinates", null) }
    }

    @Test
    fun `cancelNavigation returns success`() {
        // Arrange
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall("cancelNavigation", null)

        // Act - Call through the method channel handler
        // We can't easily mock MapboxNavigationApp, but we can verify the method completes
        // and returns success regardless of whether MapboxNavigationApp is setup
        try {
            activity.handleCancelNavigation(result)
        } catch (e: Exception) {
            // If MapboxNavigationApp isn't setup, that's expected in test environment
            // The important thing is that it doesn't crash and returns success
        }

        // Assert - Verify success was called
        verify { result.success("Navigation cancelled") }
    }

    @Test
    fun `startNavigation with waypoints passes waypoint names to Intent`() {
        // Arrange
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val arguments = mapOf(
            "originLat" to 37.7749,
            "originLng" to -122.4194,
            "destLat" to 34.0522,
            "destLng" to -118.2437,
            "waypoints" to listOf(
                listOf(-122.0, 36.5),
                listOf(-121.5, 36.0)
            ),
            "waypointNames" to listOf("Stop 1", "Stop 2")
        )
        val call = MethodCall("calculateRoute", arguments)

        // Act
        activity.handleCalculateRoute(call, result)

        // Assert - verify Intent contains waypoint names
        val shadowActivity = shadowOf(activity)
        val startedIntent = shadowActivity.nextStartedActivity

        assert(startedIntent != null) { "Intent should have been started" }

        val waypointNames = startedIntent.getStringArrayExtra("waypointNames")
        assert(waypointNames != null) { "Should pass waypointNames" }
        assert(waypointNames!!.size == 2) { "Should have 2 waypoint names" }
        assert(waypointNames[0] == "Stop 1") { "First waypoint name should match" }
        assert(waypointNames[1] == "Stop 2") { "Second waypoint name should match" }

        verify { result.success("Route calculation started") }
    }

    @Test
    fun `startNavigation without waypoint names works correctly`() {
        // Arrange
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val arguments = mapOf(
            "originLat" to 37.7749,
            "originLng" to -122.4194,
            "destLat" to 34.0522,
            "destLng" to -118.2437,
            "waypoints" to listOf(
                listOf(-122.0, 36.5)
            )
            // No waypointNames provided
        )
        val call = MethodCall("calculateRoute", arguments)

        // Act
        activity.handleCalculateRoute(call, result)

        // Assert - should still work without names
        val shadowActivity = shadowOf(activity)
        val startedIntent = shadowActivity.nextStartedActivity

        assert(startedIntent != null) { "Intent should have been started" }

        val waypoints = startedIntent.getDoubleArrayExtra("waypoints")
        assert(waypoints != null) { "Should pass waypoints" }
        assert(waypoints!!.size == 2) { "Should have flat array of coordinates" }

        // Waypoint names should be null or not present
        val waypointNames = startedIntent.getStringArrayExtra("waypointNames")
        // It's okay if waypointNames is null when not provided

        verify { result.success("Route calculation started") }
    }

    @Test
    fun `calculateRoute with waypoint names passes them to Intent`() {
        // Arrange
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val arguments = mapOf(
            "originLat" to 37.7749,
            "originLng" to -122.4194,
            "destLat" to 34.0522,
            "destLng" to -118.2437,
            "waypoints" to listOf(
                listOf(-122.0, 36.5),
                listOf(-121.5, 36.0),
                listOf(-121.0, 35.5)
            ),
            "waypointNames" to listOf("Shell Gas Station", "Starbucks", "Scenic Viewpoint")
        )
        val call = MethodCall("calculateRoute", arguments)

        // Act
        activity.handleCalculateRoute(call, result)

        // Assert - verify Intent contains waypoint names
        val shadowActivity = shadowOf(activity)
        val startedIntent = shadowActivity.nextStartedActivity

        assert(startedIntent != null) { "Intent should have been started" }

        val waypointNames = startedIntent.getStringArrayExtra("waypointNames")
        assert(waypointNames != null) { "Should pass waypointNames" }
        assert(waypointNames!!.size == 3) { "Should have 3 waypoint names" }
        assert(waypointNames[0] == "Shell Gas Station") { "First waypoint name should match" }
        assert(waypointNames[1] == "Starbucks") { "Second waypoint name should match" }
        assert(waypointNames[2] == "Scenic Viewpoint") { "Third waypoint name should match" }

        verify { result.success("Route calculation started") }
    }
}
