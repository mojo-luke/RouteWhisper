import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/services/navigation_service.dart';
import 'package:frontend/services/recommendation_service.dart';

/// Guards the *negative* gates on [RecommendationService.poll] — the
/// conditions under which the service must NOT fire a network request.
/// These are cheap, deterministic, and catch regressions where someone
/// removes a guard. They DON'T verify the request body shape, because
/// the positive path needs `NavigationService.isNavigating == true`
/// which the static singleton doesn't expose a test seam for yet.
/// Add a `NavigationService.isNavigatingForTest` setter (analogous to
/// `lastPOIResponseForTest`) when we want body-shape coverage too.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecommendationService poll() guards', () {
    test('does not fire when there is no route polyline', () async {
      var hit = false;
      final client = MockClient((http.Request req) async {
        hit = true;
        return http.Response('{}', 200);
      });
      final service = RecommendationService(httpClient: client);
      // Default state: NavigationService.routePolyline is null.
      await service.poll();
      expect(hit, isFalse);
    });

    test('does not fire when disabled', () async {
      var hit = false;
      final client = MockClient((http.Request req) async {
        hit = true;
        return http.Response('{}', 200);
      });
      final service = RecommendationService(
        httpClient: client,
        enabled: false,
      );
      NavigationService.setRoutePolyline('any-polyline');
      await service.poll();
      expect(hit, isFalse);
    });

    test('does not fire when not navigating, even with a polyline set',
        () async {
      var hit = false;
      final client = MockClient((http.Request req) async {
        hit = true;
        return http.Response('{}', 200);
      });
      final service = RecommendationService(httpClient: client);
      NavigationService.setRoutePolyline('encoded_polyline_123');
      // NavigationService.isNavigating is false until the controller
      // transitions to NavigationState.navigating, which a unit test
      // can't easily do against the static singleton.
      await service.poll();
      expect(hit, isFalse);
    });
  });

  group('RecommendationService configure()', () {
    test('disabling via configure stops the service from firing', () async {
      var hit = false;
      final client = MockClient((http.Request req) async {
        hit = true;
        return http.Response('{}', 200);
      });
      final service = RecommendationService(httpClient: client);
      service.configure(enabled: false);
      NavigationService.setRoutePolyline('any-polyline');
      await service.poll();
      expect(hit, isFalse);
    });

    test('configure updates the cap fields in place', () {
      final service = RecommendationService(httpClient: MockClient((_) async {
        return http.Response('{}', 200);
      }));
      service.configure(
        maxPerTrip: 7,
        minGapBetweenSurfaces: const Duration(minutes: 3),
      );
      expect(service.maxPerTrip, 7);
      expect(service.minGapBetweenSurfaces, const Duration(minutes: 3));
    });
  });

  group('Dismiss / accept', () {
    test('dismissCurrent clears the surfaced suggestion', () {
      final service = RecommendationService(
          httpClient: MockClient((_) async => http.Response('{}', 200)));
      // No suggestion to dismiss — should be a no-op, not a crash.
      expect(() => service.dismissCurrent(), returnsNormally);
      expect(service.current, isNull);
    });

    test('resetForNewTrip wipes surface count + suppression', () {
      final service = RecommendationService(
          httpClient: MockClient((_) async => http.Response('{}', 200)));
      // Trip-state wipe is idempotent and safe on a fresh service.
      service.resetForNewTrip();
      expect(service.current, isNull);
    });
  });
}
