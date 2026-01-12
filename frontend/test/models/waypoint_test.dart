import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/waypoint.dart';
import 'package:frontend/services/poi_api_service.dart';

void main() {
  group('Waypoint Model Tests', () {
    test('Factory: creates manual waypoint with correct defaults', () {
      final waypoint = Waypoint.manual(
        name: 'Test Stop',
        latitude: 37.7749,
        longitude: -122.4194,
        order: 1,
        address: '123 Main St',
      );

      expect(waypoint.name, 'Test Stop');
      expect(waypoint.latitude, 37.7749);
      expect(waypoint.longitude, -122.4194);
      expect(waypoint.type, WaypointType.manual);
      expect(waypoint.order, 1);
      expect(waypoint.address, '123 Main St');
      expect(waypoint.estimatedDurationMinutes, 15); // Default
      expect(waypoint.status, WaypointStatus.pending);
      expect(waypoint.requiresConfirmation, true);
      expect(waypoint.id, isNotEmpty);
    });

    test('Factory: creates origin waypoint with correct defaults', () {
      final waypoint = Waypoint.origin(
        latitude: 37.7749,
        longitude: -122.4194,
        name: 'Start Location',
      );

      expect(waypoint.name, 'Start Location');
      expect(waypoint.type, WaypointType.origin);
      expect(waypoint.order, 0);
      expect(waypoint.estimatedDurationMinutes, 0); // No stop at origin
      expect(waypoint.requiresConfirmation, false);
    });

    test('Factory: creates destination waypoint with correct defaults', () {
      final waypoint = Waypoint.destination(
        latitude: 34.0522,
        longitude: -118.2437,
        name: 'End Location',
        order: 5,
      );

      expect(waypoint.name, 'End Location');
      expect(waypoint.type, WaypointType.destination);
      expect(waypoint.order, 5);
      expect(waypoint.estimatedDurationMinutes, 0); // No stop at destination
      expect(waypoint.requiresConfirmation, false);
    });

    test('Factory: creates waypoint from POI with category-based duration', () {
      final poi = POI(
        id: 'poi-1',
        name: 'Shell Gas Station',
        category: 'gas_station',
        latitude: 37.7749,
        longitude: -122.4194,
        estimatedDurationMinutes: 15,
        distanceFromRouteMiles: 0.5,
      );

      final waypoint = Waypoint.fromPOI(poi, 1);

      expect(waypoint.name, 'Shell Gas Station');
      expect(waypoint.latitude, 37.7749);
      expect(waypoint.longitude, -122.4194);
      expect(waypoint.type, WaypointType.poi);
      expect(waypoint.sourcePOI, poi);
      expect(waypoint.estimatedDurationMinutes, 10); // Gas station = 10 min
      expect(waypoint.order, 1);
    });

    test('Category-based durations are correct', () {
      final categories = {
        'gas_station': 10,
        'restaurant': 45,
        'coffee': 20,
        'cafe': 20,
        'scenic': 30,
        'viewpoint': 30,
        'park': 60,
        'rest_area': 15,
        'unknown_category': 15, // Default
      };

      categories.forEach((category, expectedDuration) {
        final poi = POI(
          id: 'test',
          name: 'Test POI',
          category: category,
          latitude: 0,
          longitude: 0,
          estimatedDurationMinutes: 15,
          distanceFromRouteMiles: 0,
        );

        final waypoint = Waypoint.fromPOI(poi, 0);
        expect(
          waypoint.estimatedDurationMinutes,
          expectedDuration,
          reason: 'Category $category should have duration $expectedDuration',
        );
      });
    });

    test('markArrival sets arrival time and status to active', () {
      final waypoint = Waypoint.manual(
        name: 'Test Stop',
        latitude: 37.7749,
        longitude: -122.4194,
        order: 1,
      );

      final arrivedWaypoint = waypoint.markArrival();

      expect(arrivedWaypoint.arrivalTime, isNotNull);
      expect(arrivedWaypoint.status, WaypointStatus.active);
      expect(arrivedWaypoint.departureTime, isNull);
      expect(arrivedWaypoint.actualDurationMinutes, isNull);

      // Verify arrival time is recent (within last second)
      final now = DateTime.now();
      final diff = now.difference(arrivedWaypoint.arrivalTime!).abs();
      expect(diff.inSeconds, lessThan(2));
    });

    test('markDeparture sets departure time and calculates duration', () async {
      final waypoint = Waypoint.manual(
        name: 'Test Stop',
        latitude: 37.7749,
        longitude: -122.4194,
        order: 1,
      );

      // Mark arrival
      final arrivedWaypoint = waypoint.markArrival();

      // Wait a bit to simulate actual stop
      await Future.delayed(const Duration(milliseconds: 100));

      // Mark departure
      final departedWaypoint = arrivedWaypoint.markDeparture(isAutomatic: false);

      expect(departedWaypoint.departureTime, isNotNull);
      expect(departedWaypoint.actualDurationMinutes, isNotNull);
      expect(departedWaypoint.actualDurationMinutes, greaterThanOrEqualTo(0));
      expect(departedWaypoint.status, WaypointStatus.completed);
      expect(departedWaypoint.isAutomaticDeparture, false);
    });

    test('markDeparture with automatic flag sets isAutomaticDeparture', () async {
      final waypoint = Waypoint.manual(
        name: 'Test Stop',
        latitude: 37.7749,
        longitude: -122.4194,
        order: 1,
      ).markArrival();

      await Future.delayed(const Duration(milliseconds: 100));

      final departedWaypoint = waypoint.markDeparture(isAutomatic: true);

      expect(departedWaypoint.isAutomaticDeparture, true);
      expect(departedWaypoint.status, WaypointStatus.completed);
    });

    test('markDeparture without arrival time handles gracefully', () {
      final waypoint = Waypoint.manual(
        name: 'Test Stop',
        latitude: 37.7749,
        longitude: -122.4194,
        order: 1,
      );

      // Mark departure without arrival (edge case)
      final departedWaypoint = waypoint.markDeparture();

      expect(departedWaypoint.departureTime, isNotNull);
      expect(departedWaypoint.actualDurationMinutes, isNull); // Can't calculate
      expect(departedWaypoint.status, WaypointStatus.completed);
    });

    test('calculatedDuration returns correct duration', () async {
      final waypoint = Waypoint.manual(
        name: 'Test Stop',
        latitude: 37.7749,
        longitude: -122.4194,
        order: 1,
      ).markArrival();

      // Wait to create measurable duration
      await Future.delayed(const Duration(milliseconds: 100));

      final departedWaypoint = waypoint.markDeparture();

      expect(departedWaypoint.calculatedDuration, isNotNull);
      expect(departedWaypoint.calculatedDuration, greaterThanOrEqualTo(0));
    });

    test('calculatedDuration returns null when times not set', () {
      final waypoint = Waypoint.manual(
        name: 'Test Stop',
        latitude: 37.7749,
        longitude: -122.4194,
        order: 1,
      );

      expect(waypoint.calculatedDuration, isNull);
    });

    test('copyWith creates new instance with updated fields', () {
      final original = Waypoint.manual(
        name: 'Original',
        latitude: 37.7749,
        longitude: -122.4194,
        order: 1,
      );

      final modified = original.copyWith(
        name: 'Modified',
        order: 2,
        estimatedDurationMinutes: 30,
        status: WaypointStatus.active,
      );

      expect(modified.name, 'Modified');
      expect(modified.order, 2);
      expect(modified.estimatedDurationMinutes, 30);
      expect(modified.status, WaypointStatus.active);

      // Unchanged fields should remain
      expect(modified.id, original.id);
      expect(modified.latitude, original.latitude);
      expect(modified.longitude, original.longitude);
    });

    test('toJson serializes all fields correctly', () {
      final arrivalTime = DateTime(2026, 1, 10, 14, 30);
      final departureTime = DateTime(2026, 1, 10, 14, 45);

      final waypoint = Waypoint(
        id: 'test-id',
        name: 'Test Waypoint',
        latitude: 37.7749,
        longitude: -122.4194,
        type: WaypointType.manual,
        status: WaypointStatus.completed,
        order: 1,
        address: '123 Main St',
        estimatedDurationMinutes: 15,
        arrivalTime: arrivalTime,
        departureTime: departureTime,
        actualDurationMinutes: 15,
        isAutomaticDeparture: false,
      );

      final json = waypoint.toJson();

      expect(json['id'], 'test-id');
      expect(json['name'], 'Test Waypoint');
      expect(json['latitude'], 37.7749);
      expect(json['longitude'], -122.4194);
      expect(json['type'], 'manual');
      expect(json['status'], 'completed');
      expect(json['order'], 1);
      expect(json['address'], '123 Main St');
      expect(json['estimated_duration_minutes'], 15);
      expect(json['arrival_time'], arrivalTime.toIso8601String());
      expect(json['departure_time'], departureTime.toIso8601String());
      expect(json['actual_duration_minutes'], 15);
      expect(json['is_automatic_departure'], false);
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'id': 'test-id',
        'name': 'Test Waypoint',
        'latitude': 37.7749,
        'longitude': -122.4194,
        'type': 'manual',
        'status': 'completed',
        'order': 1,
        'address': '123 Main St',
        'estimated_duration_minutes': 15,
        'arrival_time': '2026-01-10T14:30:00.000',
        'departure_time': '2026-01-10T14:45:00.000',
        'actual_duration_minutes': 15,
        'is_automatic_departure': false,
      };

      final waypoint = Waypoint.fromJson(json);

      expect(waypoint.id, 'test-id');
      expect(waypoint.name, 'Test Waypoint');
      expect(waypoint.latitude, 37.7749);
      expect(waypoint.longitude, -122.4194);
      expect(waypoint.type, WaypointType.manual);
      expect(waypoint.status, WaypointStatus.completed);
      expect(waypoint.order, 1);
      expect(waypoint.address, '123 Main St');
      expect(waypoint.estimatedDurationMinutes, 15);
      expect(waypoint.arrivalTime, DateTime.parse('2026-01-10T14:30:00.000'));
      expect(waypoint.departureTime, DateTime.parse('2026-01-10T14:45:00.000'));
      expect(waypoint.actualDurationMinutes, 15);
      expect(waypoint.isAutomaticDeparture, false);
    });

    test('toJson → fromJson roundtrip preserves data', () {
      final original = Waypoint.manual(
        name: 'Test Waypoint',
        latitude: 37.7749,
        longitude: -122.4194,
        order: 1,
        address: '123 Main St',
        estimatedDurationMinutes: 30,
      ).markArrival().markDeparture();

      final json = original.toJson();
      final deserialized = Waypoint.fromJson(json);

      expect(deserialized.name, original.name);
      expect(deserialized.latitude, original.latitude);
      expect(deserialized.longitude, original.longitude);
      expect(deserialized.type, original.type);
      expect(deserialized.status, original.status);
      expect(deserialized.order, original.order);
      expect(deserialized.estimatedDurationMinutes, original.estimatedDurationMinutes);
    });

    test('Equality operator works correctly', () {
      final waypoint1 = Waypoint.manual(
        name: 'Test',
        latitude: 37.7749,
        longitude: -122.4194,
        order: 1,
      );

      final waypoint2 = waypoint1.copyWith(name: 'Different Name');
      final waypoint3 = Waypoint.manual(
        name: 'Test',
        latitude: 37.7749,
        longitude: -122.4194,
        order: 1,
      );

      expect(waypoint1 == waypoint2, true); // Same ID
      expect(waypoint1 == waypoint3, false); // Different ID
      expect(waypoint1 == waypoint1, true); // Identical
    });

    test('hashCode is based on ID', () {
      final waypoint = Waypoint.manual(
        name: 'Test',
        latitude: 37.7749,
        longitude: -122.4194,
        order: 1,
      );

      expect(waypoint.hashCode, waypoint.id.hashCode);
    });

    test('toString returns readable representation', () {
      final waypoint = Waypoint.manual(
        name: 'Test Stop',
        latitude: 37.7749,
        longitude: -122.4194,
        order: 1,
      );

      final string = waypoint.toString();

      expect(string, contains('Test Stop'));
      expect(string, contains('manual'));
      expect(string, contains('pending'));
      expect(string, contains('1'));
    });

    test('Custom estimated duration overrides category default', () {
      final poi = POI(
        id: 'test',
        name: 'Restaurant',
        category: 'restaurant', // Default would be 45 min
        latitude: 0,
        longitude: 0,
        estimatedDurationMinutes: 15,
        distanceFromRouteMiles: 0,
      );

      final waypoint = Waypoint.fromPOI(poi, 0, estimatedDurationMinutes: 60);

      expect(waypoint.estimatedDurationMinutes, 60); // Custom value
    });
  });
}
