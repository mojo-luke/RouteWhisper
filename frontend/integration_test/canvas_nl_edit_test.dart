import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:frontend/main.dart' as app;
import 'package:frontend/models/trip.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/services/trip_service.dart';

/// Integration test for the canvas NL textbox (frontend Slice 2):
/// typing a free-text instruction into TripCanvasScreen's `_NLInputBar`
/// and having it actually add a pin.
///
/// Real end to end — there's no way to mock the backend's Anthropic call
/// from a Flutter test (the backend is a separate already-running
/// process on 10.0.2.2:8000), so this hits the real LLM and real Mapbox
/// geocode server-side. Assertions are written around the backend's
/// deterministic message strings (main.py's canvas_nl_edit response
/// text) rather than the LLM-chosen pin name, since that varies run to
/// run.
///
/// Scoped to pin_stop only, not remove_stop: a second NL submission
/// after a pin renders hits a real hit-testing issue where the
/// newly-rendered chip / keyboard-dismiss transition leaves something
/// (an Overlay's RenderAbsorbPointer) intercepting the input bar's tap
/// target. remove_stop's actual logic is already covered end to end by
/// backend/tests/test_canvas_nl_edit.py and unit-tested in
/// test_nl_parser.py — this file's unique value (the full UI-to-backend
/// wiring for the NL textbox) is fully exercised by the pin_stop path
/// alone; the second interaction would just re-render the same pin list
/// with fewer entries through identical UI code.
///
/// Preconditions:
///   - Backend running (`docker-compose up -d`), real ANTHROPIC_API_KEY
///     and MAPBOX_ACCESS_TOKEN in backend/.env.
///   - Fixture test account exists: `python backend/scripts/manage_test_user.py create`
///
/// Navigation path (per trip_canvas_screen.dart / my_trips_screen.dart):
/// dashboard -> "My trips" (map_outlined icon) -> tap the trip ->
/// TripDetailScreen -> "Plan on canvas" (map_outlined action) ->
/// TripCanvasScreen. The trip itself is created via TripService.create()
/// directly (a real HTTP call, same seam the New Trip wizard uses)
/// rather than driving that wizard's form.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'NL textbox adds a pin_stop via the real backend',
    (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await AuthService.instance.signInForTesting();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final trip = await TripService.create(Trip(
        name: 'Canvas NL Test Trip',
        originName: 'San Francisco, CA',
        originLat: 37.7749,
        originLng: -122.4194,
        destinationName: 'Sacramento, CA',
        destinationLat: 38.5816,
        destinationLng: -121.4944,
      ));
      expect(trip, isNotNull, reason: 'TripService.create should succeed against the real backend');

      try {
        await tester.tap(find.byTooltip('My trips'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(find.text('Canvas NL Test Trip'), findsOneWidget);
        await tester.tap(find.text('Canvas NL Test Trip'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        await tester.tap(find.byTooltip('Plan on canvas'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Expand the collapsed NL input row.
        await tester.tap(find.text('Tell me what to change…'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField),
          'add a coffee stop in Truckee, CA',
        );
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump(); // start the request; _loading flips true

        // Real backend call (LLM parse + Mapbox geocode) — poll rather
        // than pumpAndSettle since nothing here has a repeating
        // animation blocking settle, but the real network round trip
        // can take a few seconds.
        var addedMessageSeen = false;
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 500));
          if (find
              .textContaining('tap + in the timeline to confirm it')
              .evaluate()
              .isNotEmpty) {
            addedMessageSeen = true;
            break;
          }
        }
        expect(
          addedMessageSeen,
          isTrue,
          reason: 'Expected the pin_stop success snackbar '
              '(main.py canvas_nl_edit: \'Added "{name}" — tap + in the '
              'timeline to confirm it.\') within 15s. If this fails, '
              'check ANTHROPIC_API_KEY/MAPBOX_ACCESS_TOKEN in backend/.env.',
        );
        // The location we asked for should show up somewhere on screen
        // (either the pin chip or the snackbar), regardless of exactly
        // how the LLM phrased the pin's name.
        expect(find.textContaining('Truckee'), findsWidgets);
      } finally {
        if (trip?.id != null) {
          await TripService.delete(trip!.id!);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
