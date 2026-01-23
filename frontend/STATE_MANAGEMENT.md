# State Management Guide

## Overview

RouteWhisper uses Provider for state management. This provides reactive UI updates without manual callbacks or setState().

## Architecture

### Services as ChangeNotifiers
- **WaypointManager** - Manages waypoint list state
- **NavigationController** - Manages navigation state (idle, calculating, navigating, etc.)

Both extend `ChangeNotifier` and call `notifyListeners()` when state changes.

### Provider Setup

In `main.dart`, we wrap the app with MultiProvider:
```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: NavigationService.waypointManager),
    ChangeNotifierProvider.value(value: NavigationService.controller),
  ],
  child: MaterialApp(...),
)
```

### Using Provider in Widgets

#### Watch (Rebuilds widget on changes)
```dart
@override
Widget build(BuildContext context) {
  // Widget rebuilds when waypoints change
  final waypointManager = context.watch<WaypointManager>();
  final waypoints = waypointManager.getWaypoints();

  return ListView.builder(
    itemCount: waypoints.length,
    itemBuilder: (context, index) => Text(waypoints[index].name),
  );
}
```

#### Read (One-time access, no rebuild)
```dart
void _addWaypoint() {
  // Access without watching (in button callback)
  context.read<WaypointManager>().addWaypoint(newWaypoint);
}
```

#### Consumer (Watch specific widget subtree)
```dart
Consumer<WaypointManager>(
  builder: (context, waypointManager, child) {
    return Text('${waypointManager.getWaypoints().length} waypoints');
  },
)
```

## Testing with Provider

Wrap test widgets with ChangeNotifierProvider:
```dart
testWidgets('Widget displays waypoints', (tester) async {
  final manager = WaypointManager();
  manager.addWaypoint(Waypoint.manual(...));

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: manager,
      child: MaterialApp(home: MyWidget()),
    ),
  );

  expect(find.text('Test Waypoint'), findsOneWidget);
});
```

## Migration Checklist

- [x] Added Provider dependency (pubspec.yaml)
- [x] WaypointManager extends ChangeNotifier
- [x] NavigationController extends ChangeNotifier
- [x] App wrapped with MultiProvider (main.dart)
- [x] WaypointList converted to use Provider
- [x] NavigationDashboard converted to use Provider
- [x] POIDashboard converted to use Provider
- [x] All tests updated (38 tests passing)
- [x] Old callbacks removed
- [x] Documentation complete

## Benefits

1. **Automatic UI updates** - No manual setState() calls
2. **Multiple observers** - Many widgets can watch the same state
3. **Simpler code** - Less boilerplate than callbacks
4. **Better testability** - Easy to provide mock state
5. **Maintainable architecture** - Clear separation between state and UI

## Examples

### Before (Callback Pattern)
```dart
class _DashboardState extends State<Dashboard> {
  List<Waypoint> _waypoints = [];

  @override
  void initState() {
    super.initState();
    NavigationService.waypointManager.onWaypointsChanged = (waypoints) {
      setState(() {
        _waypoints = waypoints;
      });
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _waypoints.length,
      itemBuilder: (context, index) => Text(_waypoints[index].name),
    );
  }
}
```

### After (Provider Pattern)
```dart
class Dashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Automatically rebuilds when waypoints change
    final waypointManager = context.watch<WaypointManager>();
    final waypoints = waypointManager.getWaypoints();

    return ListView.builder(
      itemCount: waypoints.length,
      itemBuilder: (context, index) => Text(waypoints[index].name),
    );
  }
}
```

## Common Patterns

### Watching Multiple Providers
```dart
@override
Widget build(BuildContext context) {
  final navigationController = context.watch<NavigationController>();
  final waypointManager = context.watch<WaypointManager>();

  final currentState = navigationController.currentState;
  final waypoints = waypointManager.getWaypoints();

  // Widget rebuilds when either state changes
  return Column(
    children: [
      Text(currentState.name),
      Text('${waypoints.length} waypoints'),
    ],
  );
}
```

### Conditional Rendering Based on State
```dart
@override
Widget build(BuildContext context) {
  final navigationController = context.watch<NavigationController>();

  if (navigationController.currentState == NavigationState.idle) {
    return Text('Set a route to begin');
  }

  return NavigationActiveView();
}
```

### Updating State
```dart
void _addWaypoint(BuildContext context) {
  // Use read() for one-time access (doesn't cause rebuilds)
  final waypointManager = context.read<WaypointManager>();
  waypointManager.addWaypoint(newWaypoint);

  // Provider automatically notifies all watching widgets
  // No need to call setState() or any callbacks!
}
```

## Performance Tips

1. **Use Selector for fine-grained updates** - Watch only specific fields:
   ```dart
   final waypointCount = context.select<WaypointManager, int>(
     (manager) => manager.getWaypoints().length,
   );
   // Widget only rebuilds when count changes, not when waypoint details change
   ```

2. **Use read() in callbacks** - Don't watch in button handlers:
   ```dart
   ElevatedButton(
     onPressed: () => context.read<WaypointManager>().clearAll(),
     child: Text('Clear All'),
   )
   ```

3. **Use Consumer for subtrees** - Limit rebuild scope:
   ```dart
   Column(
     children: [
       Text('Static header'),
       Consumer<WaypointManager>(
         builder: (context, manager, child) {
           // Only this subtree rebuilds
           return Text('${manager.getWaypoints().length} waypoints');
         },
       ),
     ],
   )
   ```

## Troubleshooting

### Widget not updating?
- Ensure you're using `context.watch()` not `context.read()`
- Verify the service extends `ChangeNotifier`
- Check that `notifyListeners()` is being called

### Too many rebuilds?
- Use `Selector` to watch specific fields
- Use `Consumer` to limit rebuild scope
- Consider using `context.read()` in callbacks

### Tests failing?
- Wrap test widgets with `ChangeNotifierProvider.value()`
- Provide mock services that extend `ChangeNotifier`
- Use `await tester.pump()` after state changes

## Additional Resources

- [Provider Package Documentation](https://pub.dev/packages/provider)
- [Flutter State Management](https://docs.flutter.dev/development/data-and-backend/state-mgmt/simple)
- [Provider Examples](https://github.com/rrousselGit/provider/tree/master/example)
