import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/waypoint.dart';
import 'package:frontend/services/navigation_controller.dart';
import 'package:frontend/services/navigation_service.dart';
import 'package:frontend/services/poi_api_service.dart';

import 'fake_navigation_host_bridge.dart';

/// Tests NavigationController against a FakeNavigationHostBridge.
///
/// Covers every outbound command (recorded into fake.sentCalls) and every
/// inbound event handler that doesn't require a Flutter widget tree.
///
/// Out of scope here: the showOverlay / popRoute handlers, both of which
/// drive Flutter Navigator state and need a widget test, not a unit test.
void main() {
  group('NavigationController against FakeNavigationHostBridge', () {
    late FakeNavigationHostBridge fake;
    late NavigationController controller;

    setUp(() {
      fake = FakeNavigationHostBridge();
      controller = NavigationController(bridge: fake);
      controller.initialize();

      // NavigationService is a static singleton — reset its waypoint state
      // between tests so no cross-test leakage.
      NavigationService.waypointManager.clearIntermediateWaypoints();
      if (NavigationService.activeWaypoint != null) {
        NavigationService.skipCurrentWaypoint();
      }
    });

    group('initialization', () {
      test('initialize registers handlers on the bridge', () {
        expect(fake.handlers, isNotNull);
      });
    });

    group('outbound: calculateRoute', () {
      test('records call and transitions idle → calculating → navigating',
          () async {
        expect(controller.currentState, NavigationState.idle);

        final states = <NavigationState>[];
        controller.addListener(() => states.add(controller.currentState));

        final result = await controller.calculateRoute(
          originLat: 1.0,
          originLng: 2.0,
          destLat: 3.0,
          destLng: 4.0,
        );

        expect(result, 'ok');
        expect(controller.currentState, NavigationState.navigating);
        expect(states, [
          NavigationState.calculating,
          NavigationState.navigating,
        ]);
        expect(fake.callsTo('calculateRoute'), hasLength(1));
        expect(fake.lastCall!.args, {
          'originLat': 1.0,
          'originLng': 2.0,
          'destLat': 3.0,
          'destLng': 4.0,
        });
      });

      test('includes waypoints and names in payload when provided', () async {
        await controller.calculateRoute(
          originLat: 1.0,
          originLng: 2.0,
          destLat: 3.0,
          destLng: 4.0,
          waypoints: [
            [5.0, 6.0]
          ],
          waypointNames: ['Shell'],
        );

        expect(fake.lastCall!.args['waypoints'], [
          [5.0, 6.0]
        ]);
        expect(fake.lastCall!.args['waypointNames'], ['Shell']);
      });

      test('omits waypoint keys when waypoints list is null or empty',
          () async {
        await controller.calculateRoute(
          originLat: 1.0, originLng: 2.0, destLat: 3.0, destLng: 4.0,
        );

        expect(fake.lastCall!.args.containsKey('waypoints'), isFalse);
        expect(fake.lastCall!.args.containsKey('waypointNames'), isFalse);
      });

      test('returns null and resets to idle when bridge throws', () async {
        fake.calculateRouteError = Exception('native blew up');

        final result = await controller.calculateRoute(
          originLat: 1.0, originLng: 2.0, destLat: 3.0, destLng: 4.0,
        );

        expect(result, isNull);
        expect(controller.currentState, NavigationState.idle);
      });
    });

    group('outbound: updateNavigationRoute', () {
      test('records call without changing state', () async {
        // Get into navigating state first.
        await controller.calculateRoute(
          originLat: 1, originLng: 2, destLat: 3, destLng: 4,
        );
        expect(controller.currentState, NavigationState.navigating);
        fake.clear();

        final result = await controller.updateNavigationRoute(
          originLat: 1,
          originLng: 2,
          destLat: 3,
          destLng: 4,
          waypoints: [
            [7.0, 8.0]
          ],
        );

        expect(result, 'ok');
        expect(controller.currentState, NavigationState.navigating);
        expect(fake.callsTo('updateNavigationRoute'), hasLength(1));
        expect(fake.lastCall!.args['waypoints'], [
          [7.0, 8.0]
        ]);
      });

      test('returns null when bridge throws (does not change state)',
          () async {
        await controller.calculateRoute(
          originLat: 1, originLng: 2, destLat: 3, destLng: 4,
        );
        fake.updateNavigationRouteError = Exception('boom');

        final result = await controller.updateNavigationRoute(
          originLat: 1, originLng: 2, destLat: 3, destLng: 4,
        );

        expect(result, isNull);
        expect(controller.currentState, NavigationState.navigating);
      });
    });

    group('outbound: cancelNavigation', () {
      test('records call, transitions to cancelled then idle after delay',
          () async {
        await controller.cancelNavigation();

        expect(controller.currentState, NavigationState.cancelled);
        expect(fake.callsTo('cancelNavigation'), hasLength(1));

        // Controller schedules a 500ms reset to idle.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(controller.currentState, NavigationState.idle);
      });
    });

    group('outbound: openMapView', () {
      test('records call and returns bridge result', () async {
        final result = await controller.openMapView();

        expect(result, 'ok');
        expect(fake.callsTo('openMapView'), hasLength(1));
      });
    });

    group('inbound: setRoutePolyline', () {
      test('updates NavigationService.routePolyline and notifies listeners',
          () {
        var notifications = 0;
        controller.addListener(() => notifications++);

        fake.emitRoutePolyline('encoded_xyz');

        expect(NavigationService.routePolyline, 'encoded_xyz');
        expect(notifications, greaterThan(0));
      });
    });

    group('inbound: waypointArrived', () {
      test('with valid legIndex marks the matching intermediate waypoint',
          () {
        NavigationService.waypointManager.setOrigin(
          latitude: 0, longitude: 0,
        );
        final stop1 = NavigationService.waypointManager.addWaypoint(
          Waypoint.manual(
              name: 'Stop 1', latitude: 1, longitude: 1, order: 0),
        );
        NavigationService.waypointManager.addWaypoint(
          Waypoint.manual(
              name: 'Stop 2', latitude: 2, longitude: 2, order: 0),
        );
        NavigationService.waypointManager.setDestination(
          latitude: 3, longitude: 3,
        );

        fake.emitWaypointArrived(legIndex: 0, latitude: 1, longitude: 1);

        expect(NavigationService.activeWaypoint?.id, stop1.id);
      });

      test('with out-of-range legIndex is a no-op (no crash)', () {
        NavigationService.waypointManager.setOrigin(
            latitude: 0, longitude: 0);
        NavigationService.waypointManager.setDestination(
            latitude: 3, longitude: 3);

        // No intermediate waypoints — legIndex 5 has no target.
        expect(
          () => fake.emitWaypointArrived(
              legIndex: 5, latitude: 0, longitude: 0),
          returnsNormally,
        );
        expect(NavigationService.activeWaypoint, isNull);
      });
    });

    group('inbound: autoDeparture', () {
      test('with no active waypoint is a no-op', () {
        expect(NavigationService.activeWaypoint, isNull);

        expect(
          () => fake.emitAutoDeparture(distanceMeters: 60, speedMph: 7),
          returnsNormally,
        );
      });

      test('with active waypoint clears active and marks departure', () {
        // Set up an active waypoint via the same path the live app uses.
        NavigationService.waypointManager.setOrigin(
            latitude: 0, longitude: 0);
        final stop = NavigationService.waypointManager.addWaypoint(
          Waypoint.manual(
              name: 'Stop', latitude: 1, longitude: 1, order: 0),
        );
        NavigationService.waypointManager.setDestination(
            latitude: 3, longitude: 3);
        fake.emitWaypointArrived(legIndex: 0, latitude: 1, longitude: 1);
        expect(NavigationService.activeWaypoint?.id, stop.id);

        fake.emitAutoDeparture(distanceMeters: 60, speedMph: 7);

        // markWaypointDeparture clears _activeWaypoint synchronously,
        // before the (awaited) HTTP call to record stop history.
        expect(NavigationService.activeWaypoint, isNull);
      });
    });

    group('inbound: destinationArrived', () {
      test('transitions controller state to completed', () {
        fake.emitDestinationArrived();

        expect(controller.currentState, NavigationState.completed);
      });
    });

    group('inbound: requestPoisOnMap', () {
      test('with cached POIs, pushes them down via bridge.showPoisOnMap',
          () async {
        // Seed the static singleton with a fake POI response. This is the
        // same path the live app populates after a successful fetch.
        final response = POIResponse(
          pois: [
            POI(
              id: 'p1',
              name: 'Test Diner',
              category: 'restaurant',
              latitude: 37.5,
              longitude: -122.4,
              estimatedDurationMinutes: 30,
              distanceFromRouteMiles: 0.4,
            ),
          ],
          totalFound: 1,
          cached: false,
          corridorBounds: [-122.5, 37.4, -122.3, 37.6],
        );
        NavigationService.lastPOIResponseForTest = response;

        fake.emitRequestPoisOnMap();
        await Future<void>.delayed(Duration.zero);

        final shown = fake.callsTo('showPoisOnMap');
        expect(shown, hasLength(1));
        expect(shown.single.args['bounds'],
            [-122.5, 37.4, -122.3, 37.6]);
        final pois = shown.single.args['pois'] as List;
        expect(pois, hasLength(1));
        expect(pois.first, {
          // Bridge id is the array index, not poi.id (the backend currently
          // dups that field across responses).
          'id': '0',
          'lat': 37.5,
          'lng': -122.4,
          'category': 'restaurant',
        });
      });

      test('with no cached POIs and no polyline, does not crash or send',
          () async {
        NavigationService.lastPOIResponseForTest = null;
        // No route polyline, so discoverPOIs() short-circuits to null.
        fake.emitRequestPoisOnMap();
        await Future<void>.delayed(Duration.zero);

        expect(fake.callsTo('showPoisOnMap'), isEmpty);
      });
    });

    group('inbound: waypointProgressRequest', () {
      test('returns formatted progress for an intermediate waypoint', () {
        NavigationService.waypointManager.setOrigin(
            latitude: 0, longitude: 0);
        NavigationService.waypointManager.addWaypoint(
          Waypoint.manual(
              name: 'Stop', latitude: 1, longitude: 1, order: 0),
        );
        NavigationService.waypointManager.setDestination(
            latitude: 3, longitude: 3);

        // 1609.34m ≈ 1 mile, 60s = 1 min — values WaypointManager will
        // format into the result map.
        final progress = fake.emitWaypointProgressRequest(
          legIndex: 0,
          distanceMeters: 1609.34,
          durationSeconds: 60,
        );

        expect(progress, isNotNull);
        expect(progress!['name'], 'Stop');
      });

      test('returns null when there is no waypoint to show', () {
        // No intermediate waypoints — final-leg case.
        final progress = fake.emitWaypointProgressRequest(
          legIndex: 0,
          distanceMeters: 1609.34,
          durationSeconds: 60,
        );

        expect(progress, isNull);
      });
    });
  });
}
