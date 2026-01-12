# Technical Debt & Optimizations

## High Priority

### 1. Proximity-Based POI Discovery & Search
**Issue**: POIs and search results aren't well-optimized for proximity to route.

**Current Behavior**:
- POI Discovery: Uses only route midpoint as proximity → misses POIs near start/end
- Place Search: No proximity parameter → returns global results

**Proposed Fix**:
- POI Discovery: Sample multiple points along route (start, 25%, 50%, 75%, end) and aggregate
- Place Search: Pass route origin or current location as proximity bias

**Impact**: Medium - Improves UX but doesn't block functionality

**Effort**: ~30-45 minutes

**When**: After Phase 6 (Personalization) complete, as part of optimization phase

**Files**:
- `backend/app/main.py` - `/api/v1/route/pois` endpoint
- `backend/app/main.py` - `/api/v1/search/geocode` endpoint
- `frontend/lib/widgets/search_waypoint_dialog.dart` - Pass proximity to backend

---

## Medium Priority

### 2. Waypoint Arrival Notification UI
**Issue**: Basic Snackbar instead of rich arrival notification overlay.

**Current Behavior**:
- Shows simple Snackbar: "📍 Arrived at waypoint N" with "Continue" action
- Auto-dismisses after a few seconds
- No timer, no stop duration tracking, minimal interaction

**Proposed Fix** (from plan Phase 4, Step 4C):
- Rich overlay dialog with waypoint name and estimated stop duration
- Live timer showing elapsed time vs planned duration (turns orange when over)
- Interactive buttons: "I'm Here" (acknowledge), "Continue" (manual departure), "Skip" (skip waypoint)
- Auto-departure hint: "Auto-continues when you start driving"
- Material Design 3 styling matching Flutter theme

**Impact**: Low - Current implementation is functional, this is UX enhancement

**Effort**: 4-6 hours (port Flutter design to native Android)

**When**: After Phase 5 (Dynamic Navigation) or Phase 6 (Personalization)

**Files**:
- `frontend/android/app/src/main/kotlin/.../MapActivity.kt` (lines 343-362) - Current Snackbar implementation
- Plan reference: `/Users/lukesimmons/.claude/plans/bright-seeking-valley.md` Phase 4, Step 4C

**Note**: All underlying functionality works (arrival detection, departure detection, timer tracking, backend API). Only the UI is simplified.

---

### 3. Waypoint Progress Display (Google Maps-style)
**Issue**: Only shows total trip progress, not individual waypoint progress.

**Current Behavior**:
- Top: Turn-by-turn instructions (maneuver view)
- Bottom: Total trip ETA/distance (trip progress view)
- No indication of which waypoint you're heading to or how far to next stop

**Proposed Behavior** (Google Maps-style):
- Top: Turn-by-turn instructions (keep as-is)
- Middle: **NEW** Waypoint progress card showing:
  - "Next stop: [Waypoint Name]" (e.g., "Next stop: Shell Gas Station")
  - Distance to waypoint (e.g., "2.3 mi")
  - ETA to waypoint (e.g., "5 min")
  - Waypoint number indicator (e.g., "Stop 1 of 3")
- Bottom: Total trip ETA/distance (keep as-is)

**Implementation Requirements**:
1. **Data Flow Changes**:
   - Pass waypoint names from Flutter to Android (currently only coordinates are passed)
   - Store waypoint names array in MapActivity alongside coordinates
   - Match leg index to waypoint name

2. **UI Changes**:
   - Add new TextView/CardView in `activity_map.xml` between maneuver and trip progress views
   - Create custom view or use Material Card with TextViews
   - Update in RouteProgressObserver using `currentLegProgress.distanceRemaining` and `durationRemaining`

3. **Logic**:
   - Check if current leg is intermediate (not final destination)
   - If intermediate: Show waypoint card with leg-specific progress
   - If final leg: Hide waypoint card (or show "Final destination")

**Impact**: Medium - Significantly improves UX for multi-waypoint trips, matches user expectations from Google Maps

**Effort**: 3-4 hours
- 1 hour: Update method channel to pass waypoint names
- 1 hour: Create waypoint progress UI component
- 1 hour: Wire up logic to update from RouteProgressObserver
- 1 hour: Testing with multiple waypoints

**When**: Before marking Step 5 (Waypoint Management) as complete

**Files**:
- `frontend/lib/services/navigation_service.dart` - Add waypoint names to startNavigation call
- `frontend/android/app/src/main/kotlin/.../MainActivity.kt` - Accept waypoint names in Intent
- `frontend/android/app/src/main/kotlin/.../MapActivity.kt` - Store and display waypoint names
- `frontend/android/app/src/main/res/layout/activity_map.xml` - Add waypoint progress view

**Priority Note**: This is listed as Medium but should be done before considering Step 5 complete.

---

## Low Priority

(Add low-priority items here)

---

**Last Updated**: January 10, 2026
