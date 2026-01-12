# Phase 4: Waypoint Arrival Testing Guide

## Test Route Overview
**Route**: Embarcadero Center → Fisherman's Wharf (San Francisco)
- **Distance**: ~2.5 miles
- **Duration**: ~10 minutes (real time) → ~7 minutes at 1.5x simulation speed
- **POI Density**: High - lots of restaurants, cafes, scenic spots

## Route Coordinates
- **Origin**: Embarcadero Center
  - Latitude: 37.7955
  - Longitude: -122.3937

- **Destination**: Fisherman's Wharf
  - Latitude: 37.8080
  - Longitude: -122.4177

## Expected POIs Along Route

### Restaurants
- Ferry Building Marketplace (37.7955, -122.3937)
- The Slanted Door
- Fog Harbor Fish House (Pier 39)
- Boudin Bakery Café
- Multiple seafood restaurants near Fisherman's Wharf

### Cafes
- Blue Bottle Coffee (Ferry Building)
- Philz Coffee
- Starbucks (multiple locations)
- Local coffee shops along Embarcadero

### Scenic/Attractions
- Ferry Building
- Pier 7 (great photo spot)
- Pier 15 (Exploratorium)
- Pier 39
- Sea Lions at Pier 39
- Aquarium of the Bay

### Gas Stations
- Limited on waterfront route (use for testing if needed)

## Testing Workflow

### Step 1: Start Test Route
1. Open RouteWhisper app
2. Tap **"Test Route (10 min)"** button
3. Wait for route calculation (~3-5 seconds)
4. Route will display on map

### Step 2: Discover POIs
1. Tap **"Discover POIs"** button
2. Backend will find POIs within 5 miles of route
3. Review POI list (expect 10-15 results)
4. Categories: restaurants, cafes, scenic, parks

### Step 3: Add Waypoints
**Option A: From POI List**
1. Tap "Add Stop" on any POI
2. Waypoint appears in list with default duration
3. Tap on waypoint to edit stop duration

**Option B: Manual Search**
1. Tap "Add Stop" (+ button)
2. Search for "Ferry Building" or "Pier 39"
3. Select from results
4. Set stop duration (5-60 min)

### Step 4: Test Multiple Waypoints
Add 2-3 waypoints for testing:
1. **First Stop**: Ferry Building (5-10 min) - near origin
2. **Second Stop**: Pier 15 or Exploratorium (15-20 min) - mid-route
3. **Third Stop**: Pier 39 (30-45 min) - near destination

### Step 5: Start Navigation
1. Review waypoint list
2. Tap **"Start Navigation"**
3. Simulation begins at 1.5x speed
4. Watch for waypoint arrival notifications

## Testing Arrival Detection

### What to Expect
1. **Arrival Trigger** (~50m from waypoint):
   - MapActivity.kt ArrivalObserver fires
   - Flutter receives "waypointArrived" event
   - WaypointArrivalNotification appears

2. **Arrival UI Features**:
   - Waypoint name displayed
   - Live stop timer (updates every second)
   - Planned duration shown
   - "I'm Here" acknowledgment button
   - "Skip" and "Continue" buttons
   - Overtime indicator (turns orange if exceeding plan)

3. **Manual Departure**:
   - Tap "Continue" button
   - Stop history sent to backend
   - Notification dismisses
   - Navigation continues to next waypoint

4. **Automatic Departure** (if moving):
   - System detects: speed >5mph AND distance >50m
   - Automatic departure triggered
   - Stop history sent to backend
   - Continues to next waypoint

### Checking Backend Logs
Backend logs should show:
```
📊 Stop recorded: Ferry Building (planned: 10min, actual: 12min, diff: +2min, auto: false)
   📍 Location: (37.7955, -122.3937)
   📅 Time: Friday 02:30PM (day 4, hour 14)
   🏷️  Category: restaurant
```

## Simulated Navigation Limitations

### Known Issues
1. **Speed Detection**: Simulated movement may not trigger auto-departure
   - Locations jump instantly between points
   - No realistic acceleration/deceleration
   - **Solution**: Use manual "Continue" button for testing

2. **Arrival Timing**: May arrive slightly before/after 50m threshold
   - Depends on simulation point spacing
   - ArrivalObserver should still fire correctly

3. **Background Monitoring**: Auto-departure may not work in simulation
   - Real-world: User exits car, walks, returns, drives
   - Simulation: Instant jumps without realistic movement patterns
   - **Solution**: Test manual flow primarily

## Success Criteria

### ✅ Phase 4 Working If:
1. Waypoint arrival notification appears when reaching POI
2. Live timer counts up from 00:00
3. Overtime indicator shows when exceeding planned time
4. "Continue" button records stop and proceeds
5. Backend receives stop history with all fields
6. Navigation continues smoothly to next waypoint
7. All waypoints can be visited in sequence

### ❌ Issues to Report:
- Arrival notification doesn't appear
- Timer doesn't update
- Backend errors in logs
- Navigation freezes after departure
- Crashes during waypoint arrival

## Debug Tips

### Flutter Console
Look for these log messages:
```dart
📍 Flutter: Waypoint arrival - leg 0 at (37.7955, -122.3937)
📍 Arrived at Ferry Building at 2026-01-10 14:30:25
📤 Sending stop history to backend...
✅ Stop history recorded: Stop history recorded successfully
📍 Departed Ferry Building manually after 12 minutes
```

### Android Logcat
Look for these in MapActivity:
```kotlin
📍 ARRIVAL: Waypoint at leg 0
🔍 Started departure monitoring for waypoint at (37.7955, -122.3937)
📍 Location update: lat=37.7960, lng=-122.3940, bearing=45.0
🚗 Auto-departure detected: 55.3m away, 6.2mph
```

### Backend Logs
```python
INFO:     127.0.0.1:52101 - "POST /api/v1/waypoints/history HTTP/1.1" 200 OK
📊 Stop recorded: Ferry Building (planned: 10min, actual: 12min, diff: +2min, auto: false)
```

## Alternative Test Routes

If Embarcadero route has issues:

### Berkeley to Oakland (4 miles, 12 min)
```dart
originLat: 37.8703,   // Berkeley BART
originLng: -122.2680,
destLat: 37.8044,     // Lake Merritt
destLng: -122.2712,
```
**POIs**: Multiple restaurants, gas stations, cafes along Telegraph/Broadway

### Palo Alto to Mountain View (4.5 miles, 12 min)
```dart
originLat: 37.4443,   // University Ave
originLng: -122.1598,
destLat: 37.3935,     // Castro St
destLng: -122.0815,
```
**POIs**: Tech cafes, restaurants, Google campus area

## Next Steps After Testing

Once Phase 4 works:
1. **Phase 5**: Add waypoints during navigation (dynamic)
2. **Phase 6**: MongoDB storage for stop history
3. **Analytics**: Category averages, time patterns, personalization

## Questions?
Check logs in order:
1. Flutter console (Dart/Flutter side)
2. Android Logcat (Native side)
3. Backend logs (API side)

Full flow: MapActivity → Flutter Controller → NavigationService → Backend
