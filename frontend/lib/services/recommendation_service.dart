import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'authed_http.dart';
import 'navigation_service.dart';
import 'poi_api_service.dart';

// Debug builds want to actually see suggestions during a short test drive;
// production should err on the side of not pestering. Both values can be
// overridden by [RecommendationService.configure] from the user's profile.
const Duration _defaultPollInterval =
    kDebugMode ? Duration(minutes: 2) : Duration(minutes: 10);
const Duration _defaultMinGap =
    kDebugMode ? Duration(minutes: 5) : Duration(minutes: 15);
const int _defaultMaxPerTrip = kDebugMode ? 5 : 3;

/// One scored stop suggestion as returned by `/api/v1/recommendations/stops`.
@immutable
class StopSuggestion {
  final POI poi;
  final double score;
  final String reason;

  const StopSuggestion({
    required this.poi,
    required this.score,
    required this.reason,
  });

  factory StopSuggestion.fromJson(Map<String, dynamic> json) => StopSuggestion(
        poi: POI.fromJson(json['poi'] as Map<String, dynamic>),
        score: (json['score'] as num).toDouble(),
        reason: json['reason'] as String,
      );
}

/// Periodically asks the backend for proactive stop suggestions during nav,
/// then exposes the next one to surface via a [ChangeNotifier].
///
/// Rate caps (live nav is interruptive — be polite):
///   * poll every [pollInterval] (default 10 min) AND on demand,
///   * skip if last surface was within [minGapBetweenSurfaces] (15 min),
///   * cap surfaces to [maxPerTrip] per trip.
///
/// Suppression: when the user dismisses a suggestion, its POI id is added
/// to a per-trip skip list so the same place doesn't re-surface. Cleared
/// by [resetForNewTrip].
class RecommendationService extends ChangeNotifier {
  static const String _baseUrl = 'http://10.0.2.2:8000/api/v1';

  Duration pollInterval;
  Duration minGapBetweenSurfaces;
  int maxPerTrip;
  bool enabled;

  /// HTTP client. Tests inject a mock; production uses the default.
  final http.Client _httpClient;

  /// How to get the Bearer token. Defaults to the real AuthService;
  /// tests inject a static provider so they don't need a Supabase
  /// session.
  final String? Function() _tokenProvider;

  Timer? _timer;
  DateTime? _lastSurface;
  int _surfaceCount = 0;
  final Set<String> _suppressed = <String>{};

  StopSuggestion? _current;
  StopSuggestion? get current => _current;

  RecommendationService({
    this.pollInterval = _defaultPollInterval,
    this.minGapBetweenSurfaces = _defaultMinGap,
    this.maxPerTrip = _defaultMaxPerTrip,
    this.enabled = true,
    http.Client? httpClient,
    String? Function()? tokenProvider,
  })  : _httpClient = httpClient ?? http.Client(),
        _tokenProvider =
            tokenProvider ?? (() => AuthService.instance.accessToken);

  /// Apply runtime settings (typically read from `UserProfile`). Safe to
  /// call before or after [start]; if a poll timer is running with the
  /// old interval, it's restarted to pick up the new value.
  void configure({
    bool? enabled,
    int? maxPerTrip,
    Duration? minGapBetweenSurfaces,
    Duration? pollInterval,
  }) {
    if (enabled != null) this.enabled = enabled;
    if (maxPerTrip != null) this.maxPerTrip = maxPerTrip;
    if (minGapBetweenSurfaces != null) {
      this.minGapBetweenSurfaces = minGapBetweenSurfaces;
    }
    if (pollInterval != null && pollInterval != this.pollInterval) {
      this.pollInterval = pollInterval;
      if (_timer != null) {
        stop();
        start();
      }
    }
  }

  /// Start polling. Idempotent — calling twice doesn't double the timer.
  void start() {
    if (!enabled || _timer != null) return;
    _timer = Timer.periodic(pollInterval, (_) => poll());
    // Fire one immediately so the user gets a suggestion sooner than 10 min in.
    poll();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Clear per-trip state (suppression, surface count, current suggestion).
  /// Call at the start of every new trip.
  void resetForNewTrip() {
    _suppressed.clear();
    _surfaceCount = 0;
    _lastSurface = null;
    _current = null;
    notifyListeners();
  }

  /// User dismissed the current surfaced suggestion. Don't show this POI
  /// again this trip; clear `current` so the UI hides the card.
  void dismissCurrent() {
    final c = _current;
    if (c != null) {
      _suppressed.add(c.poi.id);
    }
    _current = null;
    notifyListeners();
  }

  /// User accepted the current suggestion. Caller is responsible for the
  /// route update — this just clears the card and counts it.
  void acceptCurrent() {
    final c = _current;
    if (c != null) {
      _suppressed.add(c.poi.id);
    }
    _current = null;
    notifyListeners();
  }

  /// User-initiated manual fetch — bypasses both the per-trip max and the
  /// minimum-gap cap (the user explicitly asked for a suggestion). Still
  /// honors the `enabled` flag because that's the user's own setting; if
  /// you disabled suggestions entirely you don't expect a tap to override.
  Future<void> forcePoll() => poll(bypassCaps: true);

  /// Fetch suggestions and, if the surface caps allow, expose the top one.
  Future<void> poll({bool bypassCaps = false}) async {
    if (!enabled) return;
    final polyline = NavigationService.routePolyline;
    if (polyline == null) return;
    if (!NavigationService.isNavigating) return;
    final now = DateTime.now();
    if (!bypassCaps) {
      if (_surfaceCount >= maxPerTrip) return;
      if (_lastSurface != null && now.difference(_lastSurface!) < minGapBetweenSurfaces) {
        return;
      }
    }

    // Build the EngineRequest envelope. See docs/recommendations-brief.md
    // → "Engine interface". Trip-scale is left null on the request — the
    // backend derives it from the polyline. Time-budget mode is currently
    // hard-coded to 'moderate'; per-trip override comes when the planning
    // surface exists.
    final remaining =
        NavigationService.waypointManager.remainingBudgetMinutes;
    final body = <String, dynamic>{
      'context': <String, dynamic>{
        'route_polyline': polyline,
        if (remaining != null) 'minutes_remaining': remaining,
        'time_budget_mode': 'moderate',
      },
      'intent': <String, dynamic>{
        'invocation': bypassCaps ? 'manual' : 'auto',
      },
    };

    // Headers are rebuilt inside the closure so a 401→refresh→retry
    // picks up the rotated token. The token may have been null when we
    // started (and the call would early-return) but after refresh it
    // can become valid.
    Future<http.Response> doSend() {
      final token = _tokenProvider();
      return _httpClient.post(
        Uri.parse('$_baseUrl/recommendations/stops'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
    }
    if (_tokenProvider() == null) return;

    try {
      final response = await AuthedHttp.send(doSend);
      if (response.statusCode != 200) {
        debugPrint('recommendations: HTTP ${response.statusCode}');
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = (data['suggestions'] as List).cast<Map<String, dynamic>>();
      final suggestions =
          raw.map(StopSuggestion.fromJson).where((s) => !_suppressed.contains(s.poi.id)).toList();
      if (suggestions.isEmpty) return;

      _current = suggestions.first;
      _surfaceCount += 1;
      _lastSurface = now;
      notifyListeners();
    } catch (e) {
      debugPrint('recommendations poll failed: $e');
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
