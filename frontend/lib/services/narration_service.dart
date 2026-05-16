import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/route_fact.dart';
import '../models/route_monologue.dart';
import 'monologue_service.dart';
import 'narration_feedback_service.dart';
import 'navigation_host_bridge.dart';
import 'route_facts_service.dart';

/// Phase 1 of the companion product: the Whisper.
///
/// Owns the narration queue for the active trip and decides — on
/// every native location update — whether to whisper, replay, or
/// stay quiet. Spacing rules per `~/.claude/plans/breezy-gliding-
/// mountain.md`:
///   - Min 30s between auto-narrations
///   - Skip if a Mapbox turn-instruction is mid-flight (the native
///     side enforces this — our speakNarration call goes through the
///     same MapboxVoiceInstructionsPlayer that handles turn voice)
///   - Skip if vehicle speed > 70 mph (a maneuver is statistically
///     close; the chatter feels off when you're on the autobahn).
///     Heuristic, easy to tune.
///
/// State is a ChangeNotifier so the narration card overlay can
/// rebuild from `current` and `tellMeMoreCounter` without an
/// external Provider tree change.
class NarrationService extends ChangeNotifier {
  NarrationService({
    NavigationHostBridge? bridge,
    Future<List<RouteFact>> Function(String polyline)? fetcher,
    Future<RouteMonologue?> Function(String tripId)? monologueFetcher,
    DateTime Function()? now,
  })  : _bridge = bridge,
        _fetcher = fetcher ?? RouteFactsService.fetchForRoute,
        _monologueFetcher =
            monologueFetcher ?? MonologueService.fetchForTrip,
        _now = now ?? DateTime.now;

  // Test seams. Production passes nothing and the controller calls
  // `bindBridge` once during initialize() to give us the live bridge.
  NavigationHostBridge? _bridge;
  final Future<List<RouteFact>> Function(String polyline) _fetcher;
  final Future<RouteMonologue?> Function(String tripId) _monologueFetcher;
  final DateTime Function() _now;

  /// Called by NavigationController.initialize() to wire the bridge
  /// after both singletons exist. Idempotent; safe to call again on
  /// hot-restart.
  void bindBridge(NavigationHostBridge bridge) {
    _bridge = bridge;
  }

  /// Callback fired when the user taps "Take me there." NavigationController
  /// installs the implementation (adds a Waypoint to WaypointManager and
  /// calls updateNavigationRoute) so NarrationService doesn't need to
  /// import navigation_service.dart and create a circular dependency.
  void Function(RouteFact fact)? onTakeMeThere;

  /// Returns the active fact's wikipedia_pageid, or null if no card
  /// is currently surfaced. Used by NavigationController when Mapbox
  /// fires a waypoint-arrival event to figure out which fact got
  /// "visited" — we don't currently track which waypoint was added
  /// for which narration, so the heuristic is "the active narration
  /// at arrival time."
  int? get activePageid => _active?.fact.wikipediaPageid;

  /// Narration mode (Auto / Tap-to-hear / Off). Pushed from
  /// UserProfile at trip start; mutates how `_fire` behaves:
  ///
  ///   "auto"        — drop marker + show banner + speak (default)
  ///   "tap_to_hear" — drop marker + show banner, silent. User
  ///                   triggers audio via Replay/banner controls.
  ///   "off"         — short-circuit; no marker, no banner, no
  ///                   audio. The fact still gets removed from the
  ///                   queue so we don't re-evaluate it.
  ///
  /// Empty/unknown values fall back to "auto" defensively.
  String narrationMode = 'auto';

  /// Tuning constants — surfaced as fields so tests can override.
  Duration minSpacing = const Duration(seconds: 30);
  // Fallback for facts without a route-projection (e.g., area
  // prewarmed facts the user encounters off-trip, or older bundles).
  double proximityMiles = 0.31; // ~500m
  double maxSpeedMph = 70.0;
  // Lookahead in seconds of upcoming travel — when a fact's
  // projected route position is this many seconds ahead of the
  // user's current position, fire the whisper. 30s gives the
  // listener time to glance up, spot the place via the map
  // marker (which pulses while we describe it), and reach it
  // before the audio finishes.
  Duration lookaheadDuration = const Duration(seconds: 30);
  // Floor and ceiling on the lookahead window so it stays sensible
  // at low and high speeds.
  double minLookaheadMeters = 200; // ~30s at walking speed
  double maxLookaheadMeters = 1200; // ~30s at 90mph

  // Queue of facts that haven't been narrated yet for the active trip.
  // Sorted by trip order is not strictly necessary — we always pick
  // the nearest un-narrated fact — but it keeps the working set small
  // by trimming "already-passed" facts as the user moves.
  List<RouteFact> _queue = const [];

  // True between startTrip and the moment the fetch resolves. Drives
  // the "Loading whispers..." indicator on the NarrationCard so a
  // user whose first trip is hitting a cold backend cache doesn't
  // wonder why nothing's happening.
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Pageids the user has previously saved. Hydrated at startTrip
  // and mutated optimistically by `toggleSave`. The NarrationCard
  // reads `isSaved(pageid)` to render its star icon state.
  final Set<int> _savedPageids = <int>{};
  bool isSaved(int pageid) => _savedPageids.contains(pageid);

  // Trip identifier carried into feedback events so we can tie
  // them back to specific trips later (Discoveries timeline). null
  // for ad-hoc drives that aren't backed by a saved Trip record.
  String? _currentTripId;

  // The most recent fact we narrated. The narration card reads this
  // and shows the title + primary text + buttons.
  _ActiveNarration? _active;
  _ActiveNarration? get current => _active;

  // Tracks which follow-up index we're on for the current narration.
  // Drives "1 of 3 more" UI.
  int _followUpIndex = 0;
  int get followUpIndex => _followUpIndex;

  // Last time we successfully spoke a narration. Drives the spacing
  // rule. Null until first narration of the trip.
  DateTime? _lastSpokeAt;

  /// True if there's at least one fact loaded and ready to potentially
  /// fire. UI uses this to decide whether to show "narration paused"
  /// indicators or just stay invisible.
  bool get hasLoadedFacts => _queue.isNotEmpty || _active != null;

  // Monologue v1 state. The companion's authored narration track,
  // distinct from the per-POI Wikipedia queue above. See
  // docs/companion-monologue-v1-plan.md.
  List<MonologueUtterance> _monologueQueue = const [];
  final Map<String, ({double lat, double lng})> _townCentroids = {};

  /// Radius around a town centroid that counts as "entered the town."
  /// 3 miles handles drive-throughs without firing far too early.
  /// Surfaced so tests can tighten this for deterministic GPS frames.
  double townEntryRadiusMiles = 3.0;

  /// How long a monologue utterance stays visible after firing. ~13s
  /// of speech + ~7s padding so a passenger can finish reading the
  /// text after the audio finishes. Surfaced for tests to drop to
  /// near-zero for deterministic assertion frames.
  Duration monologueCardDuration = const Duration(seconds: 20);

  /// Currently-visible monologue utterance, or null when no monologue
  /// is on screen. The MonologueCard widget watches this; auto-clears
  /// after `monologueCardDuration` since the utterance fired.
  MonologueUtterance? _currentMonologueUtterance;
  MonologueUtterance? get currentMonologueUtterance =>
      _currentMonologueUtterance;
  Timer? _monologueClearTimer;

  /// User-initiated dismiss of the monologue card. The audio keeps
  /// playing (already handed off to the native side); we just hide
  /// the visual.
  void dismissMonologueCard() {
    _monologueClearTimer?.cancel();
    _currentMonologueUtterance = null;
    notifyListeners();
  }

  /// Kick off a trip's narration by fetching facts for the encoded
  /// polyline. Idempotent for the same polyline; calling again with
  /// a different polyline replaces the queue.
  ///
  /// Also hydrates the saved-pageids set in parallel so the
  /// NarrationCard can render correct save state from the first
  /// whisper without flicker.
  Future<void> startTrip(String polyline, {String? tripId}) async {
    debugPrint('🗣️ Narration: loading facts for trip...');
    _isLoading = true;
    _queue = const [];
    _monologueQueue = const [];
    _townCentroids.clear();
    _active = null;
    _followUpIndex = 0;
    _lastSpokeAt = null;
    _currentTripId = tripId;
    notifyListeners();

    // Fetch facts + saved pageids + monologue (if tripId is known)
    // in parallel. Saves don't block narration: if listSaved fails the
    // card just shows un-starred hearts and the user can still save.
    // The monologue fetch is also non-blocking — if it fails or the
    // trip has no monologue yet, only per-POI narration runs.
    final results = await Future.wait([
      _fetcher(polyline),
      NarrationFeedbackService.listSaved(),
      if (tripId != null && tripId.isNotEmpty)
        _monologueFetcher(tripId)
      else
        Future<RouteMonologue?>.value(null),
    ]);
    final facts = results[0] as List<RouteFact>;
    final saved = results[1] as List<SavedFactSummary>;
    final monologue = results[2] as RouteMonologue?;

    _queue = facts;
    _savedPageids
      ..clear()
      ..addAll(saved.map((s) => s.wikipediaPageid));
    if (monologue != null) {
      _monologueQueue = List<MonologueUtterance>.from(monologue.utterances);
      _townCentroids.clear();
      for (final town in monologue.towns) {
        _townCentroids[town.name.toLowerCase()] =
            (lat: town.lat, lng: town.lng);
      }
      debugPrint(
        '🗣️ Monologue: loaded ${monologue.utterances.length} utterances '
        'across ${monologue.towns.length} towns',
      );
    }
    _isLoading = false;
    debugPrint(
        '🗣️ Narration: loaded ${facts.length} facts, ${saved.length} saved');
    notifyListeners();
  }

  /// Clear narration state for trip end / cancellation. The active
  /// card is dismissed; further location updates are no-ops until
  /// the next startTrip call. Also tells the native side to wipe the
  /// trip's narration markers — they're trip-scoped, not persistent
  /// across trips (yet; the Discoveries-timeline slice will change
  /// that).
  void endTrip() {
    _queue = const [];
    _monologueQueue = const [];
    _townCentroids.clear();
    _monologueClearTimer?.cancel();
    _currentMonologueUtterance = null;
    _active = null;
    _followUpIndex = 0;
    _lastSpokeAt = null;
    _isLoading = false;
    _pageidByTakeMeThereWaypoint.clear();
    _bridge?.clearNarration();
    _bridge?.clearNarrationMarkers();
    notifyListeners();
  }

  /// Native pushed a fresh GPS fix. Decide if we should whisper.
  /// Called frequently (~1 Hz during driving) — keep the work
  /// proportional.
  ///
  /// Two firing strategies live here:
  ///
  ///   1. **Route-projection lookahead (preferred)** — when the fact
  ///      and the user both have a `distance_along_route_meters`,
  ///      fire when the fact is approaching: between `0` and
  ///      `speed-adjusted lookahead` meters ahead of the user along
  ///      the route. This naturally handles winding roads, varying
  ///      speeds, and gives the listener time to glance up before
  ///      we describe a place.
  ///
  ///   2. **Haversine proximity fallback** — for facts without a
  ///      route projection (older bundles, area-prewarm hits the
  ///      user encounters off-route, etc.), fall back to the simple
  ///      ~500m radius rule.
  void onLocationUpdate({
    required double latitude,
    required double longitude,
    required double speedMph,
    double distanceAlongRouteMeters = 0.0,
  }) {
    if (_queue.isEmpty && _monologueQueue.isEmpty) return;
    if (speedMph > maxSpeedMph) return;

    final now = _now();
    if (_lastSpokeAt != null && now.difference(_lastSpokeAt!) < minSpacing) {
      return;
    }

    // Monologue track: fire the next anchored utterance if the user
    // has entered its town. Strictly in author order so the narrative
    // arc unfolds correctly — utterances anchored to towns we've
    // already passed naturally drop off the head as we advance.
    if (_monologueQueue.isNotEmpty) {
      final fired = _maybeFireMonologue(latitude, longitude, now);
      if (fired) return; // Respect spacing — per-POI waits 30s.
    }

    if (_queue.isEmpty) return;

    final lookaheadM = _lookaheadMeters(speedMph);

    // Score each candidate. Route-projection-eligible facts pick a
    // "best by lookahead distance"; haversine-only ones pick a "best
    // by physical proximity." We never fire a fact that's already
    // behind the user along the route — that's the whole point of
    // lookahead.
    int? routeBestIdx;
    double routeBestAheadM = double.infinity;
    int? proxBestIdx;
    double proxBestDistMi = double.infinity;
    for (var i = 0; i < _queue.length; i++) {
      final f = _queue[i];
      if (f.distanceAlongRouteMeters != null) {
        final aheadM = f.distanceAlongRouteMeters! - distanceAlongRouteMeters;
        // Only consider facts that are ahead of us (positive lookahead)
        // and within the speed-adapted window.
        if (aheadM >= 0 && aheadM <= lookaheadM && aheadM < routeBestAheadM) {
          routeBestAheadM = aheadM;
          routeBestIdx = i;
        }
      } else {
        final d = _haversineMiles(latitude, longitude, f.lat, f.lng);
        if (d < proxBestDistMi) {
          proxBestDistMi = d;
          proxBestIdx = i;
        }
      }
    }

    // Route-projection beats haversine when both are eligible — the
    // lookahead is the better timing signal whenever we have it.
    int? chosen;
    if (routeBestIdx != null) {
      chosen = routeBestIdx;
    } else if (proxBestIdx != null && proxBestDistMi <= proximityMiles) {
      chosen = proxBestIdx;
    }
    if (chosen == null) return;

    final fact = _queue.removeAt(chosen);
    _fire(fact, now);
  }

  /// Speed-adapted lookahead window in meters. ~30 seconds of travel
  /// at any reasonable speed, clamped to a sensible floor/ceiling so
  /// stationary cars don't refuse to ever fire and racecars don't
  /// fire from absurdly far away.
  double _lookaheadMeters(double speedMph) {
    // 1 mph = 0.44704 m/s; window = speed × seconds.
    final raw = speedMph * 0.44704 * lookaheadDuration.inSeconds;
    if (raw < minLookaheadMeters) return minLookaheadMeters;
    if (raw > maxLookaheadMeters) return maxLookaheadMeters;
    return raw;
  }

  /// Try to fire the next monologue utterance if the user has entered
  /// its anchor town. Returns true if an utterance fired, false
  /// otherwise. Skips silently when narrationMode == "off".
  ///
  /// Strict author-order: only the head of the queue is checked. If
  /// the user skips a town (re-route, alternate path), the utterances
  /// anchored to it stay at the head of the queue and never fire,
  /// because the next entry checked never matches their anchor either.
  /// Future polish (Slice F) can add a "drop stale utterances after
  /// N miles" sweep to avoid that.
  bool _maybeFireMonologue(double lat, double lng, DateTime now) {
    if (_monologueQueue.isEmpty) return false;
    final utt = _monologueQueue.first;
    final centroid = _townCentroids[utt.anchor.toLowerCase()];
    if (centroid == null) return false;
    final dist = _haversineMiles(lat, lng, centroid.lat, centroid.lng);
    if (dist > townEntryRadiusMiles) return false;

    // Pop and fire.
    _monologueQueue = _monologueQueue.sublist(1);
    if (narrationMode == 'off') {
      debugPrint(
        '🎙️ Monologue [${utt.i}] @ ${utt.anchor} suppressed (mode=off)',
      );
      return true;
    }
    debugPrint(
      '🎙️ Monologue [${utt.i}] @ ${utt.anchor} (${dist.toStringAsFixed(1)}mi): '
      '${utt.text}',
    );
    _lastSpokeAt = now;
    // tap_to_hear is a per-POI affordance (the card has Replay).
    // Monologue is audio-only in v1, so silent mode means we still
    // pop the queue (advance the narrative) but skip the audio.
    if (narrationMode != 'tap_to_hear') {
      _speak(utt.text, utt.audioUrl);
    }
    // Surface the utterance on the dashboard for ~20s. Listeners
    // (MonologueCard) rebuild on the notifyListeners() call.
    _currentMonologueUtterance = utt;
    _monologueClearTimer?.cancel();
    _monologueClearTimer = Timer(monologueCardDuration, () {
      _currentMonologueUtterance = null;
      notifyListeners();
    });
    notifyListeners();
    return true;
  }

  /// Speak the primary line of [fact] now via the native bridge,
  /// promote it to `current` so the UI shows the card, and reset
  /// follow-up index. Also drops a persistent map marker so the user
  /// has a visual anchor for what's being discussed, and promotes
  /// it to "active" for the pulsing animation. Records a `played`
  /// interaction event for Phase 3 personalization.
  void _fire(RouteFact fact, DateTime now) {
    // Off mode: silently skip. Marker doesn't drop, banner doesn't
    // show, audio doesn't play. The fact gets removed from the queue
    // by the caller so we don't re-fire it once the user moves out
    // and back in to proximity.
    if (narrationMode == 'off') {
      debugPrint('🗣️ Whisper suppressed (mode=off): "${fact.articleTitle}"');
      return;
    }

    _active = _ActiveNarration(fact: fact, firedAt: now);
    _followUpIndex = 0;
    _lastSpokeAt = now;
    debugPrint('🗣️ Whisper: "${fact.articleTitle}" — ${fact.primary}');

    // Tap-to-hear: drop marker + show banner but stay silent. User
    // taps Replay (or the native banner's play button) to actually
    // hear it. We DON'T fire a `played` event yet — that records
    // when audio actually plays, via replay() or speak().
    final shouldSpeakNow = narrationMode != 'tap_to_hear';
    if (shouldSpeakNow) {
      _speak(fact.primary, fact.primaryAudioUrl);
      NarrationFeedbackService.recordEvent(
        pageid: fact.wikipediaPageid,
        eventType: NarrationEvent.played,
        tripId: _currentTripId,
      );
    }
    _dropMarker(fact);
    _pushNarrationBanner(fact);
    notifyListeners();
  }

  /// Push the active narration into the native banner inside
  /// MapActivity so the user has a controllable surface during
  /// active driving (the Flutter NarrationCard only renders on the
  /// dashboard). Fire-and-forget — banner is a UX nicety, not
  /// load-bearing.
  void _pushNarrationBanner(RouteFact fact) {
    _bridge?.setNarration(
      pageid: fact.wikipediaPageid,
      title: fact.articleTitle,
      primary: fact.primary,
      canTellMore: !fact.isThin && fact.followUps.isNotEmpty,
      isSaved: _savedPageids.contains(fact.wikipediaPageid),
    );
  }

  /// Add a persistent map marker for [fact] and promote it to the
  /// active (pulsing) state. Past markers stay on the map but go
  /// static so the user sees a trail of "everywhere the app has
  /// pointed out" over the trip.
  void _dropMarker(RouteFact fact) {
    final b = _bridge;
    if (b == null) return;
    final id = 'wiki-${fact.wikipediaPageid}';
    b.addNarrationMarker(
      id: id,
      lat: fact.lat,
      lng: fact.lng,
      title: fact.articleTitle,
    );
    b.setActiveNarrationMarker(id: id);
  }

  /// Re-speak the current narration. No spacing rule applies — this
  /// is user-initiated. Recorded as a `replayed` event (strong
  /// positive signal: user wanted to hear it twice).
  void replay() {
    final a = _active;
    if (a == null) return;
    if (_followUpIndex == 0) {
      _speak(a.fact.primary, a.fact.primaryAudioUrl);
    } else {
      final i = _followUpIndex - 1;
      _speak(
        a.fact.followUps[i],
        _audioAt(a.fact.followUpAudioUrls, i),
      );
    }
    NarrationFeedbackService.recordEvent(
      pageid: a.fact.wikipediaPageid,
      eventType: NarrationEvent.replayed,
      tripId: _currentTripId,
    );
  }

  /// Advance to the next follow-up. Returns false when exhausted
  /// (the card switches to "that's all I've got on this one").
  /// Recorded as a `tell_me_more` event with the index advanced to
  /// — that's strong positive signal for the ranker.
  bool tellMeMore() {
    final a = _active;
    if (a == null) return false;
    if (a.fact.isThin) return false;
    if (_followUpIndex >= a.fact.followUps.length) return false;
    final i = _followUpIndex;
    final next = a.fact.followUps[i];
    final url = _audioAt(a.fact.followUpAudioUrls, i);
    _followUpIndex += 1;
    _speak(next, url);
    NarrationFeedbackService.recordEvent(
      pageid: a.fact.wikipediaPageid,
      eventType: NarrationEvent.tellMeMore,
      followUpIndex: i,
      tripId: _currentTripId,
    );
    notifyListeners();
    return true;
  }

  /// Audio-URL-when-available, else fall back to local TTS on the
  /// text. Both paths still hit the same bridge so callers can stay
  /// blissfully ignorant.
  void _speak(String text, String? audioUrl) {
    final b = _bridge;
    if (b == null) return;
    if (audioUrl != null && audioUrl.isNotEmpty) {
      b.playNarrationAudio(url: audioUrl);
    } else {
      b.speakNarration(text: text);
    }
  }

  String? _audioAt(List<String?> urls, int i) =>
      (i >= 0 && i < urls.length) ? urls[i] : null;

  /// Returns true when there's more to say (more follow-ups remain
  /// AND the article isn't thin). UI uses this to enable/disable
  /// the Tell-me-more button.
  bool get canTellMore {
    final a = _active;
    if (a == null) return false;
    if (a.fact.isThin) return false;
    return _followUpIndex < a.fact.followUps.length;
  }

  /// Dismiss the active card without saving. Doesn't reset
  /// `_lastSpokeAt` — we don't want the next narration to fire
  /// immediately after a dismiss. Recorded as a `dismissed` event
  /// (negative signal: user actively rejected this whisper).
  void dismissActive() {
    final a = _active;
    if (a != null) {
      NarrationFeedbackService.recordEvent(
        pageid: a.fact.wikipediaPageid,
        eventType: NarrationEvent.dismissed,
        tripId: _currentTripId,
      );
    }
    _active = null;
    _followUpIndex = 0;
    _bridge?.clearNarration();
    notifyListeners();
  }

  /// User asked the app to re-route to the currently-active fact.
  /// Records the high-confidence engagement event and hands off to
  /// the registered `onTakeMeThere` callback for the actual waypoint
  /// + route-update work (so NarrationService doesn't have to import
  /// the navigation stack and create a circular dep).
  ///
  /// Returns true if there was an active narration to act on; false
  /// otherwise. Caller can show a snackbar based on the return.
  bool takeMeThere() {
    final a = _active;
    if (a == null) return false;
    NarrationFeedbackService.recordEvent(
      pageid: a.fact.wikipediaPageid,
      eventType: NarrationEvent.takeMeThereTapped,
      tripId: _currentTripId,
    );
    onTakeMeThere?.call(a.fact);
    return true;
  }

  /// Map of waypoint-id → wikipedia_pageid for waypoints we added
  /// via Take-me-there. NavigationController populates this when the
  /// waypoint is created, and consults it on Mapbox arrival to know
  /// which (if any) narrated fact got "visited."
  final Map<String, int> _pageidByTakeMeThereWaypoint = {};

  /// Called by NavigationController right after a Take-me-there
  /// waypoint is added to the route, so we can later attribute the
  /// arrival back to the fact it was created for.
  void registerTakeMeThereWaypoint(int pageid, String waypointId) {
    _pageidByTakeMeThereWaypoint[waypointId] = pageid;
  }

  /// Called when Mapbox fires arrival at a waypoint. Looks up whether
  /// the waypoint was a take-me-there destination; if so, records
  /// the `visited` event — the closed-loop signal that the whisper
  /// successfully changed real-world behavior.
  void onWaypointArrived(String waypointId) {
    final pageid = _pageidByTakeMeThereWaypoint.remove(waypointId);
    if (pageid == null) return;
    debugPrint('🗣️ Visited: pageid=$pageid (was a take-me-there waypoint)');
    NarrationFeedbackService.recordEvent(
      pageid: pageid,
      eventType: NarrationEvent.visited,
      tripId: _currentTripId,
    );
  }

  /// Toggle the save state of the currently-active fact. Optimistic:
  /// the UI flips immediately, the backend call happens in the
  /// background. On network failure we revert and notify so the
  /// star icon stays honest.
  Future<void> toggleSaveActive() async {
    final a = _active;
    if (a == null) return;
    final pageid = a.fact.wikipediaPageid;
    final wasSaved = _savedPageids.contains(pageid);
    if (wasSaved) {
      _savedPageids.remove(pageid);
    } else {
      _savedPageids.add(pageid);
    }
    notifyListeners();

    // Reflect optimistic state on native banner immediately too.
    _bridge?.setNarrationSaved(isSaved: !wasSaved);

    final success = wasSaved
        ? await NarrationFeedbackService.unsaveFact(pageid: pageid)
        : await NarrationFeedbackService.saveFact(
            pageid: pageid,
            articleTitle: a.fact.articleTitle,
            articleUrl: a.fact.articleUrl,
            tripId: _currentTripId,
          );
    if (!success) {
      // Revert the optimistic flip — backend rejected the change.
      if (wasSaved) {
        _savedPageids.add(pageid);
      } else {
        _savedPageids.remove(pageid);
      }
      _bridge?.setNarrationSaved(isSaved: wasSaved);
      notifyListeners();
    }
  }
}

class _ActiveNarration {
  final RouteFact fact;
  final DateTime firedAt;
  _ActiveNarration({required this.fact, required this.firedAt});
}

/// Haversine distance in miles. Local copy rather than dragging in
/// the backend's polyline utils — this function is tiny and the
/// service has no other backend-coupling.
double _haversineMiles(double lat1, double lng1, double lat2, double lng2) {
  const earthMiles = 3958.8;
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthMiles * c;
}

double _rad(double deg) => deg * (math.pi / 180.0);
