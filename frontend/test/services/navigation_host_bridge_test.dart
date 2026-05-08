import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/navigation_host_bridge.dart';

/// Verifies the bridge contract: every method-channel call name the native
/// host might send/receive routes through the right [NavigationHostHandlers]
/// field with the right typed args. This catches "added a method on one side,
/// forgot the other" bridge drift — the most common bug class in hybrid apps.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelNavigationHostBridge', () {
    late MethodChannel channel;
    late MethodChannelNavigationHostBridge bridge;

    // Captured invocations from the "native" side (we play the native role).
    final outboundCalls = <MethodCall>[];

    setUp(() {
      outboundCalls.clear();
      channel = MethodChannel(
        '${MethodChannelNavigationHostBridge.channelName}.test',
      );
      bridge = MethodChannelNavigationHostBridge(channel: channel);

      // Capture outbound (Flutter→native) calls.
      TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        outboundCalls.add(call);
        return 'ok';
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    // --- Outbound (Flutter → Native) ---

    test('calculateRoute sends correct method and payload', () async {
      final result = await bridge.calculateRoute(
        originLat: 1.0,
        originLng: 2.0,
        destLat: 3.0,
        destLng: 4.0,
        waypoints: [
          [5.0, 6.0]
        ],
        waypointNames: ['Stop A'],
      );
      expect(result, 'ok');
      expect(outboundCalls, hasLength(1));
      expect(outboundCalls.single.method, 'calculateRoute');
      expect(outboundCalls.single.arguments, {
        'originLat': 1.0,
        'originLng': 2.0,
        'destLat': 3.0,
        'destLng': 4.0,
        'waypoints': [
          [5.0, 6.0]
        ],
        'waypointNames': ['Stop A'],
      });
    });

    test('calculateRoute omits waypoint keys when none provided', () async {
      await bridge.calculateRoute(
        originLat: 1, originLng: 2, destLat: 3, destLng: 4,
      );
      expect(outboundCalls.single.arguments,
          isNot(contains('waypoints')));
      expect(outboundCalls.single.arguments,
          isNot(contains('waypointNames')));
    });

    test('updateNavigationRoute sends correct method', () async {
      await bridge.updateNavigationRoute(
        originLat: 1, originLng: 2, destLat: 3, destLng: 4,
      );
      expect(outboundCalls.single.method, 'updateNavigationRoute');
    });

    test('cancelNavigation sends correct method', () async {
      await bridge.cancelNavigation();
      expect(outboundCalls.single.method, 'cancelNavigation');
    });

    test('openMapView sends correct method', () async {
      await bridge.openMapView();
      expect(outboundCalls.single.method, 'openMapView');
    });

    test('showPoisOnMap sends correct method and payload', () async {
      await bridge.showPoisOnMap(
        pois: [
          {'id': 'p1', 'lat': 37.7, 'lng': -122.4, 'category': 'restaurant'},
        ],
        bounds: [-122.5, 37.6, -122.3, 37.8],
      );
      expect(outboundCalls.single.method, 'showPoisOnMap');
      expect(outboundCalls.single.arguments, {
        'pois': [
          {'id': 'p1', 'lat': 37.7, 'lng': -122.4, 'category': 'restaurant'},
        ],
        'bounds': [-122.5, 37.6, -122.3, 37.8],
      });
    });

    test('clearPoisFromMap sends correct method', () async {
      await bridge.clearPoisFromMap();
      expect(outboundCalls.single.method, 'clearPoisFromMap');
    });

    test('hideOverlay sends correct method', () async {
      await bridge.hideOverlay();
      expect(outboundCalls.single.method, 'hideOverlay');
    });

    // --- Inbound (Native → Flutter) ---

    test('inbound dispatch routes every documented event', () async {
      final received = <String, Object?>{};

      bridge.setHandlers(NavigationHostHandlers(
        onRoutePolyline: (polyline) =>
            received['routePolyline'] = polyline,
        onWaypointArrived: ({
          required legIndex,
          required latitude,
          required longitude,
        }) =>
            received['waypointArrived'] = [legIndex, latitude, longitude],
        onAutoDeparture: ({
          required distanceMeters,
          required speedMph,
        }) =>
            received['autoDeparture'] = [distanceMeters, speedMph],
        onDestinationArrived: () => received['destinationArrived'] = true,
        onShowOverlay: (route) => received['showOverlay'] = route,
        onPopRoute: () => received['popRoute'] = true,
        onRequestPoisOnMap: () => received['requestPoisOnMap'] = true,
        onPoiTapped: (poiId) => received['poiTapped'] = poiId,
        onWaypointProgressRequest: ({
          required legIndex,
          required distanceMeters,
          required durationSeconds,
        }) {
          received['waypointProgressRequest'] = [
            legIndex,
            distanceMeters,
            durationSeconds,
          ];
          return {'name': 'Test', 'distanceFormatted': '1.0'};
        },
      ));

      // Send each native→Flutter call through the channel and verify
      // the matching handler fires.
      Future<Object?> simulateNative(String method, Object? args) async {
        return TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger
            .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall(method, args)),
          null,
        ).then((bytes) =>
            bytes == null ? null : channel.codec.decodeEnvelope(bytes));
      }

      await simulateNative('setRoutePolyline', {'polyline': 'abc'});
      expect(received['routePolyline'], 'abc');

      await simulateNative('waypointArrived', {
        'legIndex': 2,
        'latitude': 37.7,
        'longitude': -122.4,
      });
      expect(received['waypointArrived'], [2, 37.7, -122.4]);

      await simulateNative('autoDepartureDetected', {
        'distance': 60.0,
        'speed': 7.5,
      });
      expect(received['autoDeparture'], [60.0, 7.5]);

      await simulateNative('destinationArrived', null);
      expect(received['destinationArrived'], true);

      await simulateNative('showOverlay', {'route': '/poi-discovery'});
      expect(received['showOverlay'], '/poi-discovery');

      await simulateNative('popRoute', null);
      expect(received['popRoute'], true);

      await simulateNative('requestPoisOnMap', null);
      expect(received['requestPoisOnMap'], true);

      await simulateNative('poiTapped', {'poiId': 'poi_42'});
      expect(received['poiTapped'], 'poi_42');

      final progress = await simulateNative('calculateWaypointProgress', {
        'legIndex': 0,
        'distanceMeters': 1000.0,
        'durationSeconds': 60.0,
      });
      expect(received['waypointProgressRequest'], [0, 1000.0, 60.0]);
      expect(progress, {'name': 'Test', 'distanceFormatted': '1.0'});
    });

    test('unknown inbound method does not crash and returns null', () async {
      bridge.setHandlers(_throwingHandlers());
      final envelope = await TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec
            .encodeMethodCall(const MethodCall('mysteryMethod', null)),
        null,
      );
      // Envelope is non-null (it's the encoded reply); the decoded payload is null.
      expect(envelope, isNotNull);
      expect(channel.codec.decodeEnvelope(envelope!), isNull);
    });
  });
}

NavigationHostHandlers _throwingHandlers() => NavigationHostHandlers(
      onRoutePolyline: (_) => throw StateError('should not fire'),
      onWaypointArrived: ({
        required legIndex,
        required latitude,
        required longitude,
      }) =>
          throw StateError('should not fire'),
      onAutoDeparture: ({
        required distanceMeters,
        required speedMph,
      }) =>
          throw StateError('should not fire'),
      onDestinationArrived: () => throw StateError('should not fire'),
      onShowOverlay: (_) => throw StateError('should not fire'),
      onPopRoute: () => throw StateError('should not fire'),
      onRequestPoisOnMap: () => throw StateError('should not fire'),
      onPoiTapped: (_) => throw StateError('should not fire'),
      onWaypointProgressRequest: ({
        required legIndex,
        required distanceMeters,
        required durationSeconds,
      }) =>
          throw StateError('should not fire'),
    );
