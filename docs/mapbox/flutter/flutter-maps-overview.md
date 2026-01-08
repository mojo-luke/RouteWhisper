# Mapbox Maps SDK for Flutter

## Overview
The Mapbox Maps SDK for Flutter enables developers to embed highly customized maps into iOS and Android applications using a single codebase.

## Key Features
- **Map Style Selection**: Access to Mapbox Standard, Satellite, and custom styles
- **Runtime Styling**: Modify map appearance dynamically
- **Camera Manipulation**: Control viewing angles and zoom levels
- **Map Querying**: Interact with map elements programmatically
- **User Interaction**: Handle touch events, gestures
- **3D Terrain**: Enhance maps with elevation data
- **Custom Data Visualization**: Add markers, layers, and styled features
- **Responsive Styling**: Alter appearance based on data properties and device settings

## System Requirements
- **iOS**: 14 or higher
- **Android SDK**: 21 or higher
- **Flutter SDK**: 3.22.3 or higher
- **Dart SDK**: 3.4.4 or higher

## Current Version
v2.17.0

## Integration with Mapbox Studio
Design custom map styles in Mapbox Studio web interface that seamlessly match your brand and application design, then integrate them with the Flutter SDK.

## Installation

### Add Dependency
In `pubspec.yaml`:
```yaml
dependencies:
  mapbox_maps_flutter: ^2.17.0
```

### Configure Tokens

**iOS** (`ios/Runner/Info.plist`):
```xml
<key>MBXAccessToken</key>
<string>YOUR_MAPBOX_ACCESS_TOKEN</string>
```

**Android** (`android/app/src/main/res/values/developer-config.xml`):
```xml
<resources>
    <string name="mapbox_access_token">YOUR_MAPBOX_ACCESS_TOKEN</string>
</resources>
```

## Basic Usage

```dart
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMap? mapboxMap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MapWidget(
        key: ValueKey("mapWidget"),
        onMapCreated: _onMapCreated,
      ),
    );
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    this.mapboxMap = mapboxMap;
  }
}
```

## Legal Requirements

### Attribution
Maps using this SDK must display the Mapbox wordmark unless data comes entirely from non-Mapbox sources. Attribution positioning and styling may be adjusted for design purposes.

### Telemetry
The SDK includes Mapbox Telemetry by default, sending de-identified location and usage data. Apps must provide users with an opt-out option, automatically included in the attribution control.

## Important Limitations

### Conflict with Native Navigation SDK
**CRITICAL**: The Flutter Maps SDK (`mapbox_maps_flutter`) **cannot be used alongside the native Android Navigation SDK** due to dependency conflicts.

**Why**:
- Flutter Maps plugin includes Mapbox common libraries (non-ndk27 variants)
- Native Navigation SDK uses ndk27 variants
- Both dependencies cause duplicate class errors

**Solution**:
Choose one approach:
1. **Flutter Maps UI only** - Use `mapbox_maps_flutter` for map display and build custom navigation in Flutter
2. **Native Navigation SDK** - Remove `mapbox_maps_flutter` and use native Android/iOS Navigation SDKs with method channels

### No Turn-by-Turn Navigation Features
Flutter Maps SDK provides **map display only**. It does NOT include:
- Turn-by-turn navigation
- Voice instructions
- Route line rendering (must implement manually)
- Navigation camera (must implement manually)
- Automatic rerouting
- GPS enhancement/dead reckoning

To add navigation features, you must either:
1. Build them yourself using Directions API + Flutter Maps
2. Use native Navigation SDKs via platform channels (recommended)

## When to Use Flutter Maps SDK

**Good use cases**:
- Cross-platform map display
- Custom data visualization
- Location-based apps without navigation
- Apps that already have custom navigation logic

**Not ideal for**:
- Turn-by-turn navigation apps (use native Navigation SDK)
- Apps requiring production-ready navigation features
- Apps needing voice guidance and automatic rerouting

## Alternative: Native Navigation SDK via Platform Channels

For navigation apps, prefer:
1. Use native Android Navigation SDK (Kotlin)
2. Use native iOS Navigation SDK (Swift)
3. Bridge to Flutter via method channels
4. Keep Flutter UI minimal (just launcher)

This approach provides:
- Full turn-by-turn navigation
- Voice instructions
- Pre-built UI components
- Production-ready features
- No dependency conflicts (Flutter doesn't include Maps SDK)

## Documentation
- Flutter Maps SDK Guide: https://docs.mapbox.com/flutter/maps/guides/
- API Reference: https://docs.mapbox.com/flutter/maps/api/
- Examples: https://docs.mapbox.com/flutter/maps/examples/
