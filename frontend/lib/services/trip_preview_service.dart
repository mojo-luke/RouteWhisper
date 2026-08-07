import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/route_preview.dart';
import 'auth_service.dart';
import 'authed_http.dart';
import 'geocoding_service.dart';

/// Thin client over `POST/GET /api/v1/route/preview`. Called by the
/// trip-creation wizard as soon as origin+destination are both set —
/// well before the user has named the trip or saved anything.
///
/// Same `_baseUrl` / null-on-failure pattern as MonologueService and
/// TripService.
class TripPreviewService {
  static const String _baseUrl = 'http://10.0.2.2:8000/api/v1';

  /// Kick off (or join, or return cached) a preview for this route.
  static Future<RoutePreview?> start({
    required GeocodeCandidate origin,
    required GeocodeCandidate destination,
  }) async {
    try {
      final response = await AuthedHttp.send(
        () => http.post(
          Uri.parse('$_baseUrl/route/preview'),
          headers: _authedHeaders(),
          body: jsonEncode({
            'origin_name': origin.name.isEmpty ? origin.displayLine : origin.name,
            'origin_lat': origin.lat,
            'origin_lng': origin.lng,
            'destination_name': destination.name.isEmpty
                ? destination.displayLine
                : destination.name,
            'destination_lat': destination.lat,
            'destination_lng': destination.lng,
          }),
        ),
      );
      if (response.statusCode != 200) {
        debugPrint('POST /route/preview: HTTP ${response.statusCode}');
        return null;
      }
      return RoutePreview.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('TripPreviewService.start failed: $e');
      return null;
    }
  }

  /// Poll once for a preview's current state.
  static Future<RoutePreview?> poll(String polylineHash) async {
    try {
      final response = await AuthedHttp.send(
        () => http.get(
          Uri.parse('$_baseUrl/route/preview/$polylineHash'),
          headers: _authedHeaders(),
        ),
      );
      if (response.statusCode != 200) {
        debugPrint('GET /route/preview: HTTP ${response.statusCode}');
        return null;
      }
      return RoutePreview.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('TripPreviewService.poll failed: $e');
      return null;
    }
  }

  /// Polls every [interval] until the preview reaches `ready`/`failed`
  /// or [timeout] elapses, emitting every intermediate response so the
  /// reveal step can narrate `stage` changes rather than show a bare
  /// spinner. The final emission before the stream closes is always
  /// either a ready/failed preview or the last successful poll (on
  /// timeout) — callers should treat a still-pending final value as
  /// "couldn't finish in time" and degrade gracefully.
  static Stream<RoutePreview> watch(
    String polylineHash, {
    Duration interval = const Duration(seconds: 2),
    Duration timeout = const Duration(seconds: 90),
  }) async* {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final doc = await poll(polylineHash);
      if (doc != null) {
        yield doc;
        if (doc.status != PreviewStatus.pending) return;
      }
      if (DateTime.now().isAfter(deadline)) return;
      await Future.delayed(interval);
    }
  }

  static Map<String, String> _authedHeaders() {
    final token = AuthService.instance.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}
