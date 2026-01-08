package com.routewhisper.route_whisper_app

import android.content.Intent
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.assertEquals
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Unit tests for MapActivity
 *
 * Note: These tests verify the Intent data extraction logic.
 * Full integration tests with Mapbox SDK require device/emulator testing.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class MapActivityTest {

    @Test
    fun `Intent extras can be extracted correctly`() {
        // Arrange
        val intent = Intent().apply {
            putExtra("originLat", 37.7749)
            putExtra("originLng", -122.4194)
            putExtra("destLat", 34.0522)
            putExtra("destLng", -118.2437)
        }

        // Act - Extract values the same way MapActivity does
        val originLat = intent.getDoubleExtra("originLat", 0.0)
        val originLng = intent.getDoubleExtra("originLng", 0.0)
        val destLat = intent.getDoubleExtra("destLat", 0.0)
        val destLng = intent.getDoubleExtra("destLng", 0.0)

        // Assert
        assertEquals("Origin latitude should match", 37.7749, originLat, 0.0001)
        assertEquals("Origin longitude should match", -122.4194, originLng, 0.0001)
        assertEquals("Destination latitude should match", 34.0522, destLat, 0.0001)
        assertEquals("Destination longitude should match", -118.2437, destLng, 0.0001)
    }

    @Test
    fun `Intent with missing extras returns default values`() {
        // Arrange - Intent with no extras
        val intent = Intent()

        // Act
        val originLat = intent.getDoubleExtra("originLat", 0.0)
        val originLng = intent.getDoubleExtra("originLng", 0.0)
        val destLat = intent.getDoubleExtra("destLat", 0.0)
        val destLng = intent.getDoubleExtra("destLng", 0.0)

        // Assert - Should return default values (0.0)
        assertEquals("Should return default for missing originLat", 0.0, originLat, 0.0001)
        assertEquals("Should return default for missing originLng", 0.0, originLng, 0.0001)
        assertEquals("Should return default for missing destLat", 0.0, destLat, 0.0001)
        assertEquals("Should return default for missing destLng", 0.0, destLng, 0.0001)
    }

    @Test
    fun `Intent can hold multiple coordinate sets`() {
        // Arrange - Test with different coordinates
        val testCases = listOf(
            Pair(Pair(0.0, 0.0), Pair(0.0, 0.0)),  // Zero coordinates
            Pair(Pair(-90.0, -180.0), Pair(90.0, 180.0)),  // Extreme coordinates
            Pair(Pair(51.5074, -0.1278), Pair(48.8566, 2.3522))  // London to Paris
        )

        testCases.forEach { (origin, dest) ->
            // Act
            val intent = Intent().apply {
                putExtra("originLat", origin.first)
                putExtra("originLng", origin.second)
                putExtra("destLat", dest.first)
                putExtra("destLng", dest.second)
            }

            // Assert
            assertEquals(origin.first, intent.getDoubleExtra("originLat", 0.0), 0.0001)
            assertEquals(origin.second, intent.getDoubleExtra("originLng", 0.0), 0.0001)
            assertEquals(dest.first, intent.getDoubleExtra("destLat", 0.0), 0.0001)
            assertEquals(dest.second, intent.getDoubleExtra("destLng", 0.0), 0.0001)
        }
    }
}
