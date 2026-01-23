# Flutter Engine Sharing Fix

## Problem
When tapping the "Find Stops" button in MapActivity, the app crashed with:
```
FATAL EXCEPTION: java.lang.AssertionError: The internal FlutterEngine created by MainActivity
has been attached to by another activity.
```

**Root Cause:** MainActivity created an internal FlutterEngine and cached it, but it remained attached to MainActivity. When TransparentFlutterActivity tried to use the cached engine, Flutter threw an error because one engine cannot be attached to two activities simultaneously.

## Solution: Shared FlutterEngine Pattern

### Architecture
```
RouteWhisperApplication (on app startup)
  ↓ Creates FlutterEngine
  ↓ Caches it with ID "routewhisper_shared_engine"
  ↓
MainActivity
  ↓ Uses cached engine via getCachedEngineId()
  ↓ Configures method channels
  ↓ Launches MapActivity
  ↓
MapActivity (native navigation)
  ↓ User taps "Find Stops"
  ↓ Launches TransparentFlutterActivity
  ↓
TransparentFlutterActivity
  ↓ Uses same cached engine via getCachedEngineId()
  ↓ Calls showOverlay method channel
  ↓
Flutter (shared state preserved!)
  ↓ Shows POI modal
  ✅ Can access WaypointManager, NavigationService, etc.
```

### Changes Made

#### 1. RouteWhisperApplication.kt (Modified)
- Added FlutterEngine creation on app startup
- Engine is created BEFORE any activity launches
- Engine is cached with shared ID
- Both MainActivity and TransparentFlutterActivity use this pre-created engine

#### 2. MainActivity.kt (Modified)
- Added `getCachedEngineId()` override to use shared engine
- Removed engine caching logic from `configureFlutterEngine()` (no longer needed)
- Now uses the engine created by RouteWhisperApplication

#### 3. MapActivity.kt (Modified)
- Reverted back to launching TransparentFlutterActivity
- No longer uses direct method channel calls (those would show on wrong activity)

#### 4. TransparentFlutterActivity.kt (Already correct)
- Already had `getCachedEngineId()` override ✓
- Already registered in AndroidManifest.xml ✓

### Why This Works

1. **Single Engine Creation Point:** The engine is created once in RouteWhisperApplication
2. **Proper Lifecycle:** Flutter handles activity attach/detach automatically when activities share a cached engine
3. **Shared State:** Both MainActivity and TransparentFlutterActivity access the same Dart isolate, preserving all Flutter state
4. **No Conflicts:** Flutter knows how to handle multiple activities using the same cached engine

### Benefits

- ✅ No engine conflicts
- ✅ Flutter state preserved (WaypointManager works!)
- ✅ Clean architecture (engine lifecycle managed in Application class)
- ✅ Works for future activities that need Flutter UI

## Testing

### Build and Install
```bash
cd /Users/lukesimmons/Projects/RouteWhisper/frontend
flutter clean
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### Monitor Logs
```bash
adb logcat -c && adb logcat | grep -E "(RouteWhisper|MapActivity|TransparentFlutter|showOverlay|🔍|✅|❌)"
```

### Expected Log Sequence
```
RouteWhisperApp: Creating shared FlutterEngine...
RouteWhisperApp: ✅ Shared FlutterEngine created and cached: routewhisper_shared_engine
MainActivity: Configuring shared Flutter engine: routewhisper_shared_engine

[User starts navigation]
MapActivity: Find Stops button clicked - launching POI discovery overlay
MapActivity: ✅ POI discovery overlay launched
TransparentFlutterActivity: Created transparent overlay for route: /poi-discovery
TransparentFlutterActivity: ✅ Overlay request sent successfully
flutter: 🔍 Opening Flutter overlay: /poi-discovery
flutter: ✅ Navigator context found, opening overlay modal...
flutter: ✅ Overlay modal initiated
```

## Files Modified

1. `RouteWhisperApplication.kt` - Added shared FlutterEngine creation
2. `MainActivity.kt` - Use cached engine instead of creating internal one
3. `MapActivity.kt` - Launch TransparentFlutterActivity (cleaner approach)

## Commit Message
```
fix(POI): Resolve FlutterEngine sharing conflict between MainActivity and TransparentFlutterActivity

- Move FlutterEngine creation to RouteWhisperApplication
- MainActivity now uses cached engine via getCachedEngineId()
- Fixes crash: "The internal FlutterEngine created by MainActivity has been attached to by another activity"
- Preserves Flutter state across activities (WaypointManager, etc.)
```

---

**Date:** January 23, 2026
**Status:** ✅ Ready for testing
