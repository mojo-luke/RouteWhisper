# Design Checklist

**Purpose:** Quick reference checklist to use BEFORE implementing any feature.

**How to use:** Copy this checklist into your feature planning doc or commit message. Check off each item before writing code.

---

## Pre-Implementation Checklist

### 1. User Flow Documentation

- [ ] Written user story: "As a [user], I want to [action] so that [benefit]"
- [ ] Documented happy path flow (see USER_FLOWS.md)
- [ ] Identified edge cases (at least 3)
- [ ] Documented error scenarios
- [ ] Verified flow doesn't violate UX principles

### 2. Navigation Context (Critical!)

- [ ] Does this feature run during active navigation?
  - If YES → Continue to next question
  - If NO → Skip to section 3

- [ ] Does this require leaving MapActivity?
  - If YES → **STOP!** Redesign as overlay/modal
  - If NO → ✅ Continue

- [ ] Will MapActivity need to update in-place?
  - If YES → Plan method channel for updates
  - If NO → Verify it's truly read-only

- [ ] Does this change the route?
  - If YES → Plan for seamless recalculation
  - If NO → Verify no route impact

### 3. User Friction Analysis

- [ ] How many taps required? (Target: 1-2 for common actions)
  - 1 tap: ✅ Excellent
  - 2 taps: ✅ Good
  - 3 taps: ⚠️ Consider simplifying
  - 4+ taps: ❌ Too much friction

- [ ] Are there any "hidden" steps?
  - Example: User adds stop → Must tap "Recalculate"
  - If YES → **Automate the hidden step**

- [ ] Is there immediate visual feedback (< 100ms)?
  - If NO → Plan loading states

- [ ] Does every action have a clear result?
  - If NO → Add success/error messaging

### 4. State Management

- [ ] Which Provider manages this state?
  - NavigationController?
  - WaypointManager?
  - New Provider needed?

- [ ] Does state need to persist across app restarts?
  - If YES → Plan SharedPreferences or database

- [ ] What happens if the app goes to background?
  - State preserved?
  - Operation continues?
  - Needs to resume on return?

- [ ] What happens if user rotates device?
  - State preserved?
  - UI adapts gracefully?

### 5. Error Handling

- [ ] What if network fails?
  - Planned fallback behavior?
  - User sees helpful message?
  - Can retry?

- [ ] What if GPS is off/lost?
  - Feature gracefully degraded?
  - User notified?

- [ ] What if backend API fails?
  - Cached data available?
  - Retry option provided?
  - User not stuck?

- [ ] What if user has no active route?
  - Feature disabled/hidden?
  - Helpful message shown?

- [ ] What if concurrent operations conflict?
  - Example: User adds 3 POIs rapidly
  - Handled gracefully?
  - No race conditions?

### 6. Undo Support

- [ ] Is this action destructive or state-changing?
  - If YES → Continue
  - If NO → Skip to section 7

- [ ] Does this action have an undo option?
  - ✅ YES → Good!
  - ❌ NO → **Add undo snackbar (5 seconds)**

- [ ] What's the undo window? (Target: 5 seconds)

- [ ] What happens if user leaves screen before undo expires?
  - Undo still available?
  - Action committed?

- [ ] Can undo be performed multiple times?
  - Single undo?
  - Full undo stack?

### 7. Safety (Driving Context)

- [ ] All tap targets ≥ 48x48dp?
  - Measure in design tool or code

- [ ] Text readable at a glance?
  - Font size ≥ 16sp for body text
  - High contrast ratio (4.5:1 minimum)

- [ ] No multi-step flows requiring prolonged focus?
  - Example: Filling out a form while driving
  - If YES → **Redesign or block while moving**

- [ ] Critical actions have voice confirmation?
  - "Stop added to your route"
  - "Navigation canceled"

- [ ] Works with one hand?
  - All controls reachable with thumb
  - No two-handed gestures required

### 8. Performance

- [ ] UI responds within 100ms?
  - Tap → Immediate feedback
  - Even if operation takes longer

- [ ] Animations run at 60fps?
  - No jank or stuttering
  - Smooth transitions

- [ ] Route calculation perceived as fast?
  - Shows progress immediately
  - Uses cached route if available
  - Target: < 500ms perceived

- [ ] POI discovery fast enough?
  - Shows cached results immediately
  - Fresh results within 2 seconds

- [ ] Image loading doesn't block UI?
  - Lazy loading
  - Progressive loading
  - Placeholder while loading

### 9. Testing Strategy

- [ ] Integration test written? (Write BEFORE implementing!)
  - Tests happy path
  - Tests at least 1 edge case
  - Verifies no unwanted side effects

- [ ] Unit tests for business logic?
  - All calculation logic tested
  - Edge cases covered
  - Error handling tested

- [ ] Manual test plan defined?
  - Device model to test on
  - Network conditions to test
  - GPS scenarios to test

- [ ] Accessibility tested?
  - Screen reader compatible
  - Sufficient color contrast
  - Works without sound

### 10. Documentation

- [ ] User flow documented in USER_FLOWS.md?
  - Or reference to existing flow

- [ ] API/method signatures documented?
  - Clear docstrings
  - Parameter types and meanings
  - Return value explained

- [ ] State changes documented?
  - Which Provider notifies
  - When listeners are called
  - Side effects explained

---

## Code Review Checklist

Use this during PR review or before committing:

### Architecture

- [ ] Follows Clean Architecture (Flutter logic, Android UI only)?
- [ ] State management uses Provider correctly?
- [ ] No business logic in Android/iOS code?
- [ ] Method channels used only for UI coordination?

### Code Quality

- [ ] Follows Dart/Kotlin style guide?
- [ ] No magic numbers (use named constants)?
- [ ] Error handling comprehensive?
- [ ] Logging added for debugging?
- [ ] TODOs have context and owner?

### Testing

- [ ] Integration test passes?
- [ ] Unit tests pass?
- [ ] Manually tested on real device?
- [ ] Tested with slow network?
- [ ] Tested with no network?
- [ ] Tested with GPS off?

### UX Compliance

- [ ] Doesn't violate "Never Leave Navigation" rule?
- [ ] Provides immediate feedback?
- [ ] Has undo option if needed?
- [ ] Error messages are helpful?
- [ ] Loading states prevent double-tap?

### Performance

- [ ] No obvious performance issues?
- [ ] Images optimized?
- [ ] No memory leaks?
- [ ] Animations smooth?

---

## Quick Reference: Common Violations

### ❌ BAD: Launches new activity during navigation
```kotlin
startActivity(Intent(this, POIActivity::class.java))
```

### ✅ GOOD: Shows overlay
```dart
showModalBottomSheet(context: context, builder: (_) => POIDashboard())
```

---

### ❌ BAD: No visual feedback
```dart
ElevatedButton(
  onPressed: () async {
    await longOperation(); // User sees nothing
  },
  child: Text('Submit'),
)
```

### ✅ GOOD: Immediate feedback
```dart
bool _loading = false;

ElevatedButton(
  onPressed: _loading ? null : () async {
    setState(() => _loading = true);
    await longOperation();
    setState(() => _loading = false);
  },
  child: _loading ? CircularProgressIndicator() : Text('Submit'),
)
```

---

### ❌ BAD: No undo option
```dart
void deleteWaypoint(Waypoint wp) {
  waypointManager.remove(wp);
  // No way to undo!
}
```

### ✅ GOOD: Undo snackbar
```dart
void deleteWaypoint(Waypoint wp) {
  waypointManager.remove(wp);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('${wp.name} removed'),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () => waypointManager.add(wp),
      ),
      duration: Duration(seconds: 5),
    ),
  );
}
```

---

### ❌ BAD: Multiple API calls
```kotlin
// In MainActivity - launches new MapActivity every time
handleCalculateRoute() {
  startActivity(Intent(this, MapActivity::class.java))
}
```

### ✅ GOOD: Update existing activity
```kotlin
// Send update to existing MapActivity
MainActivity.methodChannelInstance?.invokeMethod(
  "updateNavigationRoute",
  routeData
)
```

---

## Post-Implementation Review

After implementing, go through this checklist:

### Functionality
- [ ] Feature works as documented in user flow?
- [ ] All edge cases handled?
- [ ] Error scenarios handled?

### UX
- [ ] Feels natural and intuitive?
- [ ] No unexpected behavior?
- [ ] Feedback is immediate and clear?
- [ ] Undo works if applicable?

### Testing
- [ ] Integration test passes?
- [ ] Unit tests pass?
- [ ] Manually tested on real device?
- [ ] Tested all edge cases?

### Performance
- [ ] No lag or jank?
- [ ] Animations smooth?
- [ ] Memory usage reasonable?

### Documentation
- [ ] Code comments added where needed?
- [ ] USER_FLOWS.md updated if needed?
- [ ] Commit message follows convention?

---

## Commit Message Template

```
feat(Area): Brief description of what this does

**User Story:**
As a [user], I want to [action] so that [benefit].

**Implementation:**
- Key change 1
- Key change 2
- Key change 3

**UX Compliance:**
- ✅ Doesn't leave navigation context
- ✅ Immediate visual feedback
- ✅ Undo option provided
- ✅ Error handling complete

**Testing:**
- ✅ Integration test added/updated
- ✅ Unit tests pass
- ✅ Manually tested on device

**Edge Cases Handled:**
- Network failure → [behavior]
- GPS off → [behavior]
- Concurrent actions → [behavior]

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

---

## Version History

- **v1.0** (Jan 23, 2026) - Initial checklist
  - 10-point pre-implementation checklist
  - Code review checklist
  - Common violations reference
  - Post-implementation review
