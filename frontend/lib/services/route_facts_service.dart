import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/route_fact.dart';
import 'auth_service.dart';
import 'authed_http.dart';

/// Thin client over `POST /api/v1/route/facts`.
///
/// Called once per trip at trip-start time, when the user is still
/// in a parking-lot signal envelope. The backend handles fetching,
/// ranking, LLM summarization, and caching; we just consume the
/// returned list.
class RouteFactsService {
  static const String _baseUrl = 'http://10.0.2.2:8000/api/v1';

  /// Fetch narration-ready facts for the encoded route polyline.
  /// Returns an empty list on any failure — narration is a quiet
  /// feature, not load-bearing for navigation, so a failure here
  /// should never block the trip.
  static Future<List<RouteFact>> fetchForRoute(String polyline) async {
    final trimmed = polyline.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final response = await AuthedHttp.send(
        () => http.post(
          Uri.parse('$_baseUrl/route/facts'),
          headers: _authedHeaders(),
          body: jsonEncode({'polyline': trimmed}),
        ),
      );
      if (response.statusCode != 200) {
        debugPrint('POST /route/facts: HTTP ${response.statusCode}');
        return const [];
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawFacts = (data['facts'] as List).cast<Map<String, dynamic>>();
      return rawFacts.map(RouteFact.fromJson).toList();
    } catch (e) {
      debugPrint('RouteFactsService.fetchForRoute failed: $e');
      return const [];
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
