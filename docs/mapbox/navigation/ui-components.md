# Mapbox Navigation SDK - UI Components

## Overview
The Navigation SDK offers **several pre-built UI components** that developers can combine to create custom navigation experiences. Components provide smart defaults for quick implementation or customization options for unique designs.

## Adding UI Components Dependency

UI components require explicit dependency addition (separate from core navigation):

```gradle
dependencies {
    implementation "com.mapbox.navigationcore:ui-components:3.18.0-beta.1"

    // For NDK 27
    implementation "com.mapbox.navigationcore:ui-components-ndk27:3.18.0-beta.1"
}
```

## Available UI Components

### 1. Maps
Integration with Mapbox Maps SDK for map display and enhancement.

### 2. Navigation Camera
Frames user location and ensures route visibility with automatic camera movements.

### 3. Route Line
Renders routes on the map with:
- Alternative route support
- Customizable styling (colors, width, etc.)
- Traffic congestion visualization

### 4. Route Arrow
Displays next maneuver indicators (turn arrows) on the route.

### 5. Route Callouts
Shows route duration with customizable styling.

### 6. Maneuver Instructions
Provides text-based directional guidance:
- Turn-by-turn instructions
- Street names
- Distance to next maneuver

### 7. Voice Instructions
Handles audio guidance:
- Prompt announcements (e.g., "In 500 feet, turn right")
- Detailed guidance
- Multiple language support
- Customizable voice profiles

### 8. Signboards
Displays street sign-aligned textual/graphical data:
- Exit numbers
- Street names
- Highway shields

### 9. Junctions
Complex road network visualization:
- Intersection layouts
- Lane guidance
- Complex interchange graphics

### 10. Speed Limit
Speed limit display component showing:
- Current speed limit
- Unit (mph or km/h)
- Visual alerts for speeding

### 11. Trip Progress
Shows navigation progress:
- ETA (estimated time of arrival)
- Remaining distance
- Remaining time
- Current speed

### 12. Arrival Detection
Waypoint and destination visualization:
- Arrival notifications
- Multi-waypoint support
- Custom arrival UI

### 13. Building Highlights
Extrudes buildings at waypoints/destinations in 3D for better visibility.

### 14. Device Notifications
Native Android notification handling:
- Foreground service notifications
- Navigation progress in notification tray
- Quick actions (stop navigation, etc.)

### 15. Status View
Quick status message display for:
- Rerouting notifications
- GPS signal loss
- Traffic alerts
- General navigation status

## Usage Pattern

Most developers will use these components together in a navigation Activity:

1. **MapView** - Display the map
2. **NavigationCamera** - Auto-frame the route
3. **Route Line** - Show the route
4. **Maneuver Instructions** - Display turn info
5. **Voice Instructions** - Speak directions
6. **Trip Progress** - Show ETA/distance
7. **Speed Limit** - Display speed info

## Customization

All components support:
- Custom styling via XML/code
- Event listeners for user interactions
- Visibility control
- Layout customization

## Drop-in UI vs Custom UI

**Drop-in UI**: Pre-assembled navigation screen with all components configured
- Fastest implementation
- Less control over layout

**Custom UI**: Pick and place individual components
- Full layout control
- Can match your app's design
- More development time

## Documentation Links
- Full UI Components Guide: https://docs.mapbox.com/android/navigation/guides/ui-components/
- Drop-in UI: https://docs.mapbox.com/android/navigation/guides/ui-components/drop-in-ui/
- Custom UI Examples: https://docs.mapbox.com/android/navigation/examples/
