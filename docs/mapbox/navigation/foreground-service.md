# Foreground Service for Navigation

## Overview
Android requires a foreground service with a persistent notification to access location in the background. The Navigation SDK handles this automatically when you start a trip session, but you can customize the notification.

## Why Foreground Service?

**Android Requirements**:
- Background location access requires foreground service (Android 8.0+)
- Foreground services must show persistent notification
- Prevents system from killing navigation while app in background

**When It's Used**:
- During active navigation
- When user switches apps or locks screen
- Any time trip session is active

## Automatic Foreground Service

The SDK automatically starts a foreground service when you call `startTripSession()`:

```kotlin
// Foreground service starts automatically
mapboxNavigation.startTripSession()

// Foreground service stops automatically
mapboxNavigation.stopTripSession()
```

**No additional configuration required for basic usage.**

## Required Permissions

Add to `AndroidManifest.xml`:

```xml
<!-- Location permissions -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- Foreground service permission (Android 9+) -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />

<!-- Post notifications (Android 13+) -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- Background location (if needed for background navigation) -->
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
```

## Default Notification

The SDK shows a default notification with:
- App icon
- "Navigation in progress" title
- Basic text
- Tap to return to app

## Custom Notification

### Step 1: Create Notification

```kotlin
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

class NavigationNotificationProvider(private val context: Context) {

    companion object {
        private const val CHANNEL_ID = "navigation_channel"
        private const val NOTIFICATION_ID = 1
    }

    init {
        createNotificationChannel()
    }

    fun createNotification(title: String, text: String): Notification {
        // Intent to return to navigation activity
        val intent = Intent(context, NavigationActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_navigation)
            .setContentIntent(pendingIntent)
            .setOngoing(true) // Can't be dismissed
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Navigation",
                NotificationManager.IMPORTANCE_LOW // Don't make sound/vibrate
            ).apply {
                description = "Navigation in progress"
                setShowBadge(false)
            }

            val notificationManager = context.getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }
}
```

### Step 2: Configure Navigation with Custom Notification

```kotlin
import com.mapbox.navigation.base.options.NavigationOptions

val navigationOptions = NavigationOptions.Builder(context)
    .accessToken(YOUR_TOKEN)
    .notificationOptions(
        NotificationOptions.Builder(context)
            .notificationId(1)
            .build()
    )
    .build()
```

## Dynamic Notification Updates

Update notification with navigation progress:

```kotlin
import androidx.core.app.NotificationManagerCompat

class NavigationActivity : AppCompatActivity() {

    private lateinit var notificationProvider: NavigationNotificationProvider
    private val notificationManager by lazy {
        NotificationManagerCompat.from(this)
    }

    private val routeProgressObserver = RouteProgressObserver { routeProgress ->
        updateNotification(routeProgress)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        notificationProvider = NavigationNotificationProvider(this)
        mapboxNavigation.registerRouteProgressObserver(routeProgressObserver)
    }

    private fun updateNotification(routeProgress: RouteProgress) {
        val distanceRemaining = routeProgress.distanceRemaining
        val durationRemaining = routeProgress.durationRemaining

        val distanceText = formatDistance(distanceRemaining)
        val timeText = formatDuration(durationRemaining)

        val notification = notificationProvider.createNotification(
            title = "Navigation to ${getDestinationName()}",
            text = "$distanceText • $timeText remaining"
        )

        notificationManager.notify(1, notification)
    }

    private fun formatDistance(meters: Double): String {
        val miles = meters / 1609.34
        return if (miles >= 1) {
            String.format("%.1f mi", miles)
        } else {
            String.format("%.0f ft", meters * 3.28084)
        }
    }

    private fun formatDuration(seconds: Double): String {
        val minutes = (seconds / 60).toInt()
        val hours = minutes / 60
        val remainingMinutes = minutes % 60

        return if (hours > 0) {
            "$hours hr $remainingMinutes min"
        } else {
            "$minutes min"
        }
    }
}
```

## Notification Actions

Add actions like "Stop Navigation" or "Mute Voice":

```kotlin
fun createNotificationWithActions(): Notification {
    // Stop navigation action
    val stopIntent = Intent(context, NavigationService::class.java).apply {
        action = "ACTION_STOP_NAVIGATION"
    }
    val stopPendingIntent = PendingIntent.getService(
        context,
        0,
        stopIntent,
        PendingIntent.FLAG_IMMUTABLE
    )

    // Mute voice action
    val muteIntent = Intent(context, NavigationService::class.java).apply {
        action = "ACTION_TOGGLE_MUTE"
    }
    val mutePendingIntent = PendingIntent.getService(
        context,
        1,
        muteIntent,
        PendingIntent.FLAG_IMMUTABLE
    )

    return NotificationCompat.Builder(context, CHANNEL_ID)
        .setContentTitle("Navigation Active")
        .setContentText("5.2 mi • 12 min remaining")
        .setSmallIcon(R.drawable.ic_navigation)
        .setOngoing(true)
        .addAction(R.drawable.ic_stop, "Stop", stopPendingIntent)
        .addAction(R.drawable.ic_volume_off, "Mute", mutePendingIntent)
        .build()
}
```

## Background Location

### Requesting Background Location Permission

```kotlin
private val backgroundLocationPermissionRequest = registerForActivityResult(
    ActivityResultContracts.RequestPermission()
) { isGranted ->
    if (isGranted) {
        // Background location granted
        startBackgroundNavigation()
    } else {
        // Background location denied
        showBackgroundLocationRationale()
    }
}

fun requestBackgroundLocation() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        backgroundLocationPermissionRequest.launch(
            Manifest.permission.ACCESS_BACKGROUND_LOCATION
        )
    }
}
```

### Explanation for Users

```kotlin
fun showBackgroundLocationRationale() {
    AlertDialog.Builder(this)
        .setTitle("Background Location")
        .setMessage("RouteWhisper needs background location access to continue navigation when the app is in the background.")
        .setPositiveButton("Settings") { _, _ ->
            openAppSettings()
        }
        .setNegativeButton("Cancel", null)
        .show()
}

private fun openAppSettings() {
    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
        data = Uri.fromParts("package", packageName, null)
    }
    startActivity(intent)
}
```

## Complete Example

```kotlin
class NavigationActivity : AppCompatActivity() {

    private lateinit var mapboxNavigation: MapboxNavigation
    private lateinit var notificationProvider: NavigationNotificationProvider
    private val notificationManager by lazy {
        NotificationManagerCompat.from(this)
    }

    private val routeProgressObserver = RouteProgressObserver { routeProgress ->
        updateNavigationNotification(routeProgress)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_navigation)

        notificationProvider = NavigationNotificationProvider(this)

        // Register observer
        mapboxNavigation.registerRouteProgressObserver(routeProgressObserver)

        // Start navigation
        startNavigation()
    }

    private fun startNavigation() {
        // Start trip session - foreground service starts automatically
        mapboxNavigation.startTripSession()

        // Show initial notification
        showNavigationNotification("Starting navigation...")
    }

    private fun showNavigationNotification(text: String) {
        val notification = notificationProvider.createNotification(
            title = "RouteWhisper Navigation",
            text = text
        )

        notificationManager.notify(1, notification)
    }

    private fun updateNavigationNotification(routeProgress: RouteProgress) {
        val distanceRemaining = routeProgress.distanceRemaining
        val durationRemaining = routeProgress.durationRemaining

        val progressText = formatProgress(distanceRemaining, durationRemaining)

        showNavigationNotification(progressText)
    }

    private fun formatProgress(distance: Double, duration: Double): String {
        val distanceText = if (distance > 1609) {
            String.format("%.1f mi", distance / 1609.34)
        } else {
            String.format("%.0f ft", distance * 3.28084)
        }

        val minutes = (duration / 60).toInt()
        val timeText = if (minutes >= 60) {
            val hours = minutes / 60
            val mins = minutes % 60
            "$hours hr $mins min"
        } else {
            "$minutes min"
        }

        return "$distanceText • $timeText remaining"
    }

    override fun onDestroy() {
        super.onDestroy()
        mapboxNavigation.unregisterRouteProgressObserver(routeProgressObserver)

        // Stop trip session - foreground service stops automatically
        mapboxNavigation.stopTripSession()
    }
}
```

## Best Practices

1. **Always show notification** - Required for foreground service
2. **Use low priority channel** - Avoid annoying sounds/vibrations
3. **Make notification actionable** - Tap to return to app
4. **Update with progress** - Keep user informed
5. **Explain background location** - Tell users why you need it
6. **Stop service when done** - Call stopTripSession()
7. **Test on Android 13+** - Notification permissions changed

## Common Issues

### Notification not showing
- Check notification channel created (Android 8+)
- Verify POST_NOTIFICATIONS permission granted (Android 13+)
- Ensure trip session started

### App killed in background
- Verify foreground service running
- Check battery optimization settings
- Some manufacturers aggressively kill apps

### Background location not working
- Request ACCESS_BACKGROUND_LOCATION permission
- Show clear explanation to user
- Test on Android 10+ (different behavior)

## Related Documentation
- [Initialization Guide](initialization.md) - MapboxNavigation setup
- [Location Component](location-component.md) - Location tracking
- [Trip Progress](trip-progress.md) - Progress information for notification

## External Resources
- Foreground Services Guide: https://developer.android.com/guide/components/foreground-services
- Navigation SDK Guide: https://docs.mapbox.com/android/navigation/guides/
