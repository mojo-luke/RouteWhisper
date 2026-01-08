# Mapbox Troubleshooting Guide

## Common Issues and Solutions

### Build and Dependency Issues

#### 401 Unauthorized - Maven Downloads

**Symptoms**:
```
> Could not resolve com.mapbox.navigationcore:android:3.x.x
  > Could not get resource 'https://api.mapbox.com/downloads/v2/releases/maven/...'
    > Received status code 401 from server: Unauthorized
```

**Causes**:
1. Missing or incorrect `MAPBOX_DOWNLOADS_TOKEN` in `gradle.properties`
2. Token lacks `downloads:read` scope
3. Using public token instead of secret token
4. Token expired or revoked

**Solutions**:

1. **Verify token exists** in `~/.gradle/gradle.properties`:
```properties
MAPBOX_DOWNLOADS_TOKEN=sk.eyJ...
```

2. **Check token type**: Must start with `sk.` (secret token), NOT `pk.` (public token)

3. **Verify token scope**:
   - Go to https://account.mapbox.com/access-tokens
   - Check token has `downloads:read` permission
   - Create new token if necessary

4. **Test token manually**:
```bash
curl -u mapbox:$MAPBOX_DOWNLOADS_TOKEN \
  https://api.mapbox.com/downloads/v2/releases/maven/com/mapbox/navigationcore/android/3.10.0/
```
Should return HTTP 200, not 401.

5. **Clean Gradle cache**:
```bash
./gradlew clean
rm -rf ~/.gradle/caches/
./gradlew build
```

#### Duplicate Class Errors

**Symptoms**:
```
Duplicate class com.mapbox.android.core.permissions.PermissionsListener found in modules:
  common-24.14.0-alpha.2.aar (com.mapbox.common:common:24.14.0-alpha.2)
  common-ndk27-24.17.0.aar (com.mapbox.common:common-ndk27:24.17.0)
```

**Cause**: Mixing ndk27 and non-ndk27 variants of Mapbox libraries, typically when using `mapbox_maps_flutter` alongside native Navigation SDK.

**Solution 1: Remove Flutter Maps Plugin (Recommended for Navigation Apps)**
```yaml
# pubspec.yaml
dependencies:
  # mapbox_maps_flutter: ^2.17.0  # Commented out - using native SDK
```

**Solution 2: Force Resolution (If You Must Use Both)**
```gradle
// android/build.gradle
configurations.all {
    resolutionStrategy {
        force 'com.mapbox.common:common:24.17.0'
        // Exclude non-ndk27 variants
    }
}
```

**Why Flutter Maps Conflicts**:
- Flutter Maps plugin includes Mapbox common libraries (non-ndk27)
- Native Navigation SDK requires ndk27 variants
- Can't use both together in same app

#### CMake Errors During Build

**Symptoms**:
```
CMake Error: SOURCE_DATE_EPOCH out of range
```

**Cause**: Environment variable `SOURCE_DATE_EPOCH` causing CMake failures.

**Solution**:
```bash
unset SOURCE_DATE_EPOCH
flutter clean
flutter build apk
```

#### NDK Version Mismatch

**Symptoms**:
```
NDK at /path/to/ndk/23.x.x did not have a ndk-build executable
```

**Solution**: Explicitly set NDK version in `android/app/build.gradle`:
```gradle
android {
    ndkVersion "27.0.12077973"  // Or "23.1.7779620"
}
```

### Runtime Navigation Issues

#### MapboxNavigation is Null

**Symptoms**:
```kotlin
MapboxNavigationApp.current() // returns null
```

**Causes**:
1. `MapboxNavigationApp.setup()` not called
2. Lifecycle not attached
3. Called before lifecycle reaches CREATED state

**Solutions**:

1. **Ensure setup in Application.onCreate()**:
```kotlin
class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        if (!MapboxNavigationApp.isSetup()) {
            MapboxNavigationApp.setup {
                NavigationOptions.Builder(this)
                    .accessToken(getString(R.string.mapbox_access_token))
                    .build()
            }
        }
    }
}
```

2. **Attach lifecycle**:
```kotlin
override fun onResume() {
    super.onResume()
    MapboxNavigationApp.attach(this)
}
```

3. **Wait for attachment**:
```kotlin
val observer = object : MapboxNavigationObserver {
    override fun onAttached(mapboxNavigation: MapboxNavigation) {
        // Safe to use mapboxNavigation here
    }
}
MapboxNavigationApp.registerObserver(observer)
```

#### Location Not Updating

**Symptoms**:
- No location updates received
- Navigation not progressing

**Causes**:
1. Location permissions not granted
2. Trip session not started
3. GPS disabled on device
4. App in background without foreground service

**Solutions**:

1. **Check permissions**:
```kotlin
if (ContextCompat.checkSelfPermission(
        this,
        Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED
) {
    startTripSession()
} else {
    // Request permissions
}
```

2. **Start trip session**:
```kotlin
MapboxNavigationApp.current()?.startTripSession()
```

3. **Enable GPS**: Guide user to device settings

4. **Foreground service**: Ensure proper notification for background location

#### Route Not Displaying

**Symptoms**:
- Route line not visible on map
- Map loads but no route shown

**Causes**:
1. Route not set to MapboxNavigation
2. Route line layer not added to map
3. Route line renderer not initialized

**Solutions**:

1. **Set route after receiving from Directions API**:
```kotlin
directions.enqueueCall(object : Callback<DirectionsResponse> {
    override fun onResponse(
        call: Call<DirectionsResponse>,
        response: Response<DirectionsResponse>
    ) {
        val routes = response.body()?.routes()
        val navigationRoutes = routes?.map { it.toNavigationRoute() }
        MapboxNavigationApp.current()?.setNavigationRoutes(navigationRoutes)
    }
})
```

2. **Initialize route line component** (if using UI components):
```kotlin
val routeLineView = MapboxRouteLineView(
    MapboxRouteLineOptions.Builder(context).build()
)
```

#### Voice Instructions Not Playing

**Symptoms**:
- Navigation working but no audio guidance
- Silent navigation

**Causes**:
1. Voice instructions not requested in Directions API
2. MapboxSpeechApi not initialized
3. Audio focus issues
4. Device muted

**Solutions**:

1. **Request voice instructions in Directions API**:
```kotlin
val directions = MapboxDirections.builder()
    .voiceInstructions(true)
    .build()
```

2. **Initialize speech API**:
```kotlin
val speechApi = MapboxSpeechApi(
    context,
    YOUR_ACCESS_TOKEN,
    Locale.US.language
)
```

3. **Play instructions**:
```kotlin
mapboxNavigation.registerVoiceInstructionsObserver { voiceInstructions ->
    speechApi.generate(voiceInstructions) { announcement ->
        // Play announcement
    }
}
```

### API and Network Issues

#### Directions API Errors

**Error: 401 Unauthorized**
- Check access token has `styles:read` scope (minimum)
- Verify token not expired
- Ensure token copied correctly (no spaces)

**Error: 422 Unprocessable Entity**
- Invalid coordinates format
- Too many waypoints (max 25, or 12 for EV routing)
- Invalid profile name
- Coordinates outside supported regions

**Error: 429 Too Many Requests**
- Rate limit exceeded
- Wait before retrying
- Consider upgrading account tier

**Solutions**:

1. **Validate request format**:
```kotlin
val origin = Point.fromLngLat(-122.4194, 37.7749)
val destination = Point.fromLngLat(-118.2437, 34.0522)

val directions = MapboxDirections.builder()
    .accessToken(YOUR_TOKEN)
    .profile(DirectionsCriteria.PROFILE_DRIVING_TRAFFIC)
    .origin(origin)
    .destination(destination)
    .build()
```

2. **Check coordinates are valid**:
   - Longitude: -180 to 180
   - Latitude: -90 to 90
   - Format: `longitude, latitude` (NOT lat, lng)

3. **Implement retry logic**:
```kotlin
override fun onFailure(call: Call<DirectionsResponse>, t: Throwable) {
    if (t is HttpException && t.code() == 429) {
        // Wait and retry
        Handler(Looper.getMainLooper()).postDelayed({
            call.clone().enqueue(this)
        }, 5000)
    }
}
```

### Flutter Integration Issues

#### Method Channel Not Working

**Symptoms**:
- Method calls from Flutter not received in Kotlin
- `MissingPluginException` errors

**Causes**:
1. Channel name mismatch
2. MainActivity not registered
3. Method handler not set

**Solutions**:

1. **Ensure matching channel names**:

Flutter:
```dart
static const platform = MethodChannel('routewhisper.com/navigation');
```

Kotlin:
```kotlin
private val methodChannel = "routewhisper.com/navigation"
```

2. **Set handler in configureFlutterEngine**:
```kotlin
override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        methodChannel
    ).setMethodCallHandler { call, result ->
        // Handle calls
    }
}
```

#### Flutter Maps + Native Navigation Conflict

**See "Duplicate Class Errors" section above.**

### Token and Authentication Issues

#### Token Scope Issues

**Problem**: Features not working despite valid token

**Solution**: Verify token has required scopes:
- **Map display**: `styles:read`, `fonts:read`
- **SDK downloads**: `downloads:read` (secret token)
- **Style editing**: `styles:write` (secret token)

#### Token Exposure

**Problem**: Public token exposed in APK

**Answer**: This is normal and expected. Public tokens are designed to be client-side.

**Security**:
- Use URL restrictions if possible
- Rotate tokens if compromised
- Never expose secret tokens

## Debugging Commands

### Check Gradle dependencies
```bash
./gradlew :app:dependencies
```

### Check token validity
```bash
curl "https://api.mapbox.com/v1/tokens?access_token=YOUR_TOKEN"
```

### Test Directions API
```bash
curl "https://api.mapbox.com/directions/v5/mapbox/driving/-122.4194,37.7749;-118.2437,34.0522?access_token=YOUR_TOKEN"
```

### Check APK contents
```bash
unzip -l app-debug.apk | grep mapbox
```

### View logs
```bash
adb logcat | grep -i mapbox
```

## Getting Help

### Resources
- Official Documentation: https://docs.mapbox.com/
- Community Support: https://github.com/mapbox/mapbox-navigation-android/issues
- Stack Overflow: Tag with `mapbox` and `android`

### Providing Information
When asking for help, include:
1. Navigation SDK version
2. Android SDK version
3. Full error message and stack trace
4. Relevant code snippets
5. `build.gradle` dependencies section

## Related Documentation
- Installation: docs/mapbox/navigation/installation-setup.md
- Token Scopes: docs/mapbox/reference/token-scopes.md
- Initialization: docs/mapbox/navigation/initialization.md
