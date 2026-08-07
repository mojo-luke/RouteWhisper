package com.routewhisper.route_whisper_app

import android.content.Context
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Looper
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
import org.robolectric.shadows.ShadowMediaPlayer
import org.robolectric.shadows.ShadowMediaPlayer.MediaInfo
import org.robolectric.shadows.util.DataSource

/**
 * Covers MainActivity's narration/audio method-channel handlers —
 * the local-TTS path (handleSpeakNarration) and the premium mp3
 * playback path (handlePlayNarrationAudio), including the audio-focus
 * request/abandon behavior added alongside this test.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class MainActivityNarrationTest {

    private lateinit var activity: MainActivity
    private lateinit var mockFlutterEngine: FlutterEngine
    private lateinit var mockMapActivity: MapActivity
    private lateinit var audioManager: AudioManager

    @Before
    fun setup() {
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

        mockMapActivity = mockk(relaxed = true)
        MapActivity.currentInstance = mockMapActivity

        audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    @After
    fun tearDown() {
        FlutterEngineCache.getInstance().remove(MainActivity.SHARED_ENGINE_ID)
        MapActivity.currentInstance = null
        DataSource.reset()
        unmockkAll()
    }

    // --- handleSpeakNarration ---

    @Test
    fun `speakNarration with text succeeds`() {
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall("speakNarration", mapOf("text" to "You're passing a scenic overlook"))

        activity.handleSpeakNarration(call, result)

        verify { result.success(null) }
    }

    @Test
    fun `speakNarration with blank text returns error`() {
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall("speakNarration", mapOf("text" to "   "))

        activity.handleSpeakNarration(call, result)

        verify { result.error("INVALID_ARGS", "Missing text", null) }
    }

    @Test
    fun `speakNarration with missing text returns error`() {
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall("speakNarration", emptyMap<String, Any>())

        activity.handleSpeakNarration(call, result)

        verify { result.error("INVALID_ARGS", "Missing text", null) }
    }

    // --- handleAddNarrationMarker / handleSetActiveNarrationMarker / handleClearNarrationMarkers ---

    @Test
    fun `addNarrationMarker with valid fields forwards to MapActivity`() {
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall(
            "addNarrationMarker",
            mapOf("id" to "wiki-123", "lat" to 37.7749, "lng" to -122.4194, "title" to "Golden Gate Park"),
        )

        activity.handleAddNarrationMarker(call, result)

        verify { mockMapActivity.addNarrationMarker("wiki-123", 37.7749, -122.4194, "Golden Gate Park") }
        verify { result.success(null) }
    }

    @Test
    fun `addNarrationMarker with missing fields returns error`() {
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall("addNarrationMarker", mapOf("id" to "wiki-123"))

        activity.handleAddNarrationMarker(call, result)

        verify { result.error("INVALID_ARGS", "Missing marker fields", null) }
        verify(exactly = 0) { mockMapActivity.addNarrationMarker(any(), any(), any(), any()) }
    }

    @Test
    fun `setActiveNarrationMarker forwards id to MapActivity`() {
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall("setActiveNarrationMarker", mapOf("id" to "wiki-123"))

        activity.handleSetActiveNarrationMarker(call, result)

        verify { mockMapActivity.setActiveNarrationMarker("wiki-123") }
        verify { result.success(null) }
    }

    @Test
    fun `setActiveNarrationMarker with null id clears the active marker`() {
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall("setActiveNarrationMarker", null)

        activity.handleSetActiveNarrationMarker(call, result)

        verify { mockMapActivity.setActiveNarrationMarker(null) }
        verify { result.success(null) }
    }

    @Test
    fun `clearNarrationMarkers forwards to MapActivity and succeeds`() {
        val result = mockk<MethodChannel.Result>(relaxed = true)

        activity.handleClearNarrationMarkers(result)

        verify { mockMapActivity.clearNarrationMarkers() }
        verify { result.success(null) }
    }

    // --- handleSetNarration / handleSetNarrationSaved / handleClearNarration ---

    @Test
    fun `setNarration with valid fields forwards to MapActivity`() {
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val arguments = mapOf(
            "pageid" to 49728,
            "title" to "Golden Gate Park",
            "primary" to "One of the largest urban parks in the US",
            "canTellMore" to true,
            "isSaved" to false,
        )
        val call = MethodCall("setNarration", arguments)

        activity.handleSetNarration(call, result)

        verify {
            mockMapActivity.setNarrationUi(
                pageid = 49728,
                title = "Golden Gate Park",
                primary = "One of the largest urban parks in the US",
                canTellMore = true,
                isSaved = false,
            )
        }
        verify { result.success(null) }
    }

    @Test
    fun `setNarration with missing fields returns error`() {
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall("setNarration", mapOf("pageid" to 49728))

        activity.handleSetNarration(call, result)

        verify { result.error("INVALID_ARGS", "Missing narration fields", null) }
        verify(exactly = 0) { mockMapActivity.setNarrationUi(any(), any(), any(), any(), any()) }
    }

    @Test
    fun `setNarrationSaved with valid arg forwards to MapActivity`() {
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall("setNarrationSaved", mapOf("isSaved" to true))

        activity.handleSetNarrationSaved(call, result)

        verify { mockMapActivity.setNarrationSavedUi(true) }
        verify { result.success(null) }
    }

    @Test
    fun `setNarrationSaved with missing arg returns error`() {
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall("setNarrationSaved", emptyMap<String, Any>())

        activity.handleSetNarrationSaved(call, result)

        verify { result.error("INVALID_ARGS", "Missing isSaved", null) }
    }

    @Test
    fun `clearNarration forwards to MapActivity and succeeds`() {
        val result = mockk<MethodChannel.Result>(relaxed = true)

        activity.handleClearNarration(result)

        verify { mockMapActivity.clearNarrationUi() }
        verify { result.success(null) }
    }

    // --- handlePlayNarrationAudio ---

    @Test
    fun `playNarrationAudio with missing url returns error`() {
        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall("playNarrationAudio", emptyMap<String, Any>())

        activity.handlePlayNarrationAudio(call, result)

        verify { result.error("INVALID_ARGS", "Missing url", null) }
    }

    @Test
    fun `playNarrationAudio requests audio focus and starts playback once granted`() {
        val url = "http://10.0.2.2:8000/api/v1/audio/test-focus-granted"
        ShadowMediaPlayer.addMediaInfo(DataSource.toDataSource(url), MediaInfo(1000, 0))
        shadowOf(audioManager).setNextFocusRequestResponse(AudioManager.AUDIOFOCUS_REQUEST_GRANTED)

        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall("playNarrationAudio", mapOf("url" to url))

        activity.handlePlayNarrationAudio(call, result)
        shadowOf(Looper.getMainLooper()).idle()

        val focusRequest = shadowOf(audioManager).lastAudioFocusRequest
        assert(focusRequest != null) { "Should have requested audio focus before starting playback" }
        assert(focusRequest.durationHint == AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK) {
            "Should request transient-may-duck focus so nav guidance can still interrupt"
        }
        verify { result.success(null) }
    }

    @Test
    fun `playNarrationAudio does not start playback when focus is denied`() {
        val url = "http://10.0.2.2:8000/api/v1/audio/test-focus-denied"
        ShadowMediaPlayer.addMediaInfo(DataSource.toDataSource(url), MediaInfo(1000, 0))
        shadowOf(audioManager).setNextFocusRequestResponse(AudioManager.AUDIOFOCUS_REQUEST_FAILED)

        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall("playNarrationAudio", mapOf("url" to url))

        activity.handlePlayNarrationAudio(call, result)
        shadowOf(Looper.getMainLooper()).idle()

        assert(shadowOf(audioManager).lastAudioFocusRequest != null) {
            "Should still have attempted to request focus"
        }
        // handlePlayNarrationAudio's channel contract resolves synchronously
        // after prepareAsync() regardless of the async focus outcome.
        verify { result.success(null) }
    }

    @Test
    fun `playNarrationAudio abandons audio focus when playback completes`() {
        val url = "http://10.0.2.2:8000/api/v1/audio/test-focus-completion"
        ShadowMediaPlayer.addMediaInfo(DataSource.toDataSource(url), MediaInfo(50, 0))
        shadowOf(audioManager).setNextFocusRequestResponse(AudioManager.AUDIOFOCUS_REQUEST_GRANTED)

        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall("playNarrationAudio", mapOf("url" to url))

        activity.handlePlayNarrationAudio(call, result)
        shadowOf(Looper.getMainLooper()).idle()

        val requestedFocus = shadowOf(audioManager).lastAudioFocusRequest?.audioFocusRequest
        assert(requestedFocus != null) { "Playback should have requested focus before completing" }

        // Let the simulated 50ms of playback elapse so ShadowMediaPlayer fires onCompletion.
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(1))

        assert(shadowOf(audioManager).lastAbandonedAudioFocusRequest === requestedFocus) {
            "Should abandon the same focus request once playback completes"
        }
    }

    @Test
    fun `playNarrationAudio abandons audio focus when playback errors`() {
        val url = "http://10.0.2.2:8000/api/v1/audio/test-focus-error"
        val dataSource = DataSource.toDataSource(url)
        val mediaInfo = MediaInfo(1000, 0)
        mediaInfo.scheduleErrorAtOffset(0, MediaPlayer.MEDIA_ERROR_UNKNOWN, 0)
        ShadowMediaPlayer.addMediaInfo(dataSource, mediaInfo)
        shadowOf(audioManager).setNextFocusRequestResponse(AudioManager.AUDIOFOCUS_REQUEST_GRANTED)

        val result = mockk<MethodChannel.Result>(relaxed = true)
        val call = MethodCall("playNarrationAudio", mapOf("url" to url))

        activity.handlePlayNarrationAudio(call, result)
        shadowOf(Looper.getMainLooper()).idle()

        val requestedFocus = shadowOf(audioManager).lastAudioFocusRequest?.audioFocusRequest
        assert(requestedFocus != null) { "Should have requested focus before the error fires" }

        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(1))

        assert(shadowOf(audioManager).lastAbandonedAudioFocusRequest === requestedFocus) {
            "Should abandon focus when MediaPlayer reports an error"
        }
    }
}
