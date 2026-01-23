# RouteWhisper UX Principles

**Last Updated:** January 23, 2026
**Purpose:** Design guidelines to ensure RouteWhisper provides a better experience than Google Maps

---

## Core Philosophy

**"Better than Google Maps" means:**
- More intuitive POI discovery
- Seamless multi-stop routing
- Context-aware narration
- Zero friction in common tasks

---

## Golden Rules

### 1. Never Leave Navigation

**Rule:** If the user is actively navigating, NEVER exit MapActivity unless they explicitly cancel.

**Why:** Context switching destroys the navigation experience. Users should feel like they're in one continuous session.

**Implementation:**
- All interactions during navigation = overlays, bottom sheets, or in-place updates
- Adding stops → Update route in MapActivity (don't launch new activity)
- Viewing POIs → Show as modal overlay on top of map
- Adjusting settings → Bottom sheet or dialog
- Only exit navigation when user taps "Cancel Navigation"

**Bad Example:**
```dart
// ❌ Launches new activity, loses navigation context
Navigator.push(context, MaterialPageRoute(builder: (_) => POIScreen()));
```

**Good Example:**
```dart
// ✅ Shows modal overlay, stays in navigation
showModalBottomSheet(context: context, builder: (_) => POIDashboard());
```

### 2. Immediate Visual Feedback

**Rule:** Every user interaction gets instant visual feedback (< 100ms).

**Why:** Users should never wonder "did that work?"

**Implementation:**
- Button press → Ripple effect + slight scale
- Loading state → Spinner or skeleton
- Success → Checkmark animation + haptic
- Error → Shake animation + error icon

**Examples:**
- Tap "Add Stop" → Button shows loading spinner
- Route calculating → Progress bar or shimmer
- POI added → Green checkmark + snackbar
- API error → Red icon + error message

### 3. One Action = One Result (No Hidden Steps)

**Rule:** When user takes an action, the result should be immediate and complete. No "now do step 2" flows.

**Why:** Friction kills UX. Users shouldn't have to "recalculate" after adding a stop.

**Bad Flow:**
```
Add POI → Snackbar "Added" → User must tap "Recalculate Route" → Navigate
```

**Good Flow:**
```
Add POI → Route auto-updates → Continue navigating
```

**Implementation:**
- Adding waypoint → Route recalculates automatically
- Removing waypoint → Route updates immediately
- Changing route → MapActivity updates in-place

### 4. Undo Everything

**Rule:** Every destructive or state-changing action must be undoable for 5 seconds.

**Why:** Users make mistakes. Undo removes fear of experimenting.

**Implementation:**
```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Shell Gas Station added to route'),
    action: SnackBarAction(
      label: 'UNDO',
      onPressed: () => undoAddWaypoint(waypoint),
    ),
    duration: Duration(seconds: 5),
  ),
);
```

**Applies to:**
- Adding waypoint → Show undo button
- Removing waypoint → Show undo button
- Skipping waypoint → Show undo button
- Changing route → Show undo button

### 5. Safety First (Driving Mode)

**Rule:** All UX decisions must assume the user might be driving.

**Why:** This is a navigation app. Distracted driving kills people.

**Implementation:**
- Large tap targets (min 48x48dp)
- High contrast text
- No multi-step flows requiring focus
- Voice confirmations for critical actions
- "While driving" mode reduces UI complexity

**Examples:**
- POI cards → Large, easy to tap
- "Add Stop" button → Big, obvious
- No tiny checkboxes or radio buttons
- Critical actions → Voice confirmation

### 6. Respect User Context

**Rule:** Remember user state and preferences across sessions.

**Why:** Users shouldn't reconfigure things every time.

**Implementation:**
- Last used filters (restaurants, gas, etc.)
- Preferred routes (avoid tolls, highways)
- Recent searches
- Favorite stops
- Don't ask twice for the same permission

---

## Design Patterns

### Overlays During Navigation

**When to use:** Temporary interactions that don't change navigation state

**Pattern:**
```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => DraggableScrollableSheet(
    initialChildSize: 0.9,
    minChildSize: 0.5,
    maxChildSize: 0.95,
    builder: (context, scrollController) => YourWidget(),
  ),
);
```

**Examples:**
- POI discovery
- Waypoint list
- Route options
- Settings

### In-Place Updates

**When to use:** Changes that affect the current navigation route

**Pattern:**
- Update data in shared state (Provider)
- Send update command to MapActivity via method channel
- MapActivity recalculates route without restarting
- UI updates reactively via Provider listeners

**Examples:**
- Adding/removing waypoints
- Reordering stops
- Changing route preferences

### Snackbar Feedback

**Pattern:**
```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Row(
      children: [
        Icon(Icons.check_circle, color: Colors.white),
        SizedBox(width: 12),
        Text('Action completed'),
      ],
    ),
    action: SnackBarAction(label: 'UNDO', onPressed: () {}),
    behavior: SnackBarBehavior.floating,
    duration: Duration(seconds: 5),
  ),
);
```

**Use for:**
- Success messages
- Undo opportunities
- Non-critical errors
- Quick info

---

## State Management Rules

### Provider Pattern

**Rule:** All shared state uses Provider. No global variables except constants.

**Structure:**
```
NavigationController (Provider)
  ↓ provides navigation state
  ↓ notifies UI of changes
  ↓
Widgets (Consumer/watch)
  ↓ automatically rebuild
  ↓ no manual setState
```

**Benefits:**
- UI automatically updates
- No callback hell
- Easy to test
- Clear data flow

### State Persistence

**Rule:** Navigation state survives activity lifecycle.

**Implementation:**
- Critical state → Shared preferences or database
- Transient state → Provider (memory)
- Navigation route → Saved to disk
- Waypoints → Persisted

---

## Performance Guidelines

### Rule: Smooth = 60fps

**Targets:**
- Animations → 60fps (16ms per frame)
- Route calculation → < 500ms perceived (show progress immediately)
- POI discovery → < 2s (show cached results if available)
- Waypoint updates → < 100ms (optimistic UI update)

### Optimization Strategies

1. **Lazy Loading**
   - Load POI details on tap, not on list render
   - Images load progressively

2. **Caching**
   - Cache POI results (1 hour)
   - Cache route calculations (same origin/dest)
   - Cache map tiles

3. **Optimistic UI**
   - Update UI immediately
   - Revert if server fails
   - Show undo option

---

## Testing Requirements

### Every Feature Needs

1. **Integration Test** - Tests the actual user flow
2. **Unit Tests** - Tests business logic
3. **Manual Test** - Developer uses feature on real device
4. **UX Review** - Does it pass the golden rules?

### Integration Test Pattern

```dart
testWidgets('Feature name describes user goal', (tester) async {
  // GIVEN: User is in state X
  await setupState(tester);

  // WHEN: User performs action Y
  await tester.tap(find.text('Button'));
  await tester.pumpAndSettle();

  // THEN: Result Z happens
  expect(find.text('Expected Result'), findsOneWidget);

  // AND: User is still in correct context
  expect(find.byType(MapActivity), findsOneWidget);
});
```

---

## Decision Framework

### Before Implementing Any Feature, Ask:

#### 1. Navigation Context
- [ ] Does this require leaving MapActivity?
  - If YES → Can we do it as an overlay instead?

#### 2. User Friction
- [ ] How many taps does this require?
  - Target: 1-2 taps for common actions
- [ ] Are there any "hidden" steps?
  - If YES → Can we automate them?

#### 3. State Management
- [ ] Does state persist correctly?
- [ ] What happens if user rotates device?
- [ ] What happens if app goes to background?

#### 4. Error Handling
- [ ] What if network fails?
- [ ] What if GPS is off?
- [ ] What if user has no route?
- [ ] Does user get actionable feedback?

#### 5. Safety
- [ ] Can this be done while driving safely?
- [ ] Are tap targets large enough (48x48dp)?
- [ ] Is text readable at a glance?

#### 6. Testing
- [ ] Can this be integration tested?
- [ ] What are the edge cases?
- [ ] Have we tested on a real device?

---

## Common Anti-Patterns to Avoid

### ❌ Multiple Activities for Related Tasks
```kotlin
// BAD: Launches new activity, loses context
startActivity(Intent(this, POIActivity::class.java))
```

### ❌ Manual Recalculation Required
```dart
// BAD: User has to tap "Recalculate"
addWaypoint(poi);
showSnackbar('Tap Recalculate to update route');
```

### ❌ No Undo Option
```dart
// BAD: Permanent action with no way to undo
deleteWaypoint(waypoint);
```

### ❌ Silent Failures
```dart
// BAD: Fails silently
try {
  await api.addPOI(poi);
} catch (e) {
  // Nothing shown to user
}
```

### ❌ Blocking UI for Long Operations
```dart
// BAD: UI freezes
final result = await longRunningOperation(); // No loading state
```

---

## Competitive Benchmarks

### Google Maps Comparison

| Feature | Google Maps | RouteWhisper Target |
|---------|-------------|---------------------|
| Add stop during nav | 3 taps | 2 taps |
| POI discovery | Search required | Auto-discover along route |
| Multi-stop routing | Manual entry | Intelligent suggestions |
| Route recalculation | Automatic | Automatic + undo |
| Context switching | Stays in nav | Stays in nav |

### Key Differentiators

**Where we're better:**
- ✅ Proactive POI suggestions (don't need to search)
- ✅ Context-aware narration (not just turn-by-turn)
- ✅ Multi-stop optimization (Google does this poorly)
- ✅ Undo on every action

**Where we match:**
- ✅ No context switching during navigation
- ✅ Automatic route recalculation
- ✅ Smooth animations

---

## Resources

### Reading
- **Material Design Guidelines** - https://m3.material.io/
- **Apple HIG** - https://developer.apple.com/design/human-interface-guidelines/
- **Google Maps UX Patterns** - Use Google Maps, note what works

### Testing
- **Integration Tests** - `frontend/integration_test/`
- **Manual Testing Checklist** - See DESIGN_CHECKLIST.md

### Examples
- **Good UX**: Google Maps, Waze, Apple Maps
- **Bad UX**: Apps that force you back to home screen during tasks

---

## Version History

- **v1.0** (Jan 23, 2026) - Initial principles
  - Golden rules defined
  - Design patterns documented
  - Decision framework created
