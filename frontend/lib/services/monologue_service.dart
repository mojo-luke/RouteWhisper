import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/route_monologue.dart';
import 'auth_service.dart';
import 'authed_http.dart';

/// Thin client over `POST /api/v1/route/monologue`.
///
/// Called at trip-start by NarrationService. Returns the
/// (potentially cached) artifact produced by the backend's
/// generate_monologue pipeline — characterization, town list,
/// utterances with audio URLs, verified stops.
///
/// Same `_baseUrl` pattern as RouteFactsService (Android-emulator
/// loopback `10.0.2.2`). Returns `null` on any failure so the trip
/// can proceed without monologue narration; the existing per-POI
/// track is independent and unaffected.
class MonologueService {
  static const String _baseUrl = 'http://10.0.2.2:8000/api/v1';

  /// Fetch the monologue artifact for a saved trip. The backend
  /// resolves polyline + vibe from the trip record; we just hand
  /// it the trip id.
  ///
  /// Returns null when:
  ///   - HTTP non-200
  ///   - response can't be parsed
  ///   - any network exception
  ///
  /// Each of these makes monologue narration silently skip for
  /// this trip. Per-POI narration keeps working.
  static Future<RouteMonologue?> fetchForTrip(String tripId) async {
    if (tripId.trim().isEmpty) return null;
    try {
      final response = await AuthedHttp.send(
        () => http.post(
          Uri.parse('$_baseUrl/route/monologue'),
          headers: _authedHeaders(),
          body: jsonEncode({'trip_id': tripId}),
        ),
      );
      if (response.statusCode != 200) {
        debugPrint('POST /route/monologue: HTTP ${response.statusCode}');
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return RouteMonologue.fromJson(data);
    } catch (e) {
      debugPrint('MonologueService.fetchForTrip failed: $e');
      return null;
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
