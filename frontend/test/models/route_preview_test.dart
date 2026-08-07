import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/route_preview.dart';

/// Locks in the JSON wire shape between Flutter `RoutePreview` and the
/// backend `RoutePreview` Beanie document (app/database.py) served by
/// the /api/v1/route/preview endpoints.
void main() {
  group('RoutePreview.fromJson', () {
    test('decodes a pending preview with real stats but no content yet', () {
      final preview = RoutePreview.fromJson({
        'polyline_hash': 'abc123',
        'polyline': 'encodedpolyline',
        'status': 'pending',
        'stage': 'towns',
        'distance_miles': 87.5,
        'duration_minutes': 112,
        'towns': [],
        'rundown': '',
        'hotspots': [],
      });
      expect(preview.status, PreviewStatus.pending);
      expect(preview.isReady, isFalse);
      expect(preview.isFailed, isFalse);
      expect(preview.stage, 'towns');
      expect(preview.distanceLabel, '88 mi');
      expect(preview.durationLabel, '1 hr 52 min');
      expect(preview.towns, isEmpty);
    });

    test('decodes a ready preview with towns, rundown, and hotspots', () {
      final preview = RoutePreview.fromJson({
        'polyline_hash': 'abc123',
        'polyline': 'encodedpolyline',
        'status': 'ready',
        'stage': 'done',
        'distance_miles': 31.0,
        'duration_minutes': 37,
        'towns': [
          {'name': 'Columbia', 'lat': 38.95, 'lng': -92.33},
          {'name': 'Jefferson City', 'lat': 38.58, 'lng': -92.17},
        ],
        'rundown': 'A short valley drive.',
        'hotspots': [
          {
            'id': 'hs_1',
            'title': 'Old Rail Depot',
            'town': 'Columbia',
            'lat': 38.95,
            'lng': -92.33,
            'theme': 'history',
            'blurb': 'A well-preserved depot.',
            'detour_hint': 'right off the highway',
          },
        ],
      });
      expect(preview.isReady, isTrue);
      expect(preview.durationLabel, '37 min');
      expect(preview.towns, hasLength(2));
      expect(preview.towns.first.name, 'Columbia');
      expect(preview.rundown, 'A short valley drive.');
      expect(preview.hotspots, hasLength(1));
      final hotspot = preview.hotspots.first;
      expect(hotspot.title, 'Old Rail Depot');
      expect(hotspot.theme, 'history');
      expect(hotspot.detourHint, 'right off the highway');
    });

    test('decodes a failed preview with an error message', () {
      final preview = RoutePreview.fromJson({
        'polyline_hash': 'abc123',
        'polyline': 'encodedpolyline',
        'status': 'failed',
        'stage': 'authoring',
        'distance_miles': 10.0,
        'duration_minutes': 15,
        'towns': [],
        'rundown': '',
        'hotspots': [],
        'error': 'no ANTHROPIC_API_KEY',
      });
      expect(preview.isFailed, isTrue);
      expect(preview.error, 'no ANTHROPIC_API_KEY');
    });
  });

  group('PreviewHotspot.toPin', () {
    test('builds a suggested-type pin at the anchor town coordinates', () {
      const hotspot = PreviewHotspot(
        id: 'hs_3',
        title: 'Donner Pass',
        town: 'Truckee',
        lat: 39.328,
        lng: -120.33,
        theme: 'history',
        blurb: 'Gold Rush history.',
      );
      final pin = hotspot.toPin();
      expect(pin.type, 'suggested');
      expect(pin.id, 'hs-hs_3');
      expect(pin.name, 'Donner Pass');
      expect(pin.lat, 39.328);
      expect(pin.lng, -120.33);
    });
  });
}
