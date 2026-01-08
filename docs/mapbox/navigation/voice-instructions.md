# Voice Instructions Component

## Overview
The Navigation SDK provides audio guidance through the voice instructions system, which converts banner instructions into spoken directions. This includes automatic speech generation and playback during navigation.

## Core Components

### 1. MapboxSpeechApi
Generates speech from `VoiceInstruction` objects using Mapbox's text-to-speech service.

### 2. MapboxVoiceInstructionsPlayer
Plays audio announcements with proper audio focus handling.

### 3. VoiceInstructionsObserver
Observes navigation progress and delivers voice instruction events.

## Basic Implementation

### Step 1: Request Voice Instructions in Directions API

```kotlin
import com.mapbox.api.directions.v5.DirectionsCriteria
import com.mapbox.api.directions.v5.MapboxDirections

val directions = MapboxDirections.builder()
    .accessToken(YOUR_TOKEN)
    .profile(DirectionsCriteria.PROFILE_DRIVING_TRAFFIC)
    .origin(origin)
    .destination(destination)
    .steps(true)
    .voiceInstructions(true) // Enable voice instructions
    .bannerInstructions(true)
    .language("en") // Instruction language
    .build()
```

### Step 2: Initialize Speech API

```kotlin
import com.mapbox.navigation.ui.voice.api.MapboxSpeechApi
import com.mapbox.navigation.ui.voice.api.MapboxVoiceInstructionsPlayer
import com.mapbox.navigation.ui.voice.model.SpeechAnnouncement
import java.util.Locale

class NavigationActivity : AppCompatActivity() {

    private lateinit var speechApi: MapboxSpeechApi
    private lateinit var voiceInstructionsPlayer: MapboxVoiceInstructionsPlayer

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialize speech API
        speechApi = MapboxSpeechApi(
            context = this,
            accessToken = getString(R.string.mapbox_access_token),
            language = Locale.US.language
        )

        // Initialize voice player
        voiceInstructionsPlayer = MapboxVoiceInstructionsPlayer(
            context = this,
            accessToken = getString(R.string.mapbox_access_token),
            language = Locale.US.language
        )
    }
}
```

### Step 3: Register Voice Instructions Observer

```kotlin
import com.mapbox.navigation.core.trip.session.VoiceInstructionsObserver

val voiceInstructionsObserver = VoiceInstructionsObserver { voiceInstructions ->
    // Generate speech announcement
    speechApi.generate(voiceInstructions) { expected ->
        expected.fold(
            { announcement ->
                // Play the announcement
                voiceInstructionsPlayer.play(announcement)
            },
            { error ->
                // Handle error (e.g., use fallback TTS)
                Log.e("VoiceInstructions", "Error generating speech: $error")
            }
        )
    }
}

mapboxNavigation.registerVoiceInstructionsObserver(voiceInstructionsObserver)
```

### Step 4: Clean Up

```kotlin
override fun onDestroy() {
    super.onDestroy()
    mapboxNavigation.unregisterVoiceInstructionsObserver(voiceInstructionsObserver)
    speechApi.cancel() // Cancel pending requests
    voiceInstructionsPlayer.shutdown() // Release audio resources
}
```

## Language Support

### Setting Language

Specify language in Directions API and Speech API:

```kotlin
val directions = MapboxDirections.builder()
    .language("es") // Spanish
    .voiceInstructions(true)
    .build()

val speechApi = MapboxSpeechApi(
    context = this,
    accessToken = YOUR_TOKEN,
    language = "es"
)
```

### Supported Languages

Common language codes:
- `"en"` - English
- `"es"` - Spanish
- `"fr"` - French
- `"de"` - German
- `"it"` - Italian
- `"pt"` - Portuguese
- `"zh"` - Chinese
- `"ja"` - Japanese
- `"ko"` - Korean

**Note**: Not all languages support voice synthesis. Check Mapbox documentation for complete list.

## Voice Instruction Types

### Distance Announcements

Voice instructions include multiple announcements at different distances:

1. **Early warning** (e.g., "In 1 mile, turn right")
2. **Approach warning** (e.g., "In 500 feet, turn right")
3. **Execution** (e.g., "Turn right now")

### Instruction Content

Typical instruction includes:
- Distance to maneuver
- Action (turn, merge, exit, etc.)
- Direction (left, right, slight right, etc.)
- Street/road name
- Additional context (lane guidance, exit numbers)

**Example**: "In 500 feet, turn right onto Market Street"

## Audio Focus Handling

MapboxVoiceInstructionsPlayer automatically handles audio focus:

- Requests audio focus before playing
- Ducks (lowers) other audio (music, podcasts)
- Releases audio focus after announcement
- Properly handles interruptions

## Custom Voice Options

### Using Device TTS (Fallback)

If Mapbox speech generation fails, use device text-to-speech:

```kotlin
import android.speech.tts.TextToSpeech

class NavigationActivity : AppCompatActivity() {

    private lateinit var textToSpeech: TextToSpeech

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        textToSpeech = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                textToSpeech.language = Locale.US
            }
        }
    }

    private fun playWithDeviceTTS(text: String) {
        textToSpeech.speak(
            text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            "VoiceInstructionID"
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        textToSpeech.shutdown()
    }
}
```

### Hybrid Approach (Recommended)

```kotlin
val voiceInstructionsObserver = VoiceInstructionsObserver { voiceInstructions ->
    speechApi.generate(voiceInstructions) { expected ->
        expected.fold(
            { announcement ->
                // Use Mapbox speech (higher quality)
                voiceInstructionsPlayer.play(announcement)
            },
            { error ->
                // Fallback to device TTS
                playWithDeviceTTS(voiceInstructions.announcement())
            }
        )
    }
}
```

## Muting Voice Instructions

### Toggle Voice On/Off

```kotlin
class NavigationActivity : AppCompatActivity() {

    private var voiceMuted = false

    fun toggleVoice() {
        voiceMuted = !voiceMuted
        updateVoiceIcon()
    }

    private val voiceInstructionsObserver = VoiceInstructionsObserver { voiceInstructions ->
        if (!voiceMuted) {
            speechApi.generate(voiceInstructions) { expected ->
                expected.fold(
                    { announcement ->
                        voiceInstructionsPlayer.play(announcement)
                    },
                    { error ->
                        // Handle error
                    }
                )
            }
        }
    }
}
```

### Volume Control

```kotlin
import android.media.AudioManager

fun adjustNavigationVolume() {
    val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)

    // Increase volume for navigation
    audioManager.setStreamVolume(
        AudioManager.STREAM_MUSIC,
        audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
        0
    )
}
```

## Complete Example

```kotlin
class NavigationActivity : AppCompatActivity() {

    private lateinit var mapboxNavigation: MapboxNavigation
    private lateinit var speechApi: MapboxSpeechApi
    private lateinit var voiceInstructionsPlayer: MapboxVoiceInstructionsPlayer
    private var voiceMuted = false

    private val voiceInstructionsObserver = VoiceInstructionsObserver { voiceInstructions ->
        if (!voiceMuted) {
            generateAndPlayVoiceInstruction(voiceInstructions)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_navigation)

        initializeVoiceInstructions()

        // Mute button
        findViewById<Button>(R.id.muteButton).setOnClickListener {
            toggleVoice()
        }
    }

    private fun initializeVoiceInstructions() {
        speechApi = MapboxSpeechApi(
            context = this,
            accessToken = getString(R.string.mapbox_access_token),
            language = Locale.getDefault().language
        )

        voiceInstructionsPlayer = MapboxVoiceInstructionsPlayer(
            context = this,
            accessToken = getString(R.string.mapbox_access_token),
            language = Locale.getDefault().language
        )

        mapboxNavigation.registerVoiceInstructionsObserver(voiceInstructionsObserver)
    }

    private fun generateAndPlayVoiceInstruction(voiceInstructions: VoiceInstructions) {
        speechApi.generate(voiceInstructions) { expected ->
            expected.fold(
                { announcement ->
                    voiceInstructionsPlayer.play(announcement) { result ->
                        result.fold(
                            {
                                Log.d("Voice", "Announcement played successfully")
                            },
                            { error ->
                                Log.e("Voice", "Error playing announcement: $error")
                            }
                        )
                    }
                },
                { error ->
                    Log.e("Voice", "Error generating speech: $error")
                    // Fallback to device TTS
                    playWithDeviceTTS(voiceInstructions.announcement())
                }
            )
        }
    }

    private fun toggleVoice() {
        voiceMuted = !voiceMuted
        val muteButton = findViewById<Button>(R.id.muteButton)
        muteButton.text = if (voiceMuted) "Unmute" else "Mute"
    }

    private fun playWithDeviceTTS(text: String) {
        // Device TTS fallback implementation
    }

    override fun onDestroy() {
        super.onDestroy()
        mapboxNavigation.unregisterVoiceInstructionsObserver(voiceInstructionsObserver)
        speechApi.cancel()
        voiceInstructionsPlayer.shutdown()
    }
}
```

## Best Practices

1. **Always request voice instructions** in Directions API (`.voiceInstructions(true)`)
2. **Provide fallback TTS** for offline or error scenarios
3. **Handle audio focus properly** - MapboxVoiceInstructionsPlayer does this automatically
4. **Respect user preference** - Allow muting and save preference
5. **Use device locale** by default for better UX
6. **Cancel pending requests** in onDestroy() to prevent memory leaks
7. **Test in car environment** - voice clarity critical while driving

## Common Issues

### Voice instructions not playing
- Ensure `.voiceInstructions(true)` in Directions API request
- Check device volume isn't muted
- Verify audio focus not blocked by another app
- Check token has required permissions

### Wrong language
- Match language code between Directions API and SpeechApi
- Use device locale: `Locale.getDefault().language`
- Verify language is supported by Mapbox TTS

### Choppy or interrupted audio
- Check for audio focus conflicts
- Ensure proper cleanup in onDestroy()
- Don't create multiple player instances

## Related Documentation
- [Maneuver Instructions](maneuver-instructions.md) - Visual turn instructions
- [Directions API](../apis/directions-api.md) - Requesting routes with voice data
- [UI Components Overview](ui-components.md) - All UI components

## External Resources
- Voice Instructions Examples: https://docs.mapbox.com/android/navigation/examples/
- Navigation SDK Guide: https://docs.mapbox.com/android/navigation/guides/
