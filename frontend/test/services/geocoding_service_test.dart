import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/geocoding_service.dart';

/// Pins the JSON wire shape between the backend `/geocode` response and
/// the `GeocodeCandidate` the wizard consumes. The wizard ultimately
/// feeds these into Trip.origin*/destination* fields, so getting this
/// contract right protects trip creation.
void main() {
  group('GeocodeCandidate JSON', () {
    test('decodes a full candidate from the backend', () {
      final c = GeocodeCandidate.fromJson({
        'name': 'San Francisco',
        'full_address': 'San Francisco, California, United States',
        'lat': 37.7749,
        'lng': -122.4194,
        'place_type': 'place',
        'mapbox_id': 'dXJuOm1ieHBsYzpFSktVcA==',
      });
      expect(c.name, 'San Francisco');
      expect(c.fullAddress, 'San Francisco, California, United States');
      expect(c.lat, 37.7749);
      expect(c.lng, -122.4194);
      expect(c.placeType, 'place');
      expect(c.mapboxId, 'dXJuOm1ieHBsYzpFSktVcA==');
    });

    test('tolerates missing optional fields (mapbox_id, place_type, address)',
        () {
      final c = GeocodeCandidate.fromJson({
        'name': 'Some place',
        'lat': 1.0,
        'lng': 2.0,
      });
      expect(c.name, 'Some place');
      expect(c.fullAddress, isNull);
      expect(c.placeType, isNull);
      expect(c.mapboxId, '');
    });

    test('displayLine prefers full_address when present', () {
      final c = GeocodeCandidate.fromJson({
        'name': 'Coffee shop',
        'full_address': '123 Main St, Anytown',
        'lat': 0,
        'lng': 0,
      });
      expect(c.displayLine, '123 Main St, Anytown');
    });

    test('displayLine falls back to name when full_address is empty/null', () {
      final fromNull = GeocodeCandidate.fromJson({
        'name': 'Just a name',
        'lat': 0,
        'lng': 0,
      });
      expect(fromNull.displayLine, 'Just a name');

      final fromEmpty = GeocodeCandidate.fromJson({
        'name': 'Just a name',
        'full_address': '',
        'lat': 0,
        'lng': 0,
      });
      expect(fromEmpty.displayLine, 'Just a name');
    });

    test('coerces int coordinates to doubles', () {
      // Mapbox / FastAPI sometimes serialize whole numbers without a
      // decimal point — guard the parse.
      final c = GeocodeCandidate.fromJson({
        'name': 'Round-number place',
        'lat': 37,
        'lng': -122,
      });
      expect(c.lat, 37.0);
      expect(c.lng, -122.0);
    });
  });

  group('GeocodingService.search', () {
    test('empty/whitespace query short-circuits without a network call',
        () async {
      // No HTTP client is wired up in the test environment; a real call
      // would throw. The short-circuit guarantees we never reach it.
      expect(await GeocodingService.search(''), isEmpty);
      expect(await GeocodingService.search('   '), isEmpty);
    });
  });
}
