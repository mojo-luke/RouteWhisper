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

## Low Priority

(none recorded)

---

**Last Updated**: 2026-05-06 (item #3, Google Maps-style waypoint progress display, removed — shipped in commits `58a2261` / `9b4183a`)
