import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/route_fact.dart';
import 'package:frontend/models/route_monologue.dart';
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
    // fact[0] has primaryAudioUrl → uses MediaPlayer path, not TTS.
    expect(bridge.callsTo('playNarrationAudio'), hasLength(1));
    expect(bridge.callsTo('speakNarration'), isEmpty);
    expect(bridge.callsTo('playNarrationAudio').last.args['url'],
        '/api/v1/audio/wiki-49728-primary');
  });

  test('fact without audio_url falls back to local TTS', () async {
    // Build a fact list where the primary line has no audio URL —
    // the device should fall back to speakNarration on the text.
    final factsNoAudio = [
      RouteFact(
        lat: 37.7749,
        lng: -122.4194,
        articleTitle: 'No Audio Place',
        articleUrl: 'https://en.wikipedia.org/?curid=1',
        wikipediaPageid: 1,
        primary: 'A place with no audio.',
        primaryAudioUrl: null,
        followUps: const [],
        followUpAudioUrls: const [],
        isThin: true,
        distanceFromRouteMiles: 0.1,
        rankedScore: 0.5,
      ),
    ];
    service = NarrationService(
      bridge: bridge,
      fetcher: (_) async => factsNoAudio,
      now: () => fakeNow,
    );
    await service.startTrip('p');
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    expect(bridge.callsTo('speakNarration'), hasLength(1));
    expect(bridge.callsTo('playNarrationAudio'), isEmpty);
    expect(bridge.callsTo('speakNarration').last.args['text'],
        contains('no audio'));
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
    expect(bridge.callsTo('playNarrationAudio'), isEmpty);
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
    expect(bridge.callsTo('playNarrationAudio'), isEmpty);
  });

  test('spacing rule blocks back-to-back narrations', () async {
    await service.startTrip('p');
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    expect(bridge.callsTo('playNarrationAudio'), hasLength(1));

    // Advance time by less than minSpacing — even at the second fact's
    // coordinates, no fire should happen.
    fakeNow = fakeNow.add(const Duration(seconds: 10));
    service.onLocationUpdate(
      latitude: 37.8024,
      longitude: -122.4058, // Coit Tower
      speedMph: 30.0,
    );
    expect(bridge.callsTo('playNarrationAudio'), hasLength(1));
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
    expect(bridge.callsTo('playNarrationAudio'), hasLength(2));
    expect(service.current!.fact.articleTitle, 'Coit Tower');
  });

  test('a fact does not fire twice (removed from queue on fire)', () async {
    await service.startTrip('p');
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    expect(bridge.callsTo('playNarrationAudio'), hasLength(1));

    fakeNow = fakeNow.add(const Duration(seconds: 60));
    // Stay at the same spot. The first fact is gone; the only
    // remaining fact (Coit Tower at 0.3mi away) might or might not
    // be in proximity depending on the exact distance, but it
    // should NOT be the first one again.
    final firstUrl = bridge.callsTo('playNarrationAudio').first.args['url'];
    final preCount = bridge.callsTo('playNarrationAudio').length;
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    // San Francisco fact does not fire a second time.
    for (final call in bridge.callsTo('playNarrationAudio').skip(preCount)) {
      expect(call.args['url'], isNot(equals(firstUrl)));
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
    expect(bridge.callsTo('playNarrationAudio'), hasLength(2));
    expect(bridge.lastCall!.args['url'],
        '/api/v1/audio/wiki-49728-fu-0');

    final advanced2 = service.tellMeMore();
    expect(advanced2, isTrue);
    expect(bridge.callsTo('playNarrationAudio'), hasLength(3));
    expect(bridge.lastCall!.args['url'],
        '/api/v1/audio/wiki-49728-fu-1');

    // Exhausted
    final advanced3 = service.tellMeMore();
    expect(advanced3, isFalse);
    expect(service.canTellMore, isFalse);
    expect(bridge.callsTo('playNarrationAudio'), hasLength(3));
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

  test('replay re-plays the current narration regardless of spacing',
      () async {
    await service.startTrip('p');
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    expect(bridge.callsTo('playNarrationAudio'), hasLength(1));
    service.replay();
    expect(bridge.callsTo('playNarrationAudio'), hasLength(2));
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

  // --- Map markers ---

  test('firing a narration adds a marker and promotes it to active',
      () async {
    await service.startTrip('p');
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );

    final addCalls = bridge.callsTo('addNarrationMarker');
    expect(addCalls, hasLength(1));
    expect(addCalls.first.args['id'], 'wiki-49728');
    expect(addCalls.first.args['title'], 'San Francisco');
    expect(addCalls.first.args['lat'], 37.7749);
    expect(addCalls.first.args['lng'], -122.4194);

    final activeCalls = bridge.callsTo('setActiveNarrationMarker');
    expect(activeCalls, hasLength(1));
    expect(activeCalls.first.args['id'], 'wiki-49728');
  });

  test('successive whispers each drop a new marker (persistent trail)',
      () async {
    await service.startTrip('p');
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    fakeNow = fakeNow.add(const Duration(seconds: 40));
    service.onLocationUpdate(
      latitude: 37.8024,
      longitude: -122.4058,
      speedMph: 30.0,
    );
    expect(bridge.callsTo('addNarrationMarker'), hasLength(2));
    // Most recent one is now active.
    final activeCalls = bridge.callsTo('setActiveNarrationMarker');
    expect(activeCalls.last.args['id'], 'wiki-523456');
  });

  test('endTrip clears all narration markers from the map', () async {
    await service.startTrip('p');
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    expect(bridge.callsTo('addNarrationMarker'), hasLength(1));
    service.endTrip();
    expect(bridge.callsTo('clearNarrationMarkers'), hasLength(1));
  });

  // --- Monologue track (Slice E) ---

  test('monologue: utterance fires when entering its anchor town',
      () async {
    final service = NarrationService(
      bridge: bridge,
      fetcher: (_) async => const [],
      monologueFetcher: (_) async => _twoTownMonologue(),
      now: () => fakeNow,
    );
    await service.startTrip('p', tripId: 'trip-1');

    // First location update — SF (37.7749, -122.4194) — should fire
    // utterance 1 ("@ San Francisco").
    service.onLocationUpdate(
      latitude: 37.7749,
      longitude: -122.4194,
      speedMph: 30.0,
    );
    final played = bridge.callsTo('playNarrationAudio');
    expect(played, hasLength(1));
    expect(played.last.args['url'], '/api/v1/audio/monologue/sf-utt');
  });

  test('monologue: fires strictly in author order across moves',
      () async {
    final service = NarrationService(
      bridge: bridge,
      fetcher: (_) async => const [],
      monologueFetcher: (_) async => _twoTownMonologue(),
      now: () => fakeNow,
    );
    await service.startTrip('p', tripId: 'trip-1');

    // Enter SF — utt 1 fires.
    service.onLocationUpdate(
      latitude: 37.7749, longitude: -122.4194, speedMph: 30.0,
    );
    expect(bridge.callsTo('playNarrationAudio'), hasLength(1));

    // Same GPS, but 30s+ later — should NOT re-fire (utt 2 is anchored
    // to a different town).
    fakeNow = fakeNow.add(const Duration(seconds: 31));
    service.onLocationUpdate(
      latitude: 37.7749, longitude: -122.4194, speedMph: 30.0,
    );
    expect(bridge.callsTo('playNarrationAudio'), hasLength(1));

    // Move to Tahoe — utt 2 fires.
    service.onLocationUpdate(
      latitude: 38.9399, longitude: -119.9772, speedMph: 30.0,
    );
    final played = bridge.callsTo('playNarrationAudio');
    expect(played, hasLength(2));
    expect(played.last.args['url'], '/api/v1/audio/monologue/tahoe-utt');
  });

  test('monologue: 30s spacing rule blocks back-to-back utterances',
      () async {
    final service = NarrationService(
      bridge: bridge,
      fetcher: (_) async => const [],
      monologueFetcher: (_) async => _sameTownTwoUtterances(),
      now: () => fakeNow,
    );
    await service.startTrip('p', tripId: 'trip-1');

    service.onLocationUpdate(
      latitude: 37.7749, longitude: -122.4194, speedMph: 30.0,
    );
    expect(bridge.callsTo('playNarrationAudio'), hasLength(1));

    // 10s later, still in town — utt 2 should NOT fire yet.
    fakeNow = fakeNow.add(const Duration(seconds: 10));
    service.onLocationUpdate(
      latitude: 37.7749, longitude: -122.4194, speedMph: 30.0,
    );
    expect(bridge.callsTo('playNarrationAudio'), hasLength(1));

    // 31s after first fire — utt 2 fires.
    fakeNow = fakeNow.add(const Duration(seconds: 21));
    service.onLocationUpdate(
      latitude: 37.7749, longitude: -122.4194, speedMph: 30.0,
    );
    expect(bridge.callsTo('playNarrationAudio'), hasLength(2));
  });

  test('monologue: firing sets currentMonologueUtterance + auto-clears',
      () async {
    final service = NarrationService(
      bridge: bridge,
      fetcher: (_) async => const [],
      monologueFetcher: (_) async => _twoTownMonologue(),
      now: () => fakeNow,
    );
    // Tight clear window so the test doesn't hang waiting on a real
    // 20s timer.
    service.monologueCardDuration = const Duration(milliseconds: 50);
    await service.startTrip('p', tripId: 'trip-1');
    expect(service.currentMonologueUtterance, isNull);
    service.onLocationUpdate(
      latitude: 37.7749, longitude: -122.4194, speedMph: 30.0,
    );
    expect(service.currentMonologueUtterance, isNotNull);
    expect(service.currentMonologueUtterance!.anchor, 'San Francisco');
    // Wait long enough for the auto-clear timer to fire.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(service.currentMonologueUtterance, isNull);
  });

  test('monologue: dismissMonologueCard hides immediately, audio stays',
      () async {
    final service = NarrationService(
      bridge: bridge,
      fetcher: (_) async => const [],
      monologueFetcher: (_) async => _twoTownMonologue(),
      now: () => fakeNow,
    );
    await service.startTrip('p', tripId: 'trip-1');
    service.onLocationUpdate(
      latitude: 37.7749, longitude: -122.4194, speedMph: 30.0,
    );
    expect(service.currentMonologueUtterance, isNotNull);
    expect(bridge.callsTo('playNarrationAudio'), hasLength(1));
    service.dismissMonologueCard();
    expect(service.currentMonologueUtterance, isNull);
    // Audio call count unchanged — we don't stop playback, just hide UI.
    expect(bridge.callsTo('playNarrationAudio'), hasLength(1));
  });

  test('monologue: endTrip clears queue and town centroids', () async {
    final service = NarrationService(
      bridge: bridge,
      fetcher: (_) async => const [],
      monologueFetcher: (_) async => _twoTownMonologue(),
      now: () => fakeNow,
    );
    await service.startTrip('p', tripId: 'trip-1');
    service.endTrip();
    // No anchor town remembered → utterance can't fire.
    service.onLocationUpdate(
      latitude: 37.7749, longitude: -122.4194, speedMph: 30.0,
    );
    expect(bridge.callsTo('playNarrationAudio'), isEmpty);
  });
}


/// Fixture: two utterances, one anchored to SF, one to South Lake Tahoe.
RouteMonologue _twoTownMonologue() => RouteMonologue(
      polylineHash: 'p_hash',
      vibeHash: 'v_hash',
      narrationThemes: const ['history'],
      stopInterests: const [],
      towns: const [
        MonologueTown(name: 'San Francisco', lat: 37.7749, lng: -122.4194),
        MonologueTown(name: 'South Lake Tahoe', lat: 38.9399, lng: -119.9772),
      ],
      characterization: 'A long drive over the Sierra.',
      utterances: const [
        MonologueUtterance(
          i: 1, anchor: 'San Francisco',
          text: 'Leaving SF...',
          audioUrl: '/api/v1/audio/monologue/sf-utt',
        ),
        MonologueUtterance(
          i: 2, anchor: 'South Lake Tahoe',
          text: 'And there it is, the lake.',
          audioUrl: '/api/v1/audio/monologue/tahoe-utt',
        ),
      ],
      stops: const [],
    );


/// Fixture: two utterances both anchored to the same town. Used to
/// verify the 30s spacing rule between successive utterances.
RouteMonologue _sameTownTwoUtterances() => RouteMonologue(
      polylineHash: 'p_hash',
      vibeHash: 'v_hash',
      narrationThemes: const ['history'],
      stopInterests: const [],
      towns: const [
        MonologueTown(name: 'San Francisco', lat: 37.7749, lng: -122.4194),
      ],
      characterization: '',
      utterances: const [
        MonologueUtterance(
          i: 1, anchor: 'San Francisco',
          text: 'First thought.',
          audioUrl: '/api/v1/audio/monologue/utt-1',
        ),
        MonologueUtterance(
          i: 2, anchor: 'San Francisco',
          text: 'Second thought, on the same drive.',
          audioUrl: '/api/v1/audio/monologue/utt-2',
        ),
      ],
      stops: const [],
    );


/// Two-fact fixture: San Francisco (with 2 follow-ups, audio for all)
/// and Coit Tower (thin). Coords are real; both will be in proximity
/// from a query at SF's center.
List<RouteFact> _twoFacts() => [
      RouteFact(
        lat: 37.7749,
        lng: -122.4194,
        articleTitle: 'San Francisco',
        articleUrl: 'https://en.wikipedia.org/?curid=49728',
        wikipediaPageid: 49728,
        primary: 'San Francisco was built on Gold Rush dreams and has the steepest streets you can legally drive.',
        primaryAudioUrl: '/api/v1/audio/wiki-49728-primary',
        followUps: [
          'The Gold Rush turned a tiny mission settlement into a global port in under five years.',
          'The cable car system is the only one of its kind still running — and a National Historic Landmark.',
        ],
        followUpAudioUrls: const [
          '/api/v1/audio/wiki-49728-fu-0',
          '/api/v1/audio/wiki-49728-fu-1',
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
        primaryAudioUrl: '/api/v1/audio/wiki-523456-primary',
        followUps: [],
        followUpAudioUrls: const [],
        isThin: true,
        distanceFromRouteMiles: 0.2,
        rankedScore: 0.85,
      ),
    ];
