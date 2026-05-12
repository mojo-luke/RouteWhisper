import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/route_fact.dart';
import 'package:frontend/services/narration_service.dart';

import 'fake_navigation_host_bridge.dart';

/// Tests pin the Phase 1 whisper trigger contract:
///   - facts load on startTrip
///   - a fact fires when within proximityMiles AND spacing OK
///   - spacing rule blocks back-to-back narrations
///   - high speed silences narration
///   - same fact never fires twice (queue removal on fire)
///   - tellMeMore walks follow_ups in order
///   - canTellMore false when exhausted or is_thin
void main() {
  late FakeNavigationHostBridge bridge;
  late NarrationService service;
  late DateTime fakeNow;

  setUp(() {
    bridge = FakeNavigationHostBridge();
    // Register a no-op handler bag so we don't crash on bridge events
    // — narration tests don't go through the inbound side.
    fakeNow = DateTime(2026, 1, 1, 12);
    service = NarrationService(
      bridge: bridge,
      fetcher: (_) async => _twoFacts(),
      now: () => fakeNow,
    );
  });

  test('startTrip loads facts and notifies listeners', () async {
    var notified = 0;
    service.addListener(() => notified++);
    await service.startTrip('encoded_polyline_abc');
    expect(service.hasLoadedFacts, isTrue);
    expect(service.current, isNull); // not yet fired
    expect(notified, greaterThan(0));
  });

  test('location update inside proximity fires the nearest fact', () async {
    await service.startTrip('p');
    // SF coords, where fact[0] sits.
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 45.0,
    );
    expect(service.current, isNotNull);
    expect(service.current!.fact.articleTitle, 'San Francisco');
    expect(bridge.callsTo('speakNarration'), hasLength(1));
    expect(bridge.lastCall!.args['text'], contains('San Francisco'));
  });

  test('location update outside proximity does not fire', () async {
    await service.startTrip('p');
    // Far from any fact (LA-ish).
    service.onLocationUpdate(
      latitude: 34.0522,
      longitude: -118.2437,
      speedMph: 45.0,
    );
    expect(service.current, isNull);
    expect(bridge.callsTo('speakNarration'), isEmpty);
  });

  test('speed above maxSpeedMph silences narration', () async {
    await service.startTrip('p');
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 85.0, // way over 70
    );
    expect(service.current, isNull);
    expect(bridge.callsTo('speakNarration'), isEmpty);
  });

  test('spacing rule blocks back-to-back narrations', () async {
    await service.startTrip('p');
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    expect(bridge.callsTo('speakNarration'), hasLength(1));

    // Advance time by less than minSpacing — even at the second fact's
    // coordinates, no fire should happen.
    fakeNow = fakeNow.add(const Duration(seconds: 10));
    service.onLocationUpdate(
      latitude: 37.8024,
      longitude: -122.4058, // Coit Tower
      speedMph: 30.0,
    );
    expect(bridge.callsTo('speakNarration'), hasLength(1));
  });

  test('after spacing elapses a new fact can fire', () async {
    await service.startTrip('p');
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    // Past min spacing
    fakeNow = fakeNow.add(const Duration(seconds: 40));
    service.onLocationUpdate(
      latitude: 37.8024,
      longitude: -122.4058,
      speedMph: 30.0,
    );
    expect(bridge.callsTo('speakNarration'), hasLength(2));
    expect(service.current!.fact.articleTitle, 'Coit Tower');
  });

  test('a fact does not fire twice (removed from queue on fire)', () async {
    await service.startTrip('p');
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    expect(bridge.callsTo('speakNarration'), hasLength(1));

    fakeNow = fakeNow.add(const Duration(seconds: 60));
    // Stay at the same spot. The first fact is gone; the only
    // remaining fact (Coit Tower at 0.3mi away) might or might not
    // be in proximity depending on the exact distance, but it
    // should NOT be the first one again.
    final preCalls = bridge.callsTo('speakNarration').length;
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    final postCalls = bridge.callsTo('speakNarration');
    // San Francisco fact does not fire a second time.
    for (final call in postCalls.skip(preCalls)) {
      expect(call.args['text'], isNot(contains('San Francisco')));
    }
  });

  test('tellMeMore walks follow_ups in order then signals exhaustion',
      () async {
    await service.startTrip('p');
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    // First fact has 2 follow-ups; we should walk them in order
    expect(service.canTellMore, isTrue);

    final advanced1 = service.tellMeMore();
    expect(advanced1, isTrue);
    expect(bridge.callsTo('speakNarration'), hasLength(2));
    expect(bridge.lastCall!.args['text'], contains('Gold Rush'));

    final advanced2 = service.tellMeMore();
    expect(advanced2, isTrue);
    expect(bridge.callsTo('speakNarration'), hasLength(3));
    expect(bridge.lastCall!.args['text'], contains('cable car'));

    // Exhausted
    final advanced3 = service.tellMeMore();
    expect(advanced3, isFalse);
    expect(service.canTellMore, isFalse);
    expect(bridge.callsTo('speakNarration'), hasLength(3));
  });

  test('thin facts disable tellMeMore even with follow-ups present',
      () async {
    // Even if the LLM somehow returned follow_ups alongside
    // is_thin=true, the UI should refuse to advance. is_thin is a
    // promise to the user.
    final fact = RouteFact(
      lat: 37.7749,
      lng: -122.4194,
      articleTitle: 'Thin Place',
      articleUrl: 'https://en.wikipedia.org/?curid=999',
      wikipediaPageid: 999,
      primary: 'A small thing.',
      followUps: ['this should not be reachable'],
      isThin: true,
      distanceFromRouteMiles: 0.1,
      rankedScore: 0.5,
    );
    service = NarrationService(
      bridge: bridge,
      fetcher: (_) async => [fact],
      now: () => fakeNow,
    );
    await service.startTrip('p');
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    expect(service.canTellMore, isFalse);
    expect(service.tellMeMore(), isFalse);
  });

  test('replay re-speaks the current narration regardless of spacing',
      () async {
    await service.startTrip('p');
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    expect(bridge.callsTo('speakNarration'), hasLength(1));
    service.replay();
    expect(bridge.callsTo('speakNarration'), hasLength(2));
  });

  test('endTrip clears queue and current narration', () async {
    await service.startTrip('p');
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    expect(service.current, isNotNull);
    service.endTrip();
    expect(service.current, isNull);
    expect(service.hasLoadedFacts, isFalse);
  });
}

/// Two-fact fixture: San Francisco (with 2 follow-ups) and Coit Tower
/// (thin). Coords are real; both will be in proximity from a query
/// at SF's center.
List<RouteFact> _twoFacts() => [
      RouteFact(
        lat: 37.7749,
        lng: -122.4194,
        articleTitle: 'San Francisco',
        articleUrl: 'https://en.wikipedia.org/?curid=49728',
        wikipediaPageid: 49728,
        primary: 'San Francisco was built on Gold Rush dreams and has the steepest streets you can legally drive.',
        followUps: [
          'The Gold Rush turned a tiny mission settlement into a global port in under five years.',
          'The cable car system is the only one of its kind still running — and a National Historic Landmark.',
        ],
        isThin: false,
        distanceFromRouteMiles: 0.1,
        rankedScore: 0.92,
      ),
      RouteFact(
        lat: 37.8024,
        lng: -122.4058,
        articleTitle: 'Coit Tower',
        articleUrl: 'https://en.wikipedia.org/?curid=523456',
        wikipediaPageid: 523456,
        primary: 'Coit Tower is an Art Deco tower on Telegraph Hill, built in 1933 as a memorial to volunteer firefighters.',
        followUps: [],
        isThin: true,
        distanceFromRouteMiles: 0.2,
        rankedScore: 0.85,
      ),
    ];
