import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/trip.dart';

/// Locks in the JSON wire shape between Flutter `Trip` and the backend
/// `Trip` Beanie document. Slice A: skeleton fields only — pins/days
/// are pass-through `List<Map>` and gain typing in slice C+.
void main() {
  group('Trip JSON round-trip', () {
    test('decodes a server-returned trip with id + timestamps', () {
      final trip = Trip.fromJson({
        'id': '507f1f77bcf86cd799439011',
        'name': 'SF → Tahoe weekend',
        'origin_name': 'San Francisco, CA',
        'origin_lat': 37.7749,
        'origin_lng': -122.4194,
        'destination_name': 'Lake Tahoe, CA',
        'destination_lat': 39.0968,
        'destination_lng': -120.0324,
        'start_date': '2026-08-15',
        'end_date': '2026-08-17',
        'arrival_time': '16:00',
        'daily_drive_cap_hours': 5,
        'time_budget_mode': 'discovery',
        'pins': [
          {'type': 'anchor', 'poi': {'name': 'Coffee'}},
        ],
        'days': [
          {'day_number': 1, 'drive_time_minutes': 240},
        ],
        'notes': 'First hotel booked',
        'created_at': '2026-05-12T18:30:00',
        'updated_at': '2026-05-12T18:45:00',
      });
      expect(trip.id, '507f1f77bcf86cd799439011');
      expect(trip.name, 'SF → Tahoe weekend');
      expect(trip.originLat, 37.7749);
      expect(trip.destinationName, 'Lake Tahoe, CA');
      expect(trip.startDate, '2026-08-15');
      expect(trip.arrivalTime, '16:00');
      expect(trip.dailyDriveCapHours, 5);
      expect(trip.timeBudgetMode, 'discovery');
      expect(trip.pins, hasLength(1));
      expect(trip.days, hasLength(1));
      expect(trip.notes, 'First hotel booked');
      expect(trip.createdAt, isNotNull);
      expect(trip.updatedAt, isNotNull);
    });

    test('decodes a minimal trip with sensible defaults', () {
      final trip = Trip.fromJson({
        'name': 'Quick weekend',
        'origin_name': 'A',
        'origin_lat': 0.0,
        'origin_lng': 0.0,
        'destination_name': 'B',
        'destination_lat': 1.0,
        'destination_lng': 1.0,
      });
      expect(trip.id, isNull);
      expect(trip.startDate, isNull);
      expect(trip.arrivalTime, isNull);
      expect(trip.dailyDriveCapHours, 6); // default
      expect(trip.timeBudgetMode, 'moderate'); // default
      expect(trip.pins, isEmpty);
      expect(trip.days, isEmpty);
      expect(trip.notes, isNull);
    });

    test('toJson omits id when null (POST-create path)', () {
      const trip = Trip(
        name: 'New trip',
        originName: 'SF',
        originLat: 37.7,
        originLng: -122.4,
        destinationName: 'LA',
        destinationLat: 34.0,
        destinationLng: -118.2,
      );
      final json = trip.toJson();
      expect(json.containsKey('id'), isFalse);
      expect(json['name'], 'New trip');
      expect(json['daily_drive_cap_hours'], 6);
      expect(json['time_budget_mode'], 'moderate');
    });

    test('toJson includes id when present (PUT-update path)', () {
      const trip = Trip(
        id: 'abc123',
        name: 'X',
        originName: 'A',
        originLat: 0,
        originLng: 0,
        destinationName: 'B',
        destinationLat: 1,
        destinationLng: 1,
      );
      expect(trip.toJson()['id'], 'abc123');
    });

    test('round-trip preserves all fields', () {
      const original = Trip(
        id: 'abc',
        name: 'Coast trip',
        originName: 'SF',
        originLat: 37.7,
        originLng: -122.4,
        destinationName: 'Portland',
        destinationLat: 45.5,
        destinationLng: -122.7,
        startDate: '2026-07-04',
        endDate: '2026-07-08',
        arrivalTime: '18:00',
        dailyDriveCapHours: 7,
        timeBudgetMode: 'discovery',
        pins: [
          {'type': 'lodging', 'name': 'Eureka Inn'},
        ],
        notes: 'Already booked Eureka',
      );
      // toJson doesn't carry timestamps (client doesn't authoritatively
      // produce them); a fromJson round-trip on the body alone preserves
      // everything else.
      final json = original.toJson();
      final round = Trip.fromJson(json);
      expect(round.id, 'abc');
      expect(round.startDate, '2026-07-04');
      expect(round.endDate, '2026-07-08');
      expect(round.arrivalTime, '18:00');
      expect(round.dailyDriveCapHours, 7);
      expect(round.timeBudgetMode, 'discovery');
      expect(round.pins, hasLength(1));
      expect(round.pins.first['name'], 'Eureka Inn');
      expect(round.notes, 'Already booked Eureka');
    });

    test('copyWith clear flags blank optional fields', () {
      const original = Trip(
        name: 'T',
        originName: 'A',
        originLat: 0,
        originLng: 0,
        destinationName: 'B',
        destinationLat: 1,
        destinationLng: 1,
        startDate: '2026-01-01',
        endDate: '2026-01-05',
        arrivalTime: '12:00',
        notes: 'something',
      );
      final cleared = original.copyWith(
        clearStartDate: true,
        clearEndDate: true,
        clearArrivalTime: true,
        clearNotes: true,
      );
      expect(cleared.startDate, isNull);
      expect(cleared.endDate, isNull);
      expect(cleared.arrivalTime, isNull);
      expect(cleared.notes, isNull);
    });
  });
}
