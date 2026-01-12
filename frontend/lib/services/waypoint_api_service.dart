import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/waypoint.dart';

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
      // TODO: Add total_waypoints from WaypointManager
    };

    try {
      print('📤 Sending stop history to backend...');

      final response = await http.post(
        Uri.parse('$baseUrl/waypoints/history'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Stop history recorded: ${data['message']}');
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

  /// Get category-based average durations (future feature)
  ///
  /// Returns map of category -> average duration in minutes
  static Future<Map<String, double>?> getCategoryAverages() async {
    // TODO: Implement in Phase 6 when backend analytics are ready
    print('⏳ Category averages endpoint not yet implemented');
    return null;
  }

  /// Get user's time-of-day patterns (future feature)
  ///
  /// Returns analytics about when user typically stops
  static Future<Map<String, dynamic>?> getTimePatterns() async {
    // TODO: Implement in Phase 6 when backend analytics are ready
    print('⏳ Time patterns endpoint not yet implemented');
    return null;
  }
}
