import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:frontend/main.dart' as app;
import 'package:frontend/models/trip.dart';
import 'package:frontend/screens/trip_canvas_screen.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/services/trip_service.dart';

/// Integration test for the trip-creation wizard's progressive-reveal
/// flow: step navigation, the preview kicking off in the background the
/// moment origin+destination are both set, and a hotspot picked on the
/// reveal step landing as a `suggested` pin on the created trip.
///
/// Real end to end, same tradeoff as canvas_nl_edit_test.dart: there's
/// no way to mock the backend's Mapbox/Anthropic calls from a Flutter
/// test (the backend is a separate already-running process), so this
/// hits the real route-preview pipeline — one real Anthropic Sonnet
/// call (~20-30s, a few cents). The reveal widget's *rendering* of a
/// given preview state is covered cheaply and deterministically by
/// test/widgets/trip_preview_reveal_test.dart; this file's unique value
/// is the wiring — that starting the wizard's location step actually
/// triggers generation, and that a hotspot picked here actually becomes
/// a pin on the trip the wizard hands back.
///
/// Preconditions:
///   - Backend running (`docker-compose up -d`), real ANTHROPIC_API_KEY
///     and MAPBOX_ACCESS_TOKEN in backend/.env.
///   - Fixture test account exists: `python backend/scripts/manage_test_user.py create`
///
/// Navigation path: dashboard -> "My trips" -> "New trip" FAB ->
/// NewTripWizardScreen.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'wizard steps through to a reveal, and a picked hotspot becomes a pin',
    (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await AuthService.instance.signInForTesting();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      Trip? created;
      try {
        await tester.tap(find.byTooltip('My trips'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        await tester.tap(find.text('New trip'));
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // --- Step 1: Where are you headed? ---
        expect(find.text('Where are you headed?'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.my_location));
        await tester.pumpAndSettle();
        await _searchAndPick(tester, 'Columbia, MO');

        await tester.tap(find.byIcon(Icons.flag_outlined));
        await tester.pumpAndSettle();
        await _searchAndPick(tester, 'Jefferson City, MO');

        // Both endpoints set — the preview should have kicked off in
        // the background already. Continue is enabled now.
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // --- Step 2: name/dates (auto-filled, no interaction needed) ---
        expect(find.text('Call it something'), findsOneWidget);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // --- Step 3: vibe ---
        expect(find.text('What are you in the mood for?'), findsOneWidget);
        await tester.tap(find.text('History'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // --- Step 4: the reveal ---
        expect(find.text("Here's your drive"), findsOneWidget);
        // Real stats should show up immediately (fast Directions call),
        // well before authoring finishes.
        expect(find.textContaining('mi'), findsWidgets);
        expect(find.textContaining('min'), findsWidgets);

        // Real Anthropic call — poll for a hotspot card rather than
        // pumpAndSettle (the building state's spinner never settles).
        var hotspotFound = false;
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(seconds: 1));
          if (find.byIcon(Icons.add_location_alt_outlined).evaluate().isNotEmpty) {
            hotspotFound = true;
            break;
          }
        }
        expect(
          hotspotFound,
          isTrue,
          reason: 'Expected route-preview generation to produce at least '
              'one hotspot within 60s. If this fails, check '
              'ANTHROPIC_API_KEY/MAPBOX_ACCESS_TOKEN in backend/.env.',
        );

        await tester.tap(find.byIcon(Icons.add_location_alt_outlined).first);
        await tester.pump();
        // Dismiss the undo snackbar rather than waiting it out, so it
        // doesn't obscure the footer button on the next pump.
        await tester.pump(const Duration(seconds: 6));

        await tester.tap(find.text('Create trip'));
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // MyTripsScreen pushes the canvas on top once the wizard hands
        // back a saved trip (per the "land on canvas" product decision),
        // rather than popping back to the list.
        expect(find.byType(TripCanvasScreen), findsOneWidget);

        final trips = await TripService.list();
        final matches =
            trips.where((t) => t.originName.contains('Columbia')).toList();
        created = matches.isEmpty ? null : matches.first;
        expect(created, isNotNull,
            reason: 'The trip created by the wizard should be listed');
        expect(created!.polyline, isNotNull,
            reason: 'The wizard should hand its already-computed '
                'polyline to trip creation');
        expect(created.pins, hasLength(1));
        expect(created.pins.first.type, 'suggested');
        expect(created.pins.first.name, isNotEmpty);
      } finally {
        if (created?.id != null) {
          await TripService.delete(created!.id!);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Types [query] into the location search field and taps the first
/// result once it appears.
Future<void> _searchAndPick(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  var found = false;
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (find.byIcon(Icons.place_outlined).evaluate().isNotEmpty) {
      found = true;
      break;
    }
  }
  expect(found, isTrue,
      reason: 'Real Mapbox geocoding search for "$query" should return '
          'at least one result within 10s.');
  await tester.tap(find.byIcon(Icons.place_outlined).first);
  await tester.pumpAndSettle();
}
