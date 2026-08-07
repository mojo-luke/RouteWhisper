import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/route_preview.dart';
import 'package:frontend/widgets/trip_preview_reveal.dart';

/// Widget-level tests for the trip-preview reveal step. Uses directly
/// constructed [RoutePreview] objects rather than a real backend call —
/// this widget is a pure rendering of whatever preview state it's
/// given, and the pipeline that produces that state (real Mapbox +
/// real Anthropic calls, 20-30s) already has its own coverage in
/// backend/tests/test_route_preview.py and backend/scripts/
/// verify_preview.py. Exercising the real pipeline from a Flutter
/// widget test would just re-pay that cost/latency for no new signal.
void main() {
  const pendingPreview = RoutePreview(
    polylineHash: 'hash1',
    polyline: 'poly',
    status: PreviewStatus.pending,
    stage: 'towns',
    distanceMiles: 31.0,
    durationMinutes: 37,
    towns: [PreviewTown(name: 'Columbia', lat: 38.95, lng: -92.33)],
    rundown: '',
    hotspots: [],
  );

  const readyPreview = RoutePreview(
    polylineHash: 'hash1',
    polyline: 'poly',
    status: PreviewStatus.ready,
    stage: 'done',
    distanceMiles: 31.0,
    durationMinutes: 37,
    towns: [
      PreviewTown(name: 'Columbia', lat: 38.95, lng: -92.33),
      PreviewTown(name: 'Jefferson City', lat: 38.58, lng: -92.17),
    ],
    rundown: 'You leave Columbia heading south.',
    hotspots: [
      PreviewHotspot(
        id: 'hs_1',
        title: 'Old Rail Depot',
        town: 'Columbia',
        lat: 38.95,
        lng: -92.33,
        theme: 'history',
        blurb: 'A well-preserved depot from the Gold Rush era.',
        detourHint: 'right off the highway',
      ),
    ],
  );

  const failedPreview = RoutePreview(
    polylineHash: 'hash1',
    polyline: 'poly',
    status: PreviewStatus.failed,
    stage: 'authoring',
    distanceMiles: 31.0,
    durationMinutes: 37,
    towns: [],
    rundown: '',
    hotspots: [],
    error: 'authoring failed',
  );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows a loading spinner while preview is null', (tester) async {
    await tester.pumpWidget(wrap(TripPreviewReveal(
      preview: null,
      preferredThemes: const [],
      selectedHotspotIds: const {},
      onToggleHotspot: (_) {},
    )));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows staged building copy and town chips while pending',
      (tester) async {
    await tester.pumpWidget(wrap(TripPreviewReveal(
      preview: pendingPreview,
      preferredThemes: const [],
      selectedHotspotIds: const {},
      onToggleHotspot: (_) {},
    )));
    expect(find.text('31 mi'), findsOneWidget);
    expect(find.text('37 min'), findsOneWidget);
    expect(find.textContaining('Tracing the route'), findsOneWidget);
    expect(find.text('Columbia'), findsOneWidget);
  });

  testWidgets('shows rundown and hotspot cards once ready', (tester) async {
    await tester.pumpWidget(wrap(TripPreviewReveal(
      preview: readyPreview,
      preferredThemes: const [],
      selectedHotspotIds: const {},
      onToggleHotspot: (_) {},
    )));
    expect(find.text('You leave Columbia heading south.'), findsOneWidget);
    expect(find.text('Old Rail Depot'), findsOneWidget);
    expect(find.text('NEAR COLUMBIA'), findsOneWidget);
  });

  testWidgets('shows a retry affordance when generation failed', (tester) async {
    var retried = false;
    await tester.pumpWidget(wrap(TripPreviewReveal(
      preview: failedPreview,
      preferredThemes: const [],
      selectedHotspotIds: const {},
      onToggleHotspot: (_) {},
      onRetry: () => retried = true,
    )));
    expect(find.textContaining("Couldn't finish"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('tapping add on a hotspot toggles it and shows an undo snackbar',
      (tester) async {
    PreviewHotspot? toggled;
    await tester.pumpWidget(wrap(TripPreviewReveal(
      preview: readyPreview,
      preferredThemes: const [],
      selectedHotspotIds: const {},
      onToggleHotspot: (h) => toggled = h,
    )));

    await tester.tap(find.byIcon(Icons.add_location_alt_outlined));
    await tester.pump();

    expect(toggled?.id, 'hs_1');
    // 5-second undo SnackBar on this state-changing action, per
    // CLAUDE.md rule 3.
    expect(find.textContaining('Added "Old Rail Depot"'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });
}
