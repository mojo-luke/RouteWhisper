import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/services/navigation_controller.dart';
import 'package:frontend/services/navigation_service.dart';
import 'package:frontend/services/recommendation_service.dart';

/// Tests [RecommendationService.poll] both negatively (guards that
/// prevent a request from firing) and positively (the wire shape of
/// the request body that DOES fire). The positive path uses
/// `NavigationController.setStateForTesting` to drive
/// `NavigationService.isNavigating == true` without a real bridge.
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

  group('RecommendationService request body shape', () {
    // Reset the static navigation state after each test so navigating
    // state doesn't leak into the negative-gate tests above.
    tearDown(() {
      NavigationService.controller
          .setStateForTesting(NavigationState.idle);
    });

    /// Drives the static singleton into a "ready to send" state, fires
    /// poll() against a capturing MockClient, and returns the decoded
    /// JSON body. Centralized so individual test cases focus on the
    /// shape assertions, not setup.
    Future<Map<String, dynamic>> capturePollBody({
      bool force = false,
      int? remainingBudget,
      String polyline = 'test_polyline_abc',
    }) async {
      Map<String, dynamic>? captured;
      final client = MockClient((http.Request req) async {
        captured = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'suggestions': []}), 200);
      });
      final service = RecommendationService(
        httpClient: client,
        tokenProvider: () => 'test-token',
      );

      NavigationService.setRoutePolyline(polyline);
      NavigationService.waypointManager.setTripBudget(remainingBudget);
      NavigationService.controller
          .setStateForTesting(NavigationState.navigating);

      if (force) {
        await service.forcePoll();
      } else {
        await service.poll();
      }
      return captured ?? <String, dynamic>{};
    }

    test('body has the {context, intent} envelope', () async {
      final body = await capturePollBody();
      expect(body.keys.toSet(), {'context', 'intent'});
    });

    test('context carries the route polyline', () async {
      final body = await capturePollBody(polyline: 'specific_polyline_xyz');
      final context = body['context'] as Map<String, dynamic>;
      expect(context['route_polyline'], 'specific_polyline_xyz');
    });

    test('context carries time_budget_mode (defaults to moderate)', () async {
      final body = await capturePollBody();
      final context = body['context'] as Map<String, dynamic>;
      expect(context['time_budget_mode'], 'moderate');
    });

    test('context includes minutes_remaining when a budget is set',
        () async {
      // Setting tripBudgetMinutes to 60 + zero used = 60 minutes
      // remaining. The service should pass that to the backend.
      final body = await capturePollBody(remainingBudget: 60);
      final context = body['context'] as Map<String, dynamic>;
      expect(context['minutes_remaining'], 60);
    });

    test('context omits minutes_remaining when no budget is set',
        () async {
      final body = await capturePollBody();
      final context = body['context'] as Map<String, dynamic>;
      expect(context.containsKey('minutes_remaining'), isFalse);
    });

    test('auto poll sends intent.invocation == auto', () async {
      final body = await capturePollBody(force: false);
      final intent = body['intent'] as Map<String, dynamic>;
      expect(intent['invocation'], 'auto');
    });

    test('forcePoll sends intent.invocation == manual', () async {
      final body = await capturePollBody(force: true);
      final intent = body['intent'] as Map<String, dynamic>;
      expect(intent['invocation'], 'manual');
    });

    test('Authorization header carries the bearer token', () async {
      String? capturedAuth;
      final client = MockClient((http.Request req) async {
        capturedAuth = req.headers['Authorization'];
        return http.Response(jsonEncode({'suggestions': []}), 200);
      });
      final service = RecommendationService(
        httpClient: client,
        tokenProvider: () => 'opaque-jwt-here',
      );
      NavigationService.setRoutePolyline('polyline');
      NavigationService.controller
          .setStateForTesting(NavigationState.navigating);
      await service.poll();

      expect(capturedAuth, 'Bearer opaque-jwt-here');
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
