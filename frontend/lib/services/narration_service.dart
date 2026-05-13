import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/route_fact.dart';
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
  double proximityMiles = 0.31; // ~500m, matches plan
  double maxSpeedMph = 70.0;

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
  Future<void> startTrip(String polyline) async {
    debugPrint('🗣️ Narration: loading facts for trip...');
    _isLoading = true;
    _queue = const [];
    _active = null;
    _followUpIndex = 0;
    _lastSpokeAt = null;
    notifyListeners();
    final facts = await _fetcher(polyline);
    _queue = facts;
    _isLoading = false;
    debugPrint('🗣️ Narration: loaded ${facts.length} facts');
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
    _bridge?.clearNarrationMarkers();
    notifyListeners();
  }

  /// Native pushed a fresh GPS fix. Decide if we should whisper.
  /// Called frequently (~1 Hz during driving) — keep the work
  /// proportional.
  void onLocationUpdate({
    required double latitude,
    required double longitude,
    required double speedMph,
  }) {
    if (_queue.isEmpty) return;
    if (speedMph > maxSpeedMph) return;

    final now = _now();
    if (_lastSpokeAt != null && now.difference(_lastSpokeAt!) < minSpacing) {
      return;
    }

    // Find the nearest un-narrated fact. We also trim facts we've
    // clearly passed (further than 2× proximity *behind* us) but only
    // when we're not currently within proximity of anything. For
    // Phase 1 we don't have a "passed" heading-aware check, so we
    // just keep all facts in the queue and rely on distance-based
    // re-eligibility — same fact won't fire twice because it gets
    // removed from the queue on fire.
    int? bestIndex;
    double bestDist = double.infinity;
    for (var i = 0; i < _queue.length; i++) {
      final f = _queue[i];
      final d = _haversineMiles(latitude, longitude, f.lat, f.lng);
      if (d < bestDist) {
        bestDist = d;
        bestIndex = i;
      }
    }
    if (bestIndex == null || bestDist > proximityMiles) return;

    final fact = _queue.removeAt(bestIndex);
    _fire(fact, now);
  }

  /// Speak the primary line of [fact] now via the native bridge,
  /// promote it to `current` so the UI shows the card, and reset
  /// follow-up index. Also drops a persistent map marker so the user
  /// has a visual anchor for what's being discussed, and promotes
  /// it to "active" for the pulsing animation.
  void _fire(RouteFact fact, DateTime now) {
    _active = _ActiveNarration(fact: fact, firedAt: now);
    _followUpIndex = 0;
    _lastSpokeAt = now;
    debugPrint('🗣️ Whisper: "${fact.articleTitle}" — ${fact.primary}');
    _speak(fact.primary, fact.primaryAudioUrl);
    _dropMarker(fact);
    notifyListeners();
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
  /// is user-initiated.
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
  }

  /// Advance to the next follow-up. Returns false when exhausted
  /// (the card switches to "that's all I've got on this one").
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
  /// immediately after a dismiss.
  void dismissActive() {
    _active = null;
    _followUpIndex = 0;
    notifyListeners();
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
