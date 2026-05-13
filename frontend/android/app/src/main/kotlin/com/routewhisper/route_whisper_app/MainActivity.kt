package com.routewhisper.route_whisper_app

import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.speech.tts.TextToSpeech
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val methodChannelName = "routewhisper.com/navigation"

    // Narration TTS engine. Lives at MainActivity scope (which survives
    // when the user backs out of MapActivity), so whispers keep playing
    // whether or not the live map is foregrounded. The Mapbox voice
    // player is still responsible for turn-by-turn voice — that stays
    // in MapActivity where it's tied to the active route.
    private var narrationTts: TextToSpeech? = null
    private var narrationTtsReady = false
    // Queued speaks that arrive before the engine finishes async init.
    private val pendingNarrations = mutableListOf<String>()

    // MediaPlayer for premium-voice narration (OpenAI-synthesized mp3
    // streamed from our backend). One instance reused across narrations
    // — release on destroy. Separate audio path from the local-TTS
    // fallback above.
    private var narrationPlayer: MediaPlayer? = null

    // Where the backend lives, used to resolve relative audio URLs.
    // 10.0.2.2 is the emulator's loopback to the Mac. Real devices on
    // the same LAN need a different host — we'll lift this constant
    // out the moment iOS + physical-device testing matters.
    private val backendBase = "http://10.0.2.2:8000"

    companion object {
        const val SHARED_ENGINE_ID = "routewhisper_shared_engine"

        // Static reference to method channel for use by other activities
        internal var methodChannelInstance: MethodChannel? = null

        fun sendRoutePolyline(polyline: String) {
            methodChannelInstance?.invokeMethod("setRoutePolyline", mapOf("polyline" to polyline))
            Log.d("MainActivity", "Sent route polyline to Flutter (${polyline.length} chars)")
        }

        fun sendWaypointArrived(legIndex: Int, latitude: Double, longitude: Double) {
            if (methodChannelInstance == null) {
                Log.e("MainActivity", "❌ methodChannelInstance is NULL! Cannot send waypoint arrival")
                return
            }

            Log.d("MainActivity", "Invoking waypointArrived method channel for leg $legIndex")
            methodChannelInstance?.invokeMethod("waypointArrived", mapOf(
                "legIndex" to legIndex,
                "latitude" to latitude,
                "longitude" to longitude,
                "timestamp" to System.currentTimeMillis()
            ))
            Log.d("MainActivity", "✅ Sent waypoint arrival to Flutter: leg $legIndex")
        }

        fun sendAutoDepartureDetected(distance: Double, speed: Double) {
            methodChannelInstance?.invokeMethod("autoDepartureDetected", mapOf(
                "distance" to distance,
                "speed" to speed,
                "timestamp" to System.currentTimeMillis()
            ))
            Log.d("MainActivity", "Sent auto-departure to Flutter: ${distance}m, ${speed}mph")
        }

        fun sendDestinationArrived() {
            methodChannelInstance?.invokeMethod("destinationArrived", mapOf(
                "timestamp" to System.currentTimeMillis()
            ))
            Log.d("MainActivity", "Sent destination arrival to Flutter")
        }

        /**
         * Forward each GPS fix to Flutter so the NarrationService can decide
         * whether to whisper a fact about a nearby place. Fires at the cadence
         * Mapbox's LocationObserver emits (roughly 1 Hz during driving).
         *
         * `distanceAlongRouteMeters` is how far along the active route the
         * user has traveled — used for lookahead narration timing so a
         * whisper fires ~30s of upcoming travel before a fact's
         * projected route position.
         */
        fun sendLocationUpdate(
            latitude: Double,
            longitude: Double,
            speedMph: Double,
            distanceAlongRouteMeters: Double,
        ) {
            methodChannelInstance?.invokeMethod("locationUpdate", mapOf(
                "latitude" to latitude,
                "longitude" to longitude,
                "speedMph" to speedMph,
                "distanceAlongRouteMeters" to distanceAlongRouteMeters,
            ))
        }
    }

    // Use the shared FlutterEngine created by RouteWhisperApplication
    override fun getCachedEngineId(): String {
        return SHARED_ENGINE_ID
    }

    // The shared engine's lifecycle is driven from RouteWhisperApplication via
    // ProcessLifecycleOwner. If this activity also dispatched its own lifecycle to the
    // engine, its onStop would fire AFTER MapActivity.onResume during a transition and
    // pause the engine while MapActivity is foreground — freezing overlay setState calls.
    override fun shouldDispatchAppLifecycleState(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        Log.d("MainActivity", "Configuring shared Flutter engine: $SHARED_ENGINE_ID")

        // Spin up the narration TTS engine. We pass the explicit Google
        // TTS package as the engine to avoid relying on `tts_default_synth`
        // being set — some emulators ship with the engine installed but
        // not selected as default, leaving the no-arg constructor with
        // nothing to initialize. Falls back to the system default if
        // Google TTS isn't installed (rare; it's bundled on most builds).
        val initListener = TextToSpeech.OnInitListener { status ->
            if (status == TextToSpeech.SUCCESS) {
                // setLanguage returns:
                //   >=0 (LANG_AVAILABLE / _COUNTRY_AVAILABLE / _VAR_AVAILABLE)
                //   -1 LANG_MISSING_DATA   ← engine installed, voice not
                //   -2 LANG_NOT_SUPPORTED  ← engine doesn't speak this lang
                // If we ignore this we silently can't speak, which is exactly
                // the failure mode we just hit in the emulator.
                val langStatus = narrationTts?.setLanguage(Locale.US)
                Log.d("MainActivity", "🗣️ Narration TTS engine ready, setLanguage=$langStatus")
                if (langStatus == TextToSpeech.LANG_MISSING_DATA ||
                    langStatus == TextToSpeech.LANG_NOT_SUPPORTED) {
                    Log.w("MainActivity", "🗣️ Voice data missing for en-US — install via TTS settings")
                }
                narrationTtsReady = true
                pendingNarrations.forEach { speakNarration(it) }
                pendingNarrations.clear()
            } else {
                Log.e("MainActivity", "Narration TTS init failed: status=$status")
            }
        }
        narrationTts = try {
            TextToSpeech(applicationContext, initListener, "com.google.android.tts")
        } catch (e: Throwable) {
            Log.w("MainActivity", "Google TTS unavailable, falling back to default: $e")
            TextToSpeech(applicationContext, initListener)
        }

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
        methodChannelInstance = channel  // Store reference for MapActivity

        channel.setMethodCallHandler { call, result ->
            Log.d("MainActivity", "Received method call: ${call.method}")

            when (call.method) {
                "calculateRoute" -> handleCalculateRoute(call, result)
                "updateNavigationRoute" -> handleUpdateNavigationRoute(call, result)
                "openMapView" -> handleOpenMapView(call, result)
                "cancelNavigation" -> handleCancelNavigation(result)
                "showPoisOnMap" -> handleShowPoisOnMap(call, result)
                "clearPoisFromMap" -> handleClearPoisFromMap(result)
                "hideOverlay" -> handleHideOverlay(result)
                "setBudgetStatus" -> handleSetBudgetStatus(call, result)
                "clearBudgetStatus" -> handleClearBudgetStatus(result)
                "setRecommendation" -> handleSetRecommendation(call, result)
                "clearRecommendation" -> handleClearRecommendation(result)
                "speakNarration" -> handleSpeakNarration(call, result)
                "playNarrationAudio" -> handlePlayNarrationAudio(call, result)
                "setTurnByTurnVoiceEnabled" -> handleSetTurnByTurnVoiceEnabled(call, result)
                "addNarrationMarker" -> handleAddNarrationMarker(call, result)
                "setActiveNarrationMarker" -> handleSetActiveNarrationMarker(call, result)
                "clearNarrationMarkers" -> handleClearNarrationMarkers(result)
                "setNarration" -> handleSetNarration(call, result)
                "setNarrationSaved" -> handleSetNarrationSaved(call, result)
                "clearNarration" -> handleClearNarration(result)
                else -> result.notImplemented()
            }
        }
    }

    internal fun handleCalculateRoute(call: MethodCall, result: MethodChannel.Result) {
        val originLat = call.argument<Double>("originLat")
        val originLng = call.argument<Double>("originLng")
        val destLat = call.argument<Double>("destLat")
        val destLng = call.argument<Double>("destLng")
        val waypoints = call.argument<List<List<Double>>>("waypoints") // [[lng, lat], [lng, lat], ...]
        val waypointNames = call.argument<List<String>>("waypointNames") // ["Name 1", "Name 2", ...]

        if (originLat == null || originLng == null || destLat == null || destLng == null) {
            result.error("INVALID_ARGS", "Missing coordinates", null)
            return
        }

        if (waypoints != null && waypoints.isNotEmpty()) {
            Log.d("MainActivity", "Calculate route with ${waypoints.size} waypoints: ($originLat, $originLng) -> ($destLat, $destLng)")
            if (waypointNames != null && waypointNames.isNotEmpty()) {
                Log.d("MainActivity", "Waypoint names: $waypointNames")
            }
        } else {
            Log.d("MainActivity", "Calculate route: ($originLat, $originLng) -> ($destLat, $destLng)")
        }

        // Launch MapActivity which will handle route calculation with waypoints
        val intent = Intent(this, MapActivity::class.java).apply {
            putExtra("originLat", originLat)
            putExtra("originLng", originLng)
            putExtra("destLat", destLat)
            putExtra("destLng", destLng)

            // Pass waypoints as flat array: [lng1, lat1, lng2, lat2, ...]
            if (waypoints != null && waypoints.isNotEmpty()) {
                val flatWaypoints = waypoints.flatten().toDoubleArray()
                putExtra("waypoints", flatWaypoints)
                Log.d("MainActivity", "Passing ${waypoints.size} waypoints for route calculation")

                // Pass waypoint names as String array
                if (waypointNames != null && waypointNames.isNotEmpty()) {
                    putExtra("waypointNames", waypointNames.toTypedArray())
                    Log.d("MainActivity", "Passing ${waypointNames.size} waypoint names for route calculation")
                }
            }
        }
        startActivity(intent)

        result.success("Route calculation started")
    }

    /**
     * Update navigation route in existing MapActivity (in-place update)
     *
     * This method updates the route without launching a new activity, which is critical
     * for the "Never Leave Navigation" UX principle. Called when user adds POI during
     * active navigation.
     *
     * Unlike handleCalculateRoute which launches a NEW MapActivity, this method sends
     * the update to the EXISTING MapActivity instance via updateNavigationRoute().
     */
    internal fun handleUpdateNavigationRoute(call: MethodCall, result: MethodChannel.Result) {
        val originLat = call.argument<Double>("originLat")
        val originLng = call.argument<Double>("originLng")
        val destLat = call.argument<Double>("destLat")
        val destLng = call.argument<Double>("destLng")
        val waypoints = call.argument<List<List<Double>>>("waypoints") // [[lng, lat], [lng, lat], ...]
        val waypointNames = call.argument<List<String>>("waypointNames") // ["Name 1", "Name 2", ...]

        if (originLat == null || originLng == null || destLat == null || destLng == null) {
            result.error("INVALID_ARGS", "Missing coordinates", null)
            return
        }

        Log.d("MainActivity", "🔄 Update navigation route in-place with ${waypoints?.size ?: 0} waypoints")

        // Check if MapActivity is currently active
        val mapActivity = MapActivity.currentInstance
        if (mapActivity == null) {
            Log.e("MainActivity", "❌ No active MapActivity instance - cannot update route in-place")
            result.error("NO_ACTIVITY", "MapActivity not active", null)
            return
        }

        // Convert waypoints to Points
        val waypointPoints = if (waypoints != null && waypoints.isNotEmpty()) {
            waypoints.mapNotNull { coords ->
                if (coords.size >= 2) {
                    com.mapbox.geojson.Point.fromLngLat(coords[0], coords[1])
                } else {
                    null
                }
            }
        } else {
            emptyList()
        }

        Log.d("MainActivity", "Updating route with ${waypointPoints.size} waypoint points")

        // Update route in existing MapActivity (in-place)
        mapActivity.updateNavigationRoute(
            originLat = originLat,
            originLng = originLng,
            destLat = destLat,
            destLng = destLng,
            waypoints = waypointPoints,
            waypointNames = waypointNames
        )

        result.success("Route updated in-place")
    }

    private fun handleOpenMapView(call: MethodCall, result: MethodChannel.Result) {
        Log.d("MainActivity", "Open map view")

        // Launch MapActivity without coordinates - it will show current map state
        // (including any active routes, or just the map if no routes are set)
        val intent = Intent(this, MapActivity::class.java).apply {
            // Don't pass coordinates - MapActivity will just display current state
            putExtra("viewOnly", true)
        }
        startActivity(intent)

        result.success("Map view opened")
    }

    private fun handleShowPoisOnMap(call: MethodCall, result: MethodChannel.Result) {
        val poisRaw = call.argument<List<Map<String, Any>>>("pois")
        val bounds = call.argument<List<Double>>("bounds")
        if (poisRaw == null || bounds == null || bounds.size != 4) {
            result.error("INVALID_ARGS", "Missing pois or bounds", null)
            return
        }

        val map = MapActivity.currentInstance
        if (map == null) {
            Log.e("MainActivity", "showPoisOnMap: no active MapActivity")
            result.error("NO_ACTIVITY", "MapActivity not active", null)
            return
        }

        map.showPoisOnMap(poisRaw, bounds)
        result.success(null)
    }

    private fun handleClearPoisFromMap(result: MethodChannel.Result) {
        MapActivity.currentInstance?.clearPoisFromMap()
        result.success(null)
    }

    private fun handleHideOverlay(result: MethodChannel.Result) {
        MapActivity.currentInstance?.hideFlutterOverlay()
        result.success(null)
    }

    private fun handleSetBudgetStatus(call: MethodCall, result: MethodChannel.Result) {
        val used = call.argument<Int>("usedMinutes")
        val total = call.argument<Int>("totalMinutes")
        if (used == null || total == null) {
            result.error("INVALID_ARGS", "Missing usedMinutes or totalMinutes", null)
            return
        }
        MapActivity.currentInstance?.setBudgetStatusUi(used, total)
        result.success(null)
    }

    private fun handleClearBudgetStatus(result: MethodChannel.Result) {
        MapActivity.currentInstance?.clearBudgetStatusUi()
        result.success(null)
    }

    private fun handleSetRecommendation(call: MethodCall, result: MethodChannel.Result) {
        val poiId = call.argument<String>("poiId")
        val name = call.argument<String>("name")
        val category = call.argument<String>("category")
        val reason = call.argument<String>("reason")
        if (poiId == null || name == null || category == null || reason == null) {
            result.error("INVALID_ARGS", "Missing recommendation fields", null)
            return
        }
        MapActivity.currentInstance?.setRecommendationUi(poiId, name, category, reason)
        result.success(null)
    }

    private fun handleClearRecommendation(result: MethodChannel.Result) {
        MapActivity.currentInstance?.clearRecommendationUi()
        result.success(null)
    }

    /**
     * Speak arbitrary narration text via MainActivity's TextToSpeech.
     *
     * Routes narration through Android's built-in TTS rather than the
     * Mapbox voice player. Reasons:
     *
     *   1. The Mapbox player is bound to MapActivity's lifecycle and
     *      tears down when the user backs out — narration must keep
     *      working from the home dashboard too.
     *   2. The Mapbox player expects an audio File on its announcements;
     *      passing a bare text-only SpeechAnnouncement made it accept
     *      the call but produce no sound.
     *
     * Turn-by-turn voice still flows through the Mapbox player inside
     * MapActivity, untouched. Audio focus may briefly collide if a
     * turn instruction lands during a whisper; Android's TTS engine
     * handles its own focus politely so this should duck rather than
     * stomp.
     */
    private fun handleSpeakNarration(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")
        if (text.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Missing text", null)
            return
        }
        speakNarration(text)
        result.success(null)
    }

    /**
     * Drop / promote / clear narration markers on the native map. We
     * silently no-op when MapActivity isn't around (markers only have
     * meaning while the map is up). Failures don't surface as Flutter
     * errors — narration markers are a UX nicety, not load-bearing.
     */
    private fun handleAddNarrationMarker(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        val lat = call.argument<Double>("lat")
        val lng = call.argument<Double>("lng")
        val title = call.argument<String>("title")
        if (id == null || lat == null || lng == null || title == null) {
            result.error("INVALID_ARGS", "Missing marker fields", null)
            return
        }
        MapActivity.currentInstance?.addNarrationMarker(id, lat, lng, title)
        result.success(null)
    }

    private fun handleSetActiveNarrationMarker(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id") // may be null
        MapActivity.currentInstance?.setActiveNarrationMarker(id)
        result.success(null)
    }

    private fun handleClearNarrationMarkers(result: MethodChannel.Result) {
        MapActivity.currentInstance?.clearNarrationMarkers()
        result.success(null)
    }

    /**
     * Show or replace the in-nav narration banner. Mirrors the
     * dashboard NarrationCard so the user can react during active
     * driving without leaving MapActivity. Silent no-op when
     * MapActivity isn't currently in the foreground — the audio
     * still plays, just no visible card.
     */
    private fun handleSetNarration(call: MethodCall, result: MethodChannel.Result) {
        val pageid = call.argument<Int>("pageid")
        val title = call.argument<String>("title")
        val primary = call.argument<String>("primary")
        val canTellMore = call.argument<Boolean>("canTellMore")
        val isSaved = call.argument<Boolean>("isSaved")
        if (pageid == null || title == null || primary == null ||
            canTellMore == null || isSaved == null) {
            result.error("INVALID_ARGS", "Missing narration fields", null)
            return
        }
        MapActivity.currentInstance?.setNarrationUi(
            pageid = pageid,
            title = title,
            primary = primary,
            canTellMore = canTellMore,
            isSaved = isSaved,
        )
        result.success(null)
    }

    private fun handleSetNarrationSaved(call: MethodCall, result: MethodChannel.Result) {
        val isSaved = call.argument<Boolean>("isSaved")
        if (isSaved == null) {
            result.error("INVALID_ARGS", "Missing isSaved", null)
            return
        }
        MapActivity.currentInstance?.setNarrationSavedUi(isSaved)
        result.success(null)
    }

    private fun handleClearNarration(result: MethodChannel.Result) {
        MapActivity.currentInstance?.clearNarrationUi()
        result.success(null)
    }

    /**
     * Push the user's turn-by-turn voice preference to MapActivity.
     * Stored on a companion object so MapActivity sees the latest
     * value whether or not it's currently in the foreground (the
     * preference might change between trips).
     */
    private fun handleSetTurnByTurnVoiceEnabled(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled")
        if (enabled == null) {
            result.error("INVALID_ARGS", "Missing enabled", null)
            return
        }
        MapActivity.turnByTurnVoiceEnabled = enabled
        Log.d("MainActivity", "Turn-by-turn voice ${if (enabled) "enabled" else "disabled"}")
        result.success(null)
    }

    /**
     * Play a pre-synthesized mp3 (OpenAI-voice narration) from a
     * server-relative URL like `/api/v1/audio/wiki-49728-primary`.
     * Resolves against `backendBase` and streams via MediaPlayer.
     *
     * One player instance reused — we reset() between plays rather
     * than constructing a new one. That avoids leaks if the user
     * mashes Replay or rapid follow-ups land back to back. Errors
     * are logged and swallowed: a failed mp3 play shouldn't crash
     * the bridge call. (Bridge fallback to local TTS isn't auto —
     * the device commits to one path per line via NarrationService.)
     */
    private fun handlePlayNarrationAudio(call: MethodCall, result: MethodChannel.Result) {
        val rawUrl = call.argument<String>("url")
        if (rawUrl.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Missing url", null)
            return
        }
        val fullUrl = if (rawUrl.startsWith("http")) rawUrl else "$backendBase$rawUrl"
        try {
            val player = narrationPlayer ?: MediaPlayer().also { narrationPlayer = it }
            player.reset()
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            player.setDataSource(fullUrl)
            player.setOnPreparedListener {
                Log.d("MainActivity", "🗣️ Narration mp3 prepared: $fullUrl")
                it.start()
            }
            player.setOnErrorListener { _, what, extra ->
                Log.e("MainActivity", "🗣️ MediaPlayer error what=$what extra=$extra url=$fullUrl")
                true // we've handled it; player will reset on next call
            }
            player.prepareAsync()
            Log.d("MainActivity", "🗣️ Narration mp3 prepareAsync: $fullUrl")
            result.success(null)
        } catch (e: Throwable) {
            Log.e("MainActivity", "🗣️ Failed to play narration mp3: ${e.message}")
            result.error("PLAYBACK_FAILED", e.message, null)
        }
    }

    /**
     * Speak [text] through the narration TTS. Queues if the engine
     * hasn't finished its async init yet. QUEUE_FLUSH means a fresh
     * whisper interrupts any in-flight one — at our 30s spacing rule
     * this is almost never the case, but it keeps the experience
     * consistent if the user mashes the Replay button.
     */
    private fun speakNarration(text: String) {
        val tts = narrationTts
        if (tts == null || !narrationTtsReady) {
            Log.d("MainActivity", "🗣️ Narration TTS not ready, queueing")
            pendingNarrations.add(text)
            return
        }
        val result = tts.speak(
            text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            "narration_${System.currentTimeMillis()}",
        )
        // speak() returns SUCCESS (0) or ERROR (-1). ERROR is the
        // silent-failure mode we need to surface — usually means the
        // utterance was rejected because no voice data is installed.
        if (result == TextToSpeech.ERROR) {
            Log.e("MainActivity", "🗣️ TTS speak() returned ERROR — voice data probably missing")
        } else {
            Log.d("MainActivity", "🗣️ Narration spoken: \"${text.take(80)}...\"")
        }
    }

    override fun onDestroy() {
        Log.d("MainActivity", "🔻 onDestroy — releasing narration TTS + MediaPlayer")
        narrationTts?.stop()
        narrationTts?.shutdown()
        narrationTts = null
        narrationTtsReady = false
        narrationPlayer?.release()
        narrationPlayer = null
        super.onDestroy()
    }

    override fun onPause() {
        Log.d("MainActivity", "🟡 onPause (FlutterActivity will dispatch appIsInactive)")
        super.onPause()
    }

    override fun onStop() {
        Log.d("MainActivity", "🔴 onStop (FlutterActivity will dispatch appIsPaused)")
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        Log.d("MainActivity", "🟢 onResume (FlutterActivity dispatched appIsResumed)")
    }

    @OptIn(com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI::class)
    internal fun handleCancelNavigation(result: MethodChannel.Result) {
        Log.d("MainActivity", "Cancel navigation - stopping trip session and clearing routes")

        // Stop the active navigation session completely
        try {
            if (MapboxNavigationApp.isSetup()) {
                val mapboxNavigation = MapboxNavigationApp.current()

                // Stop the active guidance session
                mapboxNavigation?.stopTripSession()
                Log.d("MainActivity", "Trip session stopped")

                // Clear routes
                mapboxNavigation?.setNavigationRoutes(emptyList())
                Log.d("MainActivity", "Routes cleared successfully")

                // Stop replay simulation if active
                mapboxNavigation?.mapboxReplayer?.stop()
                mapboxNavigation?.mapboxReplayer?.finish()
                Log.d("MainActivity", "Replay simulation stopped")
            } else {
                Log.d("MainActivity", "MapboxNavigationApp not setup yet")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error cancelling navigation: ${e.message}")
        }

        result.success("Navigation cancelled")
    }
}
