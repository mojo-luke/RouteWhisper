import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:frontend/main.dart' as app;
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/services/navigation_service.dart';
import 'package:frontend/services/poi_api_service.dart' show POI;
import 'package:frontend/widgets/poi_suggestion_card.dart';

/// Integration test for the pre-navigation waypoint flow: discover POIs
/// along a route, add one as a waypoint, verify it shows up on the
/// dashboard, then remove it via the "Manage Waypoints" dialog.
///
/// Preconditions:
///   - Backend running (`docker-compose up -d` in backend/) — this test
///     hits the real POI-discovery endpoint, no mocking.
///   - Fixture test account exists: `python backend/scripts/manage_test_user.py create`
///
/// Auth: signs in via AuthService.signInForTesting() rather than tapping
/// through Google OAuth — see docs/auth-setup.md. Without this, the app
/// never gets past the sign-in screen and every step below silently
/// fails to find anything, which is why this test used to be full of
/// `if (button exists)` guards instead of real assertions.
///
/// Route seam: seeds NavigationService.setRoutePolyline(...) directly
/// with a hand-encoded real SF polyline (Embarcadero -> Fisherman's
/// Wharf — the same corridor _startSampleNavigation() uses, chosen
/// because it's POI-dense) instead of driving RouteInputDialog.
/// RouteInputDialog ignores whatever you type in its fields and always
/// calls startNavigation() with hardcoded SF->LA coordinates (real,
/// live navigation) — there's no "route calculated but not navigating"
/// state reachable through that dialog. This is the same seam
/// frontend/test/services/recommendation_service_test.dart already uses.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final testPolyline = _encodePolyline(const [
    [37.7955, -122.3937], // Embarcadero Center
    [37.8080, -122.4177], // Fisherman's Wharf
  ]);

  testWidgets(
    'Discover POIs, add one as a waypoint, then remove it',
    (tester) async {
      final firstPoi = await _discoverAndAddFirstWaypoint(tester, testPolyline);
      // Let the add-waypoint snackbar clear before opening a dialog.
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // _addPOIAsWaypoint pops POIDashboard back to the dashboard once
      // the waypoint is added.
      expect(
        find.text('Discover POIs'),
        findsNothing,
        reason: 'Once a waypoint exists, the button switches to '
            '"View POIs (...)"',
      );
      expect(
        find.text(firstPoi.name),
        findsOneWidget,
        reason: 'The added waypoint should appear in the compact list on '
            'the dashboard, not just in a transient snackbar',
      );

      // Remove it via the "Manage Waypoints" dialog.
      await tester.tap(find.byTooltip('Manage Waypoints'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      // Removing re-opens a fresh "Manage Waypoints" dialog (now empty)
      // rather than closing it — close it to get back to the dashboard.
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(
        find.text(firstPoi.name),
        findsNothing,
        reason: 'Removing the waypoint should clear it from the compact list',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'Undo on the add-waypoint snackbar removes it immediately',
    (tester) async {
      final firstPoi = await _discoverAndAddFirstWaypoint(tester, testPolyline);

      // The "Waypoint Added" snackbar (poi_dashboard.dart _addPOIAsWaypoint)
      // only stays up for 3 seconds — act on it right away rather than
      // pumpAndSettle-ing for long enough that it could auto-dismiss.
      expect(
        find.text('Undo'),
        findsOneWidget,
        reason: 'Adding a waypoint should show an undo-able snackbar, per '
            'the 5-second-undo rule in CLAUDE.md',
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(
        find.text(firstPoi.name),
        findsNothing,
        reason: 'Tapping Undo should remove the waypoint immediately',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// Launches the app, signs in, seeds [polyline], discovers real POIs
/// along it, and adds the first result as a waypoint. Returns that POI
/// so the caller can assert on its name. Leaves the snackbar from
/// _addPOIAsWaypoint still visible — callers that don't need it should
/// let it run out (3s) or dismiss it before doing anything else that
/// might conflict with a pending SnackBar.
Future<POI> _discoverAndAddFirstWaypoint(
  WidgetTester tester,
  String polyline,
) async {
  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 3));

  // NavigationService/WaypointManager are static/singleton — their state
  // persists across testWidgets blocks in this same process even though
  // app.main() runs again, so a prior test's discovery response would
  // otherwise leave "Discover POIs" reading "View POIs (...)" here.
  NavigationService.clearPOIs();
  NavigationService.waypointManager.clearIntermediateWaypoints();

  await AuthService.instance.signInForTesting();
  // Seed the polyline BEFORE the dashboard's first build. NavigationService
  // isn't a ChangeNotifier — setting this after the dashboard has already
  // built wouldn't trigger a rebuild, so the button would stay hidden
  // until something unrelated happened to rebuild the tree.
  NavigationService.setRoutePolyline(polyline);
  await tester.pumpAndSettle(const Duration(seconds: 3));

  expect(
    find.text('Discover POIs'),
    findsOneWidget,
    reason: 'hasPolyline should be true from the seeded route',
  );

  await tester.tap(find.text('Discover POIs'));
  await tester.pump(); // start the Navigator.push transition
  await tester.pump(const Duration(seconds: 1));

  // POIDashboard shows an indeterminate CircularProgressIndicator while
  // its real backend call is in flight — pumpAndSettle() never returns
  // during that (the spinner's AnimationController keeps scheduling
  // frames), so poll instead.
  var found = false;
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (find.byType(POISuggestionCard).evaluate().isNotEmpty) {
      found = true;
      break;
    }
  }
  expect(
    found,
    isTrue,
    reason: "Real POI discovery against the Embarcadero->Fisherman's Wharf "
        'corridor should return at least one result within 10s. If this '
        'fails, check the backend is running (docker-compose up -d) and '
        'that manage_test_user.py create has been run.',
  );

  final firstPoi =
      tester.widget<POISuggestionCard>(find.byType(POISuggestionCard).first).poi;

  await tester.tap(find.text('Add as Waypoint').first);
  // Deliberately not pumpAndSettle here — the snackbar this triggers has
  // a 3s auto-dismiss, and callers that want to interact with it (the
  // Undo test) need it still on screen.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  return firstPoi;
}

/// Minimal Google/Mapbox polyline encoder (precision 6, matching what
/// backend/app/utils/polyline.py's decode_polyline expects by default —
/// Mapbox's Navigation SDK uses precision 6, NOT the Google-Maps-standard
/// precision 5). [points] are [lat, lng] pairs.
String _encodePolyline(List<List<double>> points) {
  const factor = 1000000;
  final buffer = StringBuffer();
  var prevLat = 0;
  var prevLng = 0;
  for (final point in points) {
    final lat = (point[0] * factor).round();
    final lng = (point[1] * factor).round();
    _encodeSignedNumber(lat - prevLat, buffer);
    _encodeSignedNumber(lng - prevLng, buffer);
    prevLat = lat;
    prevLng = lng;
  }
  return buffer.toString();
}

void _encodeSignedNumber(int number, StringBuffer buffer) {
  var shifted = number << 1;
  if (number < 0) {
    shifted = ~shifted;
  }
  while (shifted >= 0x20) {
    buffer.writeCharCode((0x20 | (shifted & 0x1f)) + 63);
    shifted >>= 5;
  }
  buffer.writeCharCode(shifted + 63);
}
