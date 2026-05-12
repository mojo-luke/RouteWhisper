import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/trip.dart';
import 'auth_service.dart';
import 'authed_http.dart';

/// Thin client over the backend's `/trips` CRUD endpoints. All calls go
/// through `AuthedHttp.send` so a stale Supabase token gets a single
/// refresh-retry before surfacing as a failure.
///
/// Each method returns the trip(s) the server confirms, NOT what the
/// client sent — server is the source of truth for ids and timestamps.
class TripService {
  static const String _baseUrl = 'http://10.0.2.2:8000/api/v1';

  /// List the caller's saved trips, most recently updated first. Returns
  /// an empty list on auth-less or server failure rather than throwing —
  /// the My Trips screen renders the empty state either way.
  static Future<List<Trip>> list() async {
    try {
      final response = await AuthedHttp.send(
        () => http.get(
          Uri.parse('$_baseUrl/trips'),
          headers: _authedJsonHeaders(),
        ),
      );
      if (response.statusCode != 200) {
        debugPrint('GET /trips: HTTP ${response.statusCode}');
        return const [];
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawTrips = (data['trips'] as List).cast<Map<String, dynamic>>();
      return rawTrips.map(Trip.fromJson).toList();
    } catch (e) {
      debugPrint('TripService.list failed: $e');
      return const [];
    }
  }

  static Future<Trip?> get(String id) async {
    try {
      final response = await AuthedHttp.send(
        () => http.get(
          Uri.parse('$_baseUrl/trips/$id'),
          headers: _authedJsonHeaders(),
        ),
      );
      if (response.statusCode != 200) {
        debugPrint('GET /trips/$id: HTTP ${response.statusCode}');
        return null;
      }
      return Trip.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('TripService.get failed: $e');
      return null;
    }
  }

  /// Create a new trip on the server. Returns the server-assigned record
  /// (with id + timestamps), or null on failure.
  static Future<Trip?> create(Trip trip) async {
    try {
      final response = await AuthedHttp.send(
        () => http.post(
          Uri.parse('$_baseUrl/trips'),
          headers: _authedJsonHeaders(),
          body: jsonEncode(trip.toJson()),
        ),
      );
      if (response.statusCode != 200) {
        debugPrint(
            'POST /trips: HTTP ${response.statusCode} ${response.body}');
        return null;
      }
      return Trip.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('TripService.create failed: $e');
      return null;
    }
  }

  /// Replace all editable fields of an existing trip.
  static Future<Trip?> update(Trip trip) async {
    final id = trip.id;
    if (id == null) {
      debugPrint('TripService.update called on a trip with no id');
      return null;
    }
    try {
      final response = await AuthedHttp.send(
        () => http.put(
          Uri.parse('$_baseUrl/trips/$id'),
          headers: _authedJsonHeaders(),
          body: jsonEncode(trip.toJson()),
        ),
      );
      if (response.statusCode != 200) {
        debugPrint(
            'PUT /trips/$id: HTTP ${response.statusCode} ${response.body}');
        return null;
      }
      return Trip.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('TripService.update failed: $e');
      return null;
    }
  }

  static Future<bool> delete(String id) async {
    try {
      final response = await AuthedHttp.send(
        () => http.delete(
          Uri.parse('$_baseUrl/trips/$id'),
          headers: _authedJsonHeaders(),
        ),
      );
      if (response.statusCode != 200) {
        debugPrint(
            'DELETE /trips/$id: HTTP ${response.statusCode} ${response.body}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('TripService.delete failed: $e');
      return false;
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
