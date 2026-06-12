import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/trip_pin.dart';

void main() {
  group('TripPin', () {
    test('round-trips anchor pin through toJson/fromJson', () {
      const pin = TripPin(
        type: 'anchor',
        id: 'abc-123',
        name: 'Coffee in Truckee',
        lat: 39.3279,
        lng: -120.1833,
      );
      final json = pin.toJson();
      final restored = TripPin.fromJson(json);

      expect(restored.type, 'anchor');
      expect(restored.id, 'abc-123');
      expect(restored.name, 'Coffee in Truckee');
      expect(restored.lat, closeTo(39.3279, 0.00001));
      expect(restored.lng, closeTo(-120.1833, 0.00001));
      expect(restored.dayIndex, isNull);
      expect(restored.timeOfDay, isNull);
    });

    test('round-trips pin with optional fields set', () {
      const pin = TripPin(
        type: 'lodging',
        id: 'xyz-456',
        name: 'Mendocino Inn',
        lat: 39.3057,
        lng: -123.7981,
        dayIndex: 2,
        timeOfDay: '20:00',
      );
      final restored = TripPin.fromJson(pin.toJson());

      expect(restored.dayIndex, 2);
      expect(restored.timeOfDay, '20:00');
    });

    test('omits null optional fields from toJson', () {
      const pin = TripPin(
        type: 'anchor',
        id: 'q',
        name: 'Stop',
        lat: 0,
        lng: 0,
      );
      final json = pin.toJson();
      expect(json.containsKey('day_index'), isFalse);
      expect(json.containsKey('time_of_day'), isFalse);
    });

    test('fromJson defaults missing type to anchor', () {
      final json = {
        'id': 'no-type',
        'name': 'No Type Stop',
        'lat': 0.0,
        'lng': 0.0,
      };
      expect(TripPin.fromJson(json).type, 'anchor');
    });

    test('equality is by id', () {
      const a = TripPin(type: 'anchor', id: 'same', name: 'A', lat: 1, lng: 2);
      const b = TripPin(type: 'anchor', id: 'same', name: 'B', lat: 9, lng: 9);
      const c = TripPin(type: 'anchor', id: 'diff', name: 'A', lat: 1, lng: 2);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces fields selectively', () {
      const pin = TripPin(
        type: 'anchor',
        id: 'orig',
        name: 'Original',
        lat: 1.0,
        lng: 2.0,
        dayIndex: 1,
      );
      final updated = pin.copyWith(name: 'Updated', clearDayIndex: true);
      expect(updated.name, 'Updated');
      expect(updated.lat, 1.0);
      expect(updated.dayIndex, isNull);
    });

    test('all four pin types survive round-trip', () {
      for (final type in ['anchor', 'suggested', 'lodging', 'wing_it']) {
        final pin = TripPin(type: type, id: type, name: type, lat: 0, lng: 0);
        expect(TripPin.fromJson(pin.toJson()).type, type);
      }
    });
  });
}
