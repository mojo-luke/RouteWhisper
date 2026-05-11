import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'navigation_service.dart';
import 'poi_api_service.dart';

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

  final Duration pollInterval;
  final Duration minGapBetweenSurfaces;
  final int maxPerTrip;

  Timer? _timer;
  DateTime? _lastSurface;
  int _surfaceCount = 0;
  final Set<String> _suppressed = <String>{};

  StopSuggestion? _current;
  StopSuggestion? get current => _current;

  RecommendationService({
    this.pollInterval = const Duration(minutes: 10),
    this.minGapBetweenSurfaces = const Duration(minutes: 15),
    this.maxPerTrip = 3,
  });

  /// Start polling. Idempotent — calling twice doesn't double the timer.
  void start() {
    if (_timer != null) return;
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

  /// Fetch suggestions and, if the surface caps allow, expose the top one.
  Future<void> poll() async {
    final polyline = NavigationService.routePolyline;
    if (polyline == null) return;
    if (!NavigationService.isNavigating) return;
    if (_surfaceCount >= maxPerTrip) return;
    final now = DateTime.now();
    if (_lastSurface != null && now.difference(_lastSurface!) < minGapBetweenSurfaces) {
      return;
    }

    final token = AuthService.instance.accessToken;
    if (token == null) return;

    final remaining =
        NavigationService.waypointManager.remainingBudgetMinutes;
    final body = <String, dynamic>{
      'encoded_polyline': polyline,
      if (remaining != null) 'remaining_budget_minutes': remaining,
    };

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/recommendations/stops'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
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
