# RouteWhisper User Flows

**Last Updated:** January 23, 2026
**Purpose:** Document all major user flows to ensure consistent UX

---

## Table of Contents

1. [Basic Navigation](#1-basic-navigation)
2. [POI Discovery During Navigation](#2-poi-discovery-during-navigation)
3. [Multi-Stop Route Planning](#3-multi-stop-route-planning)
4. [Waypoint Management](#4-waypoint-management)
5. [Route Recalculation](#5-route-recalculation)
6. [Error Recovery](#6-error-recovery)

---

## 1. Basic Navigation

### User Story
As a driver, I want to navigate to a destination so that I can get turn-by-turn directions.

### Happy Path Flow

```
[Home Screen]
    ↓ User enters destination
    ↓ Taps "Search"
[Search Results]
    ↓ User selects destination
[Route Preview]
    ↓ Shows route, ETA, distance
    ↓ User taps "Start Navigation"
[MapActivity - Navigation Mode]
    ↓ Turn-by-turn directions
    ↓ Voice guidance
    ↓ Live progress updates
[Arrival]
    ↓ "You've arrived"
    ↓ Auto-return to home after 5s
```

### States
- **Idle** - No route set
- **Calculating** - Route being calculated
- **Ready** - Route calculated, ready to start
- **Navigating** - Active turn-by-turn navigation
- **Completed** - Arrived at destination

### Edge Cases

**No destination entered:**
- Show error: "Please enter a destination"
- Keep user on home screen

**Route calculation fails:**
- Show error: "Could not calculate route"
- Offer "Try Again" button
- Log error details for debugging

**GPS lost during navigation:**
- Show banner: "GPS signal lost"
- Continue showing last known position
- Auto-resume when signal returns

### Testing Checklist
- [ ] Can enter destination via search
- [ ] Route calculates within 2 seconds
- [ ] Navigation starts without errors
- [ ] Voice guidance works
- [ ] Arrival detected correctly
- [ ] Returns to home after arrival

---

## 2. POI Discovery During Navigation

### User Story
As a driver on a road trip, I want to find interesting stops along my route without leaving navigation or manually searching.

### Happy Path Flow (FIXED)

```
[MapActivity - Navigating]
    ↓ User taps "Find Stops" FAB
[POI Modal Overlay]
    ↓ Shows POIs along route (cached or live)
    ↓ Displays: restaurants, gas, attractions
    ↓ User taps a POI card
[POI Details Sheet]
    ↓ Shows: name, distance, ETA, rating, category
    ↓ User taps "Add Stop"
[POI Modal Closes]
    ↓ Snackbar: "Shell Gas Station added"
    ↓ Shows "UNDO" button (5 seconds)
[MapActivity - Navigating]
    ↓ Route recalculates IN-PLACE
    ↓ New route shows on map
    ↓ Waypoint progress card updates
    ↓ Navigation continues seamlessly
    ✅ User never left MapActivity
```

### States
- **Modal Closed** - POI discovery not visible
- **Loading POIs** - Fetching from backend
- **Showing POIs** - List displayed
- **POI Details** - Bottom sheet with details
- **Adding Waypoint** - Processing add + recalculate
- **Route Updated** - Navigation continues

### Key UX Requirements

1. **Never Leave MapActivity**
   - POI modal is an overlay, not a new activity
   - Route updates happen in-place
   - User stays in navigation context

2. **Immediate Feedback**
   - POI list shows within 2 seconds (or cached immediately)
   - "Add Stop" button shows loading spinner
   - Route recalculation starts immediately

3. **Undo Support**
   - Snackbar with "UNDO" button (5 seconds)
   - Undo removes waypoint and recalculates again
   - Clear confirmation of undo action

4. **Seamless Continuation**
   - Navigation audio doesn't stop
   - Turn-by-turn instructions continue
   - Progress bar updates with new route

### Edge Cases

**No POIs found:**
- Show: "No POIs found along your route"
- Offer: "Search Again" button
- Suggest: Increase search radius

**Backend API fails:**
- Show cached POIs if available
- Display: "Showing cached results"
- Fallback: "Could not load POIs. Try again?"

**User adds multiple POIs:**
- Each addition recalculates route
- Show progress: "Updating route..."
- Optimize: Batch if user adds multiple quickly

**User taps "Add Stop" twice:**
- Disable button after first tap
- Show loading state
- Prevent duplicate additions

### Testing Checklist
- [ ] "Find Stops" button visible during navigation
- [ ] Tapping button opens POI modal (not new activity)
- [ ] POIs load within 2 seconds
- [ ] POI details sheet shows all info
- [ ] "Add Stop" adds waypoint and updates route
- [ ] Snackbar shows with "UNDO" button
- [ ] Undo removes waypoint correctly
- [ ] User never leaves MapActivity
- [ ] Navigation continues smoothly
- [ ] Works with no internet (cached POIs)

### Implementation Requirements

**Frontend (Flutter):**
- POIDashboard opens as modal (not new route)
- Calls `updateNavigationRoute()` not `calculateRoute()`
- Shows optimistic UI (immediate waypoint add)
- Handles undo gracefully

**Backend (MapActivity):**
- Listens for `updateNavigationRoute` on method channel
- Recalculates route with new waypoints
- Sends updated route to MapView
- Doesn't restart navigation session

**State Management:**
- WaypointManager adds waypoint
- Notifies Provider listeners
- Waypoint list rebuilds automatically
- Progress card updates automatically

---

## 3. Multi-Stop Route Planning

### User Story
As a road tripper, I want to plan a multi-stop route before starting navigation so I can visit multiple places efficiently.

### Happy Path Flow

```
[Home Screen]
    ↓ User enters destination
[Route Preview]
    ↓ User taps "Add Stops"
[Waypoint Planning Screen]
    ↓ Shows: origin → destination
    ↓ User taps "Discover POIs"
[POI Discovery]
    ↓ Shows POIs along planned route
    ↓ User adds 3 POIs as stops
[Waypoint Planning Screen]
    ↓ Shows: origin → stop1 → stop2 → stop3 → dest
    ↓ Route updates with each addition
    ↓ Shows total time and distance
    ↓ User taps "Start Navigation"
[MapActivity - Navigation Mode]
    ↓ Navigate to first stop
    ↓ Arrive → Navigate to second stop
    ↓ Continue until final destination
```

### States
- **Planning** - Adding/removing waypoints
- **Optimizing** - Reordering for efficiency
- **Ready** - Route complete, ready to navigate
- **Navigating** - Active multi-stop navigation

### Features

**Drag to Reorder:**
- User can drag waypoints to reorder
- Route recalculates on drop
- Shows time savings/loss

**Remove Waypoint:**
- Swipe to delete or tap trash icon
- Shows undo snackbar
- Route updates immediately

**Optimize Route:**
- "Optimize" button reorders stops
- Shows before/after comparison
- User can accept or revert

### Edge Cases

**Too many waypoints (>10):**
- Show warning: "Maximum 10 stops"
- Suggest: "Remove a stop to add more"

**Waypoints out of order:**
- Offer: "Optimize route?" button
- Show time savings if optimized

**Duplicate waypoints:**
- Prevent adding same POI twice
- Show: "Already added to route"

### Testing Checklist
- [ ] Can add multiple waypoints before navigation
- [ ] Route updates with each addition
- [ ] Can reorder waypoints via drag
- [ ] Can remove waypoints
- [ ] Optimization works correctly
- [ ] Start navigation with all stops

---

## 4. Waypoint Management

### User Story
As a driver with multiple stops, I want to manage my waypoints during navigation so I can skip or reorder stops as plans change.

### Happy Path Flow

```
[MapActivity - Navigating to Stop 1]
    ↓ User opens waypoint list
[Waypoint List Bottom Sheet]
    ↓ Shows: [✓ Origin] → [• Stop 1] → [ Stop 2] → [ Dest]
    ↓ User taps "Skip" on Stop 1
[Confirmation Dialog]
    ↓ "Skip Shell Gas Station?"
    ↓ User taps "Yes, Skip"
[MapActivity - Navigating to Stop 2]
    ↓ Route recalculates
    ↓ Now navigating to Stop 2
    ↓ Snackbar: "Skipped Shell. UNDO?"
```

### Actions

**Skip Waypoint:**
- Marks as skipped (not deleted)
- Recalculates route to next stop
- Provides undo option

**Mark as Completed:**
- Manual completion if auto-detect fails
- Updates progress
- Continues to next stop

**Remove Waypoint:**
- Permanently removes from route
- Recalculates route
- Provides undo option

**Add New Stop:**
- Opens POI discovery
- Inserts into route order
- Recalculates route

### Edge Cases

**Skip last waypoint:**
- Navigate directly to destination
- Show confirmation: "Skip to destination?"

**Skip while approaching waypoint:**
- Show: "Approaching stop. Skip anyway?"
- Confirm action

**Undo after arrival:**
- If user arrived and departed, undo is disabled
- Show: "Already departed from this stop"

### Testing Checklist
- [ ] Can open waypoint list during navigation
- [ ] Skip updates route immediately
- [ ] Undo skip works correctly
- [ ] Mark as complete works
- [ ] Remove waypoint works
- [ ] Add new stop works

---

## 5. Route Recalculation

### User Story
As a driver, when I deviate from the route or add stops, I want the route to recalculate automatically without interrupting navigation.

### Trigger Events

**Automatic Recalculation:**
- User deviates from route (> 50m off)
- Waypoint added
- Waypoint removed
- Waypoint skipped
- Traffic update (future)

**Manual Recalculation:**
- User taps "Recalculate" button
- User changes route preferences (avoid tolls, etc.)

### Happy Path Flow

```
[Navigating on Route A]
    ↓ User adds a waypoint
[Recalculating]
    ↓ Shows progress indicator
    ↓ Keeps current navigation active
    ↓ Calculates new route in background
[Route Updated]
    ↓ New route displays on map
    ↓ ETA and distance update
    ↓ Voice: "Route updated. Continue on [street]"
    ↓ Navigation continues seamlessly
```

### States
- **Active Route** - Following current route
- **Recalculating** - New route being calculated
- **Route Updated** - New route applied
- **Recalculation Failed** - Fallback to original route

### UX Requirements

1. **Non-Blocking**
   - Recalculation happens in background
   - Current navigation continues
   - No loading screens that block UI

2. **Visual Feedback**
   - Progress indicator during calculation
   - New route animates onto map
   - ETA updates smoothly

3. **Voice Feedback**
   - "Route updated" announcement
   - Next instruction after update

4. **Error Handling**
   - If recalculation fails, keep original route
   - Show error message
   - Offer manual retry

### Edge Cases

**Recalculation takes > 5 seconds:**
- Show: "Still calculating..."
- Allow user to cancel
- Fallback to original route if cancel

**Recalculation fails:**
- Keep current route
- Show error: "Could not update route"
- Offer "Try Again" button

**Multiple recalculations queued:**
- Cancel pending if new one requested
- Use latest request only
- Don't spam the backend

### Testing Checklist
- [ ] Adding waypoint triggers recalculation
- [ ] Removing waypoint triggers recalculation
- [ ] Deviating from route triggers recalculation
- [ ] Recalculation doesn't stop navigation
- [ ] UI shows progress during calculation
- [ ] Voice announces route update
- [ ] Failed recalculation handled gracefully

---

## 6. Error Recovery

### User Story
As a driver, when something goes wrong, I want clear feedback and recovery options so I can continue my journey.

### Common Errors

#### Network Connection Lost

**Symptoms:**
- POI discovery fails
- Route calculation fails
- Map tiles don't load

**Flow:**
```
[Network Lost]
    ↓ Show banner: "No internet connection"
    ↓ Continue navigation with cached route
    ↓ Disable POI discovery button
[Network Restored]
    ↓ Hide banner
    ↓ Re-enable features
    ↓ Sync any pending data
```

**Recovery:**
- Use cached data when available
- Queue actions for when online
- Clear messaging about offline status

#### GPS Signal Lost

**Flow:**
```
[GPS Lost]
    ↓ Show banner: "GPS signal lost"
    ↓ Keep showing last known position
    ↓ Dim map slightly (indicate uncertainty)
[GPS Restored]
    ↓ Hide banner
    ↓ Resume normal navigation
    ↓ Recalculate if user drifted far
```

**Recovery:**
- Don't stop navigation entirely
- Show last known position
- Recalculate when signal returns

#### Backend API Error

**Flow:**
```
[API Call Fails]
    ↓ Show error: "Could not load POIs"
    ↓ Offer cached results if available
    ↓ Provide "Retry" button
[User Taps Retry]
    ↓ Show loading state
    ↓ Attempt request again
```

**Recovery:**
- Use cached data as fallback
- Provide manual retry
- Log error for debugging

#### Route Calculation Fails

**Flow:**
```
[Calculation Fails]
    ↓ Show error: "Could not calculate route"
    ↓ Show details if available
    ↓ Offer "Try Again" button
    ↓ Don't leave current screen
[User Retries]
    ↓ Show loading state
    ↓ Attempt calculation again
```

**Recovery:**
- Keep user on current screen
- Provide actionable retry
- Log error details

### Testing Checklist
- [ ] Airplane mode → Shows offline banner
- [ ] No GPS → Shows GPS lost banner
- [ ] Backend down → Shows error with retry
- [ ] Route fails → Offers retry without leaving screen
- [ ] All errors have recovery path
- [ ] Errors don't crash app

---

## Flow Diagram Legend

```
[Screen/State]    - Current UI state
    ↓             - User action or system transition
[Next State]      - Resulting state
    ✅            - Success indicator
    ❌            - Failure/error state
```

---

## Testing Strategy

### For Each Flow

1. **Happy Path Test** - Everything works perfectly
2. **Edge Case Tests** - Unusual but valid scenarios
3. **Error Tests** - Network fails, GPS off, etc.
4. **State Persistence** - App goes to background
5. **Device Tests** - Rotate, low memory, etc.

### Test Checklist Template

```dart
testWidgets('[Flow Name] - [Scenario]', (tester) async {
  // GIVEN: Starting state
  await setupInitialState(tester);

  // WHEN: User performs actions
  await performUserActions(tester);

  // THEN: Expected result
  expect(find.text('Expected'), findsOneWidget);

  // AND: Verify state
  verifyFinalState(tester);
});
```

---

## Version History

- **v1.0** (Jan 23, 2026) - Initial flows
  - Basic navigation flow
  - POI discovery flow (fixed)
  - Multi-stop planning
  - Waypoint management
  - Route recalculation
  - Error recovery
