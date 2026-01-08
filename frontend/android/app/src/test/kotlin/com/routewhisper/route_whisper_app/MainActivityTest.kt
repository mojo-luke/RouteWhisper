package com.routewhisper.route_whisper_app

import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
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
    private lateinit var methodChannelHandler: MethodChannel.MethodCallHandler

    @Before
    fun setup() {
        // Create activity
        activity = Robolectric.buildActivity(MainActivity::class.java)
            .create()
            .get()

        // Mock FlutterEngine
        mockFlutterEngine = mockk(relaxed = true)

        // Capture the method call handler
        val methodChannelSlot = slot<MethodChannel.MethodCallHandler>()
        every {
            mockFlutterEngine.dartExecutor.binaryMessenger
        } returns mockk(relaxed = true)

        // Configure the engine which will set up the method channel
        activity.configureFlutterEngine(mockFlutterEngine)
    }

    @After
    fun tearDown() {
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
        val call = MethodCall("startNavigation", arguments)

        // Act
        activity.handleStartNavigation(call, result)

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
        verify { result.success("Navigation started") }
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
        val call = MethodCall("startNavigation", arguments)

        // Act
        activity.handleStartNavigation(call, result)

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
        val call = MethodCall("startNavigation", arguments)

        // Act
        activity.handleStartNavigation(call, result)

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
        val call = MethodCall("startNavigation", arguments)

        // Act
        activity.handleStartNavigation(call, result)

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
        val call = MethodCall("startNavigation", arguments)

        // Act
        activity.handleStartNavigation(call, result)

        // Assert
        verify { result.error("INVALID_ARGS", "Missing coordinates", null) }
    }

    @Test
    fun `startNavigation with all null coordinates returns error`() {
        // Arrange
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val arguments = emptyMap<String, Any>()
        val call = MethodCall("startNavigation", arguments)

        // Act
        activity.handleStartNavigation(call, result)

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
}
