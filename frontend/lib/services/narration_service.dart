import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/route_fact.dart';
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
    DateTime Function()? now,
  })  : _bridge = bridge,
        _fetcher = fetcher ?? RouteFactsService.fetchForRoute,
        _now = now ?? DateTime.now;

  // Test seams. Production passes nothing and the controller calls
  // `bindBridge` once during initialize() to give us the live bridge.
  NavigationHostBridge? _bridge;
  final Future<List<RouteFact>> Function(String polyline) _fetcher;
  final DateTime Function() _now;

  /// Called by NavigationController.initialize() to wire the bridge
  /// after both singletons exist. Idempotent; safe to call again on
  /// hot-restart.
  void bindBridge(NavigationHostBridge bridge) {
    _bridge = bridge;
  }

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
    _active = null;
    _followUpIndex = 0;
    _lastSpokeAt = null;
    _currentTripId = tripId;
    notifyListeners();

    // Fetch facts + saved pageids in parallel. Saves don't block
    // narration: if listSaved fails the card just shows un-starred
    // hearts and the user can still save.
    final results = await Future.wait([
      _fetcher(polyline),
      NarrationFeedbackService.listSaved(),
    ]);
    final facts = results[0] as List<RouteFact>;
    final saved = results[1] as List<SavedFactSummary>;

    _queue = facts;
    _savedPageids
      ..clear()
      ..addAll(saved.map((s) => s.wikipediaPageid));
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
    _active = null;
    _followUpIndex = 0;
    _lastSpokeAt = null;
    _isLoading = false;
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
    if (_queue.isEmpty) return;
    if (speedMph > maxSpeedMph) return;

    final now = _now();
    if (_lastSpokeAt != null && now.difference(_lastSpokeAt!) < minSpacing) {
      return;
    }

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

  /// Speak the primary line of [fact] now via the native bridge,
  /// promote it to `current` so the UI shows the card, and reset
  /// follow-up index. Also drops a persistent map marker so the user
  /// has a visual anchor for what's being discussed, and promotes
  /// it to "active" for the pulsing animation. Records a `played`
  /// interaction event for Phase 3 personalization.
  void _fire(RouteFact fact, DateTime now) {
    _active = _ActiveNarration(fact: fact, firedAt: now);
    _followUpIndex = 0;
    _lastSpokeAt = now;
    debugPrint('🗣️ Whisper: "${fact.articleTitle}" — ${fact.primary}');
    _speak(fact.primary, fact.primaryAudioUrl);
    _dropMarker(fact);
    _pushNarrationBanner(fact);
    NarrationFeedbackService.recordEvent(
      pageid: fact.wikipediaPageid,
      eventType: NarrationEvent.played,
      tripId: _currentTripId,
    );
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
