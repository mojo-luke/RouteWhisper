import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/waypoint_manager.dart';
import 'package:frontend/models/waypoint.dart';

void main() {
  group('WaypointManager Tests', () {
    late WaypointManager manager;

    setUp(() {
      manager = WaypointManager();
    });

    group('Basic Operations', () {
      test('Starts with empty waypoint list', () {
        expect(manager.getWaypoints(), isEmpty);
        expect(manager.hasIntermediateWaypoints(), false);
      });

      test('addWaypoint adds waypoint with correct order', () {
        final waypoint = Waypoint.manual(
          name: 'Test Stop',
          latitude: 37.7749,
          longitude: -122.4194,
          order: 0,
        );

        final added = manager.addWaypoint(waypoint);

        expect(manager.getWaypoints().length, 1);
        expect(added.order, 0);
        expect(added.name, 'Test Stop');
      });

      test('addWaypoint inserts before destination if it exists', () {
        // Set destination
        manager.setDestination(
          latitude: 34.0522,
          longitude: -118.2437,
          name: 'Destination',
        );

        // Add intermediate waypoint
        final waypoint = Waypoint.manual(
          name: 'Stop 1',
          latitude: 37.7749,
          longitude: -122.4194,
          order: 0,
        );

        manager.addWaypoint(waypoint);

        final waypoints = manager.getWaypoints();
        expect(waypoints.length, 2);
        expect(waypoints[0].name, 'Stop 1');
        expect(waypoints[0].order, 0);
        expect(waypoints[1].name, 'Destination');
        expect(waypoints[1].order, 1);
      });

      test('removeWaypoint removes intermediate waypoint', () {
        final waypoint = Waypoint.manual(
          name: 'Test Stop',
          latitude: 37.7749,
          longitude: -122.4194,
          order: 0,
        );

        final added = manager.addWaypoint(waypoint);
        expect(manager.getWaypoints().length, 1);

        final removed = manager.removeWaypoint(added.id);
        expect(removed, true);
        expect(manager.getWaypoints(), isEmpty);
      });

      test('removeWaypoint returns false for non-existent waypoint', () {
        final removed = manager.removeWaypoint('non-existent-id');
        expect(removed, false);
      });

      test('removeWaypoint prevents removing origin', () {
        manager.setOrigin(
          latitude: 37.7749,
          longitude: -122.4194,
          name: 'Start',
        );

        final origin = manager.getWaypoints().first;
        final removed = manager.removeWaypoint(origin.id);

        expect(removed, false);
        expect(manager.getWaypoints().length, 1);
      });

      test('removeWaypoint prevents removing destination', () {
        manager.setDestination(
          latitude: 34.0522,
          longitude: -118.2437,
          name: 'End',
        );

        final destination = manager.getWaypoints().first;
        final removed = manager.removeWaypoint(destination.id);

        expect(removed, false);
        expect(manager.getWaypoints().length, 1);
      });

      test('clearIntermediateWaypoints keeps origin and destination', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194);
        manager.setDestination(latitude: 34.0522, longitude: -118.2437);

        manager.addWaypoint(Waypoint.manual(
          name: 'Stop 1',
          latitude: 36.0,
          longitude: -121.0,
          order: 0,
        ));
        manager.addWaypoint(Waypoint.manual(
          name: 'Stop 2',
          latitude: 35.5,
          longitude: -120.5,
          order: 0,
        ));

        expect(manager.getWaypoints().length, 4);

        manager.clearIntermediateWaypoints();

        expect(manager.getWaypoints().length, 2);
        expect(manager.getWaypoints()[0].type, WaypointType.origin);
        expect(manager.getWaypoints()[1].type, WaypointType.destination);
      });

      test('clearAll removes all waypoints', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194);
        manager.setDestination(latitude: 34.0522, longitude: -118.2437);
        manager.addWaypoint(Waypoint.manual(
          name: 'Stop',
          latitude: 36.0,
          longitude: -121.0,
          order: 0,
        ));

        expect(manager.getWaypoints().length, 3);

        manager.clearAll();

        expect(manager.getWaypoints(), isEmpty);
      });
    });

    group('Origin and Destination Management', () {
      test('setOrigin creates origin waypoint at position 0', () {
        manager.setOrigin(
          latitude: 37.7749,
          longitude: -122.4194,
          name: 'San Francisco',
        );

        final waypoints = manager.getWaypoints();
        expect(waypoints.length, 1);
        expect(waypoints[0].type, WaypointType.origin);
        expect(waypoints[0].name, 'San Francisco');
        expect(waypoints[0].order, 0);
        expect(waypoints[0].estimatedDurationMinutes, 0);
      });

      test('setOrigin replaces existing origin', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194, name: 'Old Origin');
        manager.setOrigin(latitude: 34.0522, longitude: -118.2437, name: 'New Origin');

        final waypoints = manager.getWaypoints();
        expect(waypoints.length, 1);
        expect(waypoints[0].name, 'New Origin');
      });

      test('setDestination creates destination waypoint at end', () {
        manager.setDestination(
          latitude: 34.0522,
          longitude: -118.2437,
          name: 'Los Angeles',
        );

        final waypoints = manager.getWaypoints();
        expect(waypoints.length, 1);
        expect(waypoints[0].type, WaypointType.destination);
        expect(waypoints[0].name, 'Los Angeles');
        expect(waypoints[0].estimatedDurationMinutes, 0);
      });

      test('setDestination replaces existing destination', () {
        manager.setDestination(latitude: 34.0522, longitude: -118.2437, name: 'Old Dest');
        manager.setDestination(latitude: 36.0, longitude: -121.0, name: 'New Dest');

        final waypoints = manager.getWaypoints();
        expect(waypoints.length, 1);
        expect(waypoints[0].name, 'New Dest');
      });
    });

    group('Reordering', () {
      test('reorderWaypoint moves waypoint correctly', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194);

        manager.addWaypoint(Waypoint.manual(name: 'Stop 1', latitude: 36.0, longitude: -121.0, order: 0));
        manager.addWaypoint(Waypoint.manual(name: 'Stop 2', latitude: 35.5, longitude: -120.5, order: 0));
        manager.addWaypoint(Waypoint.manual(name: 'Stop 3', latitude: 35.0, longitude: -120.0, order: 0));

        manager.setDestination(latitude: 34.0522, longitude: -118.2437);

        // Reorder Stop 1 (index 0) to index 2
        manager.reorderWaypoint(0, 2);

        final waypoints = manager.getWaypoints();
        expect(waypoints[0].type, WaypointType.origin);
        expect(waypoints[1].name, 'Stop 2');
        expect(waypoints[2].name, 'Stop 3');
        expect(waypoints[3].name, 'Stop 1');
        expect(waypoints[4].type, WaypointType.destination);
      });

      test('reorderWaypoint handles invalid indices gracefully', () {
        manager.addWaypoint(Waypoint.manual(name: 'Stop 1', latitude: 36.0, longitude: -121.0, order: 0));

        // Try to reorder with out-of-bounds indices
        manager.reorderWaypoint(-1, 0);
        manager.reorderWaypoint(0, 10);

        // Should not crash, waypoint should remain
        expect(manager.getWaypoints().length, 1);
      });
    });

    group('Status Management', () {
      test('updateWaypoint updates existing waypoint', () {
        final waypoint = Waypoint.manual(
          name: 'Test Stop',
          latitude: 37.7749,
          longitude: -122.4194,
          order: 0,
        );

        final added = manager.addWaypoint(waypoint);
        final updated = added.copyWith(
          status: WaypointStatus.active,
          estimatedDurationMinutes: 30,
        );

        manager.updateWaypoint(updated);

        final retrieved = manager.getWaypointById(added.id);
        expect(retrieved!.status, WaypointStatus.active);
        expect(retrieved.estimatedDurationMinutes, 30);
      });

      test('skipWaypoint marks waypoint as skipped', () {
        final waypoint = Waypoint.manual(
          name: 'Test Stop',
          latitude: 37.7749,
          longitude: -122.4194,
          order: 0,
        );

        final added = manager.addWaypoint(waypoint);
        manager.skipWaypoint(added.id);

        final retrieved = manager.getWaypointById(added.id);
        expect(retrieved!.status, WaypointStatus.skipped);
      });

      test('resetWaypointStatuses resets all to pending', () {
        final wp1 = manager.addWaypoint(Waypoint.manual(name: 'Stop 1', latitude: 36.0, longitude: -121.0, order: 0));
        final wp2 = manager.addWaypoint(Waypoint.manual(name: 'Stop 2', latitude: 35.5, longitude: -120.5, order: 0));

        // Mark waypoints with different statuses
        manager.updateWaypoint(wp1.copyWith(status: WaypointStatus.active));
        manager.updateWaypoint(wp2.copyWith(status: WaypointStatus.completed));

        manager.resetWaypointStatuses();

        final waypoints = manager.getWaypoints();
        expect(waypoints.every((wp) => wp.status == WaypointStatus.pending), true);
        expect(waypoints.every((wp) => wp.arrivalTime == null), true);
        expect(waypoints.every((wp) => wp.departureTime == null), true);
      });
    });

    group('Query Methods', () {
      test('getWaypointById returns correct waypoint', () {
        final waypoint = Waypoint.manual(
          name: 'Test Stop',
          latitude: 37.7749,
          longitude: -122.4194,
          order: 0,
        );

        final added = manager.addWaypoint(waypoint);
        final retrieved = manager.getWaypointById(added.id);

        expect(retrieved, isNotNull);
        expect(retrieved!.id, added.id);
        expect(retrieved.name, 'Test Stop');
      });

      test('getWaypointById returns null for non-existent ID', () {
        final retrieved = manager.getWaypointById('non-existent');
        expect(retrieved, isNull);
      });

      test('getIntermediateWaypoints excludes origin and destination', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194);
        manager.addWaypoint(Waypoint.manual(name: 'Stop 1', latitude: 36.0, longitude: -121.0, order: 0));
        manager.addWaypoint(Waypoint.manual(name: 'Stop 2', latitude: 35.5, longitude: -120.5, order: 0));
        manager.setDestination(latitude: 34.0522, longitude: -118.2437);

        final intermediate = manager.getIntermediateWaypoints();

        expect(intermediate.length, 2);
        expect(intermediate.every((wp) => wp.type != WaypointType.origin && wp.type != WaypointType.destination), true);
      });

      test('hasIntermediateWaypoints returns correct boolean', () {
        expect(manager.hasIntermediateWaypoints(), false);

        manager.setOrigin(latitude: 37.7749, longitude: -122.4194);
        manager.setDestination(latitude: 34.0522, longitude: -118.2437);
        expect(manager.hasIntermediateWaypoints(), false);

        manager.addWaypoint(Waypoint.manual(name: 'Stop', latitude: 36.0, longitude: -121.0, order: 0));
        expect(manager.hasIntermediateWaypoints(), true);
      });

      test('getNextPendingWaypoint returns first pending waypoint', () {
        manager.addWaypoint(Waypoint.manual(name: 'Stop 1', latitude: 36.0, longitude: -121.0, order: 0));
        manager.addWaypoint(Waypoint.manual(name: 'Stop 2', latitude: 35.5, longitude: -120.5, order: 0));

        final next = manager.getNextPendingWaypoint();
        expect(next, isNotNull);
        expect(next!.name, 'Stop 1');
      });

      test('getNextPendingWaypoint returns null when none pending', () {
        final wp = manager.addWaypoint(Waypoint.manual(name: 'Stop', latitude: 36.0, longitude: -121.0, order: 0));
        manager.updateWaypoint(wp.copyWith(status: WaypointStatus.completed));

        final next = manager.getNextPendingWaypoint();
        expect(next, isNull);
      });

      test('getActiveWaypoint returns currently active waypoint', () {
        manager.addWaypoint(Waypoint.manual(name: 'Stop 1', latitude: 36.0, longitude: -121.0, order: 0));
        final wp2 = manager.addWaypoint(Waypoint.manual(name: 'Stop 2', latitude: 35.5, longitude: -120.5, order: 0));

        manager.updateWaypoint(wp2.copyWith(status: WaypointStatus.active));

        final active = manager.getActiveWaypoint();
        expect(active, isNotNull);
        expect(active!.name, 'Stop 2');
      });

      test('getActiveWaypoint returns null when none active', () {
        manager.addWaypoint(Waypoint.manual(name: 'Stop', latitude: 36.0, longitude: -121.0, order: 0));

        final active = manager.getActiveWaypoint();
        expect(active, isNull);
      });
    });

    group('Calculations', () {
      test('getCoordinatesList returns correct format', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194);
        manager.addWaypoint(Waypoint.manual(name: 'Stop', latitude: 36.0, longitude: -121.0, order: 0));
        manager.setDestination(latitude: 34.0522, longitude: -118.2437);

        final coords = manager.getCoordinatesList();

        expect(coords.length, 3);
        expect(coords[0], [-122.4194, 37.7749]); // [lng, lat]
        expect(coords[1], [-121.0, 36.0]);
        expect(coords[2], [-118.2437, 34.0522]);
      });

      test('calculateTotalTripDuration includes stop times', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194);

        // Add intermediate waypoints with different durations
        manager.addWaypoint(Waypoint.manual(
          name: 'Stop 1',
          latitude: 36.0,
          longitude: -121.0,
          order: 0,
          estimatedDurationMinutes: 15,
        ));
        manager.addWaypoint(Waypoint.manual(
          name: 'Stop 2',
          latitude: 35.5,
          longitude: -120.5,
          order: 0,
          estimatedDurationMinutes: 30,
        ));

        manager.setDestination(latitude: 34.0522, longitude: -118.2437);

        final drivingTime = const Duration(hours: 2);
        final totalTime = manager.calculateTotalTripDuration(drivingTime: drivingTime);

        // 2 hours driving + 15 min + 30 min = 2 hours 45 min
        expect(totalTime, const Duration(hours: 2, minutes: 45));
      });

      test('calculateTotalTripDuration excludes origin and destination', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194);
        manager.setDestination(latitude: 34.0522, longitude: -118.2437);

        final drivingTime = const Duration(hours: 2);
        final totalTime = manager.calculateTotalTripDuration(drivingTime: drivingTime);

        expect(totalTime, const Duration(hours: 2)); // No stops added
      });

      test('getStopSummary returns correct summary', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194);

        manager.addWaypoint(Waypoint.manual(
          name: 'Stop 1',
          latitude: 36.0,
          longitude: -121.0,
          order: 0,
          estimatedDurationMinutes: 15,
        ));
        manager.addWaypoint(Waypoint.manual(
          name: 'Stop 2',
          latitude: 35.5,
          longitude: -120.5,
          order: 0,
          estimatedDurationMinutes: 30,
        ));

        manager.setDestination(latitude: 34.0522, longitude: -118.2437);

        final summary = manager.getStopSummary();

        expect(summary['waypointCount'], 2);
        expect(summary['totalStopMinutes'], 45);
        expect(summary['totalStopHours'], '0.8'); // 45/60 = 0.75 → 0.8 (rounded to 1 decimal)
        expect(summary['waypoints'], isA<List>());
        expect((summary['waypoints'] as List).length, 2);
      });
    });

    group('Listener Notifications', () {
      test('notifies listeners when waypoints change (ChangeNotifier)', () {
        bool notified = false;
        manager.addListener(() {
          notified = true;
        });

        manager.addWaypoint(Waypoint.manual(
          name: 'Test',
          latitude: 37.7749,
          longitude: -122.4194,
          order: 0,
        ));

        expect(notified, true);
      });

      test('onWaypointsChanged callback still works (deprecated)', () {
        List<Waypoint>? notifiedWaypoints;
        manager.onWaypointsChanged = (waypoints) {
          notifiedWaypoints = waypoints;
        };

        manager.addWaypoint(Waypoint.manual(
          name: 'Test',
          latitude: 37.7749,
          longitude: -122.4194,
          order: 0,
        ));

        expect(notifiedWaypoints, isNotNull);
        expect(notifiedWaypoints!.length, 1);
      });

      test('onWaypointsChanged callback is triggered on remove', () {
        int callCount = 0;
        manager.onWaypointsChanged = (_) {
          callCount++;
        };

        final wp = manager.addWaypoint(Waypoint.manual(
          name: 'Test',
          latitude: 37.7749,
          longitude: -122.4194,
          order: 0,
        ));

        manager.removeWaypoint(wp.id);

        expect(callCount, 2); // Once for add, once for remove
      });

      test('onWaypointsChanged callback is triggered on update', () {
        int callCount = 0;
        manager.onWaypointsChanged = (_) {
          callCount++;
        };

        final wp = manager.addWaypoint(Waypoint.manual(
          name: 'Test',
          latitude: 37.7749,
          longitude: -122.4194,
          order: 0,
        ));

        manager.updateWaypoint(wp.copyWith(estimatedDurationMinutes: 30));

        expect(callCount, 2); // Once for add, once for update
      });

      test('onWaypointsChanged callback is triggered on reorder', () {
        int callCount = 0;
        manager.onWaypointsChanged = (_) {
          callCount++;
        };

        manager.addWaypoint(Waypoint.manual(name: 'Stop 1', latitude: 36.0, longitude: -121.0, order: 0));
        manager.addWaypoint(Waypoint.manual(name: 'Stop 2', latitude: 35.5, longitude: -120.5, order: 0));

        manager.reorderWaypoint(0, 1);

        expect(callCount, 3); // Two adds + one reorder
      });
    });

    group('Waypoint Progress Calculation', () {
      test('getWaypointProgressData returns correct data for first waypoint', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194, name: 'Start');
        manager.addWaypoint(Waypoint.manual(
          name: 'Shell Gas Station',
          latitude: 37.5,
          longitude: -122.0,
          order: 0,
          estimatedDurationMinutes: 15,
        ));
        manager.addWaypoint(Waypoint.manual(
          name: 'Starbucks',
          latitude: 37.0,
          longitude: -121.5,
          order: 1,
          estimatedDurationMinutes: 10,
        ));
        manager.setDestination(latitude: 34.0522, longitude: -118.2437, name: 'End');

        // Leg 0 = origin → first waypoint (Shell)
        final progressData = manager.getWaypointProgressData(
          legIndex: 0,
          distanceMeters: 1609.34, // 1 mile in meters
          durationSeconds: 300, // 5 minutes
        );

        expect(progressData, isNotNull);
        expect(progressData!['name'], 'Shell Gas Station');
        expect(progressData['distanceMiles'], closeTo(1.0, 0.01));
        expect(progressData['distanceFormatted'], '1.0');
        expect(progressData['etaMinutes'], 5);
        expect(progressData['etaFormatted'], '5 min');
        expect(progressData['stopNumber'], 1);
        expect(progressData['totalStops'], 2);
        expect(progressData['stopIndicator'], 'Stop 1 of 2');
        expect(progressData['shouldShow'], true);
      });

      test('getWaypointProgressData returns correct data for second waypoint', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194, name: 'Start');
        manager.addWaypoint(Waypoint.manual(name: 'Stop 1', latitude: 37.5, longitude: -122.0, order: 0));
        manager.addWaypoint(Waypoint.manual(name: 'Stop 2', latitude: 37.0, longitude: -121.5, order: 1));
        manager.addWaypoint(Waypoint.manual(name: 'Stop 3', latitude: 36.5, longitude: -121.0, order: 2));
        manager.setDestination(latitude: 34.0522, longitude: -118.2437, name: 'End');

        // Leg 1 = first waypoint → second waypoint
        final progressData = manager.getWaypointProgressData(
          legIndex: 1,
          distanceMeters: 8046.72, // 5 miles
          durationSeconds: 600, // 10 minutes
        );

        expect(progressData, isNotNull);
        expect(progressData!['name'], 'Stop 2');
        expect(progressData['distanceMiles'], closeTo(5.0, 0.01));
        expect(progressData['etaMinutes'], 10);
        expect(progressData['stopNumber'], 2);
        expect(progressData['totalStops'], 3);
        expect(progressData['stopIndicator'], 'Stop 2 of 3');
      });

      test('getWaypointProgressData returns null for final destination leg', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194, name: 'Start');
        manager.addWaypoint(Waypoint.manual(name: 'Stop 1', latitude: 37.5, longitude: -122.0, order: 0));
        manager.setDestination(latitude: 34.0522, longitude: -118.2437, name: 'End');

        // Leg 1 = last waypoint → destination (should hide card)
        final progressData = manager.getWaypointProgressData(
          legIndex: 1,
          distanceMeters: 5000,
          durationSeconds: 300,
        );

        expect(progressData, isNull);
      });

      test('getWaypointProgressData returns null when no intermediate waypoints', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194, name: 'Start');
        manager.setDestination(latitude: 34.0522, longitude: -118.2437, name: 'End');

        final progressData = manager.getWaypointProgressData(
          legIndex: 0,
          distanceMeters: 5000,
          durationSeconds: 300,
        );

        expect(progressData, isNull);
      });

      test('getWaypointProgressData handles invalid leg index', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194, name: 'Start');
        manager.addWaypoint(Waypoint.manual(name: 'Stop 1', latitude: 37.5, longitude: -122.0, order: 0));
        manager.setDestination(latitude: 34.0522, longitude: -118.2437, name: 'End');

        // Leg index out of range
        final progressData = manager.getWaypointProgressData(
          legIndex: 5,
          distanceMeters: 5000,
          durationSeconds: 300,
        );

        expect(progressData, isNull);
      });

      test('getWaypointProgressData converts units correctly', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194, name: 'Start');
        manager.addWaypoint(Waypoint.manual(name: 'Stop', latitude: 37.5, longitude: -122.0, order: 0));
        manager.setDestination(latitude: 34.0522, longitude: -118.2437, name: 'End');

        // Test meters to miles conversion: 10,000 meters = 6.21371 miles
        final progressData = manager.getWaypointProgressData(
          legIndex: 0,
          distanceMeters: 10000.0,
          durationSeconds: 900, // 15 minutes
        );

        expect(progressData, isNotNull);
        expect(progressData!['distanceMiles'], closeTo(6.21371, 0.01));
        expect(progressData['distanceFormatted'], '6.2'); // Formatted to 1 decimal
        expect(progressData['etaMinutes'], 15);
        expect(progressData['etaFormatted'], '15 min');
      });

      test('getWaypointProgressData rounds ETA correctly', () {
        manager.setOrigin(latitude: 37.7749, longitude: -122.4194, name: 'Start');
        manager.addWaypoint(Waypoint.manual(name: 'Stop', latitude: 37.5, longitude: -122.0, order: 0));
        manager.setDestination(latitude: 34.0522, longitude: -118.2437, name: 'End');

        // Test rounding: 125 seconds = 2.083 minutes → rounds to 2
        var progressData = manager.getWaypointProgressData(
          legIndex: 0,
          distanceMeters: 1000,
          durationSeconds: 125,
        );
        expect(progressData!['etaMinutes'], 2);

        // Test rounding: 155 seconds = 2.583 minutes → rounds to 3
        progressData = manager.getWaypointProgressData(
          legIndex: 0,
          distanceMeters: 1000,
          durationSeconds: 155,
        );
        expect(progressData!['etaMinutes'], 3);
      });
    });
  });
}
