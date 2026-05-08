import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/waypoint.dart';
import 'auth_service.dart';

/// API client for waypoint-related backend operations
///
/// Handles communication with backend for:
/// - Stop history recording (for personalization)
/// - Analytics retrieval (future)
class WaypointApiService {
  static const String baseUrl = 'http://10.0.2.2:8000/api/v1';

  /// Record stop history for a completed waypoint
  ///
  /// Sends actual stop duration data to backend for:
  /// - Category-based duration averages
  /// - Time-of-day pattern analysis
  /// - User preference learning
  ///
  /// Returns true if recording was successful
  static Future<bool> recordStopHistory(Waypoint waypoint) async {
    if (waypoint.arrivalTime == null || waypoint.departureTime == null) {
      print('⚠️ Cannot record stop history: missing arrival/departure times');
      return false;
    }

    final actualDuration = waypoint.actualDurationMinutes ??
        waypoint.departureTime!.difference(waypoint.arrivalTime!).inMinutes;

    final payload = {
      'waypoint_id': waypoint.id,
      'waypoint_name': waypoint.name,
      'waypoint_category': waypoint.sourcePOI?.category,
      'latitude': waypoint.latitude,
      'longitude': waypoint.longitude,
      'planned_duration_minutes': waypoint.estimatedDurationMinutes,
      'actual_duration_minutes': actualDuration,
      'arrival_time': waypoint.arrivalTime!.toIso8601String(),
      'departure_time': waypoint.departureTime!.toIso8601String(),
      'is_automatic_departure': waypoint.isAutomaticDeparture ?? false,
      'waypoint_order': waypoint.order,
      // Note: total_waypoints not included here; can be added when WaypointManager is passed
    };

    try {
      print('📤 Sending stop history to backend...');

      final response = await http.post(
        Uri.parse('$baseUrl/waypoints/history'),
        headers: _authedJsonHeaders(),
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Stop history recorded: id=${data['id']}');
        return true;
      } else {
        print('❌ Failed to record stop history: ${response.statusCode}');
        print('   Response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Error recording stop history: $e');
      return false;
    }
  }

  /// Map of category → `{count, avg_planned_minutes, avg_actual_minutes,
  /// avg_diff_minutes}` for the authenticated user. Returns null on error
  /// or when not signed in.
  static Future<Map<String, Map<String, num>>?> getCategoryAverages() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/waypoints/category-averages'),
        headers: _authedJsonHeaders(),
      );
      if (response.statusCode != 200) {
        print('⚠️ category-averages: HTTP ${response.statusCode}');
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final categories = (data['categories'] as List).cast<Map<String, dynamic>>();
      return {
        for (final c in categories)
          c['category'] as String: {
            'count': c['count'] as num,
            'avg_planned_minutes': c['avg_planned_minutes'] as num,
            'avg_actual_minutes': c['avg_actual_minutes'] as num,
            'avg_diff_minutes': c['avg_diff_minutes'] as num,
          },
      };
    } catch (e) {
      print('❌ getCategoryAverages failed: $e');
      return null;
    }
  }

  /// Stop counts by hour-of-day and day-of-week for the authenticated user.
  static Future<Map<String, dynamic>?> getTimePatterns() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/waypoints/time-patterns'),
        headers: _authedJsonHeaders(),
      );
      if (response.statusCode != 200) {
        print('⚠️ time-patterns: HTTP ${response.statusCode}');
        return null;
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      print('❌ getTimePatterns failed: $e');
      return null;
    }
  }

  static Map<String, String> _authedJsonHeaders() {
    final token = AuthService.instance.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}
