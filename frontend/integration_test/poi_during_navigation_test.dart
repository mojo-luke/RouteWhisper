import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:frontend/main.dart' as app;
import 'package:frontend/services/auth_service.dart';

/// Integration test for the "never leave MapActivity" requirement around
/// POI discovery during active navigation.
///
/// What this test CAN verify from Flutter's integration_test: launching
/// real navigation via "Test Route (10 min)" leaves the Flutter dashboard
/// (MainActivity's widget tree) and doesn't come back to it.
///
/// What it CANNOT verify, and why: adding a POI during active navigation
/// happens through a native FAB inside MapActivity ("Find Stops") that
/// opens TransparentFlutterActivity as a separate native Activity via a
/// method channel call — neither the native FAB nor that overlay's
/// contents are part of the widget tree `WidgetTester` is bound to here.
/// Driving that would need Android UI Automator/Espresso, not Flutter's
/// integration_test. That logic IS covered elsewhere:
///   - MainActivityTest.kt / MainActivityNarrationTest.kt (Kotlin,
///     frontend/android/app/src/test/kotlin/...): handleShowPoisOnMap,
///     handleUpdateNavigationRoute, and the narration/marker handlers —
///     verifies MainActivity dispatches these method-channel calls
///     correctly.
///   - WaypointArrivalTrackerTest.kt: the arrival/departure state machine
///     that keeps running during active navigation.
///
/// Preconditions: same as waypoint_navigation_test.dart — backend up,
/// fixture test account created (backend/scripts/manage_test_user.py).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Starting navigation leaves the dashboard and does not return to it',
    (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await AuthService.instance.signInForTesting();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('Plan New Route'), findsOneWidget,
          reason: 'Should be on the dashboard after signing in');

      await tester.tap(find.text('Test Route (10 min)'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(
        find.text('Plan New Route'),
        findsNothing,
        reason: 'startNavigation() launches native MapActivity — the '
            "dashboard's Flutter widgets shouldn't be showing anymore",
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
