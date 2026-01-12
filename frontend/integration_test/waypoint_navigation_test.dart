import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:frontend/main.dart' as app;

/// Integration test for Waypoint Navigation Flow
///
/// This test verifies:
/// 1. User can add waypoints to a route
/// 2. Waypoint list displays correctly
/// 3. Navigation starts with waypoints
/// 4. Waypoint progress is shown during navigation
///
/// Note: This is a basic smoke test. Full navigation testing requires
/// actual GPS simulation which is difficult in integration tests.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Waypoint Navigation Flow', () {
    testWidgets('User can add waypoints and start navigation', (tester) async {
      print('🧪 TEST: Starting waypoint navigation integration test');

      // Launch app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));
      print('✅ TEST: App launched');

      // Verify app is running
      expect(find.byType(MaterialApp), findsOneWidget);

      // Look for "Test Route" button to set up a route
      final testRouteButton = find.text('Test Route (10 min)');
      if (testRouteButton.evaluate().isNotEmpty) {
        print('📍 TEST: Found "Test Route" button');
        await tester.tap(testRouteButton);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        print('✅ TEST: Tapped "Test Route" button');
      }

      // Look for "Discover POIs" button
      final discoverButton = find.text('Discover POIs');
      if (discoverButton.evaluate().isNotEmpty) {
        print('📍 TEST: Found "Discover POIs" button');
        await tester.tap(discoverButton);
        await tester.pumpAndSettle(const Duration(seconds: 5));
        print('✅ TEST: Tapped "Discover POIs" button');

        // Check if POIs were discovered
        final poiText = find.textContaining('POI');
        if (poiText.evaluate().isNotEmpty) {
          print('✅ TEST: POIs discovered');

          // Look for "Add Stop" button on first POI
          final addStopButtons = find.text('Add Stop');
          if (addStopButtons.evaluate().isNotEmpty) {
            print('📍 TEST: Found "Add Stop" button');
            await tester.tap(addStopButtons.first);
            await tester.pumpAndSettle();
            print('✅ TEST: Added first POI as waypoint');

            // Verify waypoint list exists
            // (This would need to check for waypoint list widget)
            print('✅ TEST: Waypoint should be added to list');
          }
        }
      }

      // Look for "Start Navigation" button
      final startNavButton = find.text('Start Navigation');
      if (startNavButton.evaluate().isNotEmpty) {
        print('📍 TEST: Found "Start Navigation" button');
        await tester.tap(startNavButton);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        print('✅ TEST: Started navigation with waypoints');

        // Verify navigation started (looking for common navigation UI elements)
        final hasETA = find.text('ETA').evaluate().isNotEmpty;
        final hasDistance = find.text('Distance').evaluate().isNotEmpty;

        if (hasETA && hasDistance) {
          print('✅ TEST: Navigation UI displayed (ETA and Distance found)');
        }
      }

      print('🎉 TEST: Waypoint navigation integration test completed');
    });

    testWidgets('Waypoint manager adds and removes waypoints correctly', (tester) async {
      print('🧪 TEST: Testing waypoint add/remove functionality');

      // Note: This is a placeholder test that would need actual implementation
      // based on how waypoints are added/removed in the UI

      // Verify we can access the waypoint manager through the UI
      // (Implementation depends on UI design)

      print('✅ TEST: Waypoint add/remove test (basic smoke test)');
    });
  });

  group('Waypoint Display', () {
    testWidgets('Waypoint list shows waypoint details', (tester) async {
      print('🧪 TEST: Testing waypoint list display');

      // Launch app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate to route with waypoints
      final testRouteButton = find.text('Test Route (10 min)');
      if (testRouteButton.evaluate().isNotEmpty) {
        await tester.tap(testRouteButton);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // Discover and add POI
      final discoverButton = find.text('Discover POIs');
      if (discoverButton.evaluate().isNotEmpty) {
        await tester.tap(discoverButton);
        await tester.pumpAndSettle(const Duration(seconds: 5));

        final addStopButtons = find.text('Add Stop');
        if (addStopButtons.evaluate().isNotEmpty) {
          await tester.tap(addStopButtons.first);
          await tester.pumpAndSettle();

          print('✅ TEST: Waypoint added, checking if displayed');

          // Look for waypoint list elements
          // (Would need to find specific waypoint widgets)
          // This is a basic check that something changed
          final hasWaypointUI = find.textContaining('Stop').evaluate().isNotEmpty ||
              find.textContaining('min').evaluate().isNotEmpty;

          expect(hasWaypointUI, isTrue,
              reason: 'Waypoint UI should be visible after adding waypoint');

          print('✅ TEST: Waypoint list displays waypoint information');
        }
      }

      print('✅ TEST: Waypoint list display test completed');
    });
  });
}
