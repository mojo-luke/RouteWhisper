# UX rules

The rules below have led to real bugs when ignored. They're a short list, not a checklist ritual — internalize them, apply judgment.

## 1. Never leave MapActivity during active navigation

Launching a new activity on top of MapActivity has, in the past, killed the navigation session. During active nav, use overlays:

- `showModalBottomSheet` for Flutter modals reachable from a Flutter context
- `TransparentFlutterActivity` (with the shared FlutterEngine) for overlays triggered from MapActivity

Both let the overlay see live Provider state.

```dart
// Wrong — destroys nav context
Navigator.push(context, MaterialPageRoute(builder: (_) => POIScreen()));

// Right — overlay over the live map
showModalBottomSheet(context: context, builder: (_) => POIDashboard());
```

## 2. Visible reaction within 100ms of every tap

Long operations get a spinner immediately. Buttons disable on press to prevent double-tap. The user should never wonder if a tap registered.

```dart
bool _loading = false;
ElevatedButton(
  onPressed: _loading ? null : () async {
    setState(() => _loading = true);
    try { await op(); }
    finally { if (mounted) setState(() => _loading = false); }
  },
  child: _loading ? const CircularProgressIndicator() : const Text('Submit'),
);
```

## 3. One action = final result, no follow-up step

Adding a waypoint should automatically trigger route recalculation. The user shouldn't have to tap "Recalculate" afterward. If a flow needs more than one tap to commit, automate the rest.

## 4. 5-second undo SnackBar for destructive/state-changing actions

Adding, removing, or skipping a waypoint:

```dart
ScaffoldMessenger.of(context).showSnackBar(SnackBar(
  content: Text('${wp.name} removed'),
  action: SnackBarAction(label: 'UNDO', onPressed: () => waypointManager.add(wp)),
  duration: const Duration(seconds: 5),
));
```

## 5. Driving context

- Tap targets ≥ 48×48dp
- Body text ≥ 16sp, ≥ 4.5:1 contrast
- No multi-step flows that need sustained focus
- One-handed thumb reach for primary actions

## State management (Provider)

`WaypointManager` and `NavigationController` extend `ChangeNotifier`. UI watches them via `context.watch<T>()` and rebuilds automatically; callbacks use `context.read<T>()` to avoid unnecessary subscriptions. The `MultiProvider` is set up in `frontend/lib/main.dart`.

In tests, wrap the widget under test:

```dart
await tester.pumpWidget(
  ChangeNotifierProvider.value(
    value: waypointManager,
    child: const MaterialApp(home: MyWidget()),
  ),
);
```
