import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/discovery_item.dart';
import 'auth_service.dart';
import 'authed_http.dart';

/// Event types accepted by `POST /narration/{pageid}/event`. Keep
/// in sync with `_ALLOWED_INTERACTION_EVENTS` on the backend — a
/// drifted spelling here will 400 server-side, which is loud and
/// findable but worth avoiding.
class NarrationEvent {
  static const String played = 'played';
  static const String replayed = 'replayed';
  static const String tellMeMore = 'tell_me_more';
  static const String dismissed = 'dismissed';
  // Strongest engagement signal short of an actual visit — the user
  // asked the app to re-route to this place. Closes the loop from
  // "whisper played" to "user changed behavior."
  static const String takeMeThereTapped = 'take_me_there_tapped';
  // Mapbox arrived at the take-me-there waypoint. Fires from the
  // existing waypoint-arrival callback.
  static const String visited = 'visited';
}

/// One entry in the user's saved-facts list.
class SavedFactSummary {
  final int wikipediaPageid;
  final String articleTitle;
  final String articleUrl;
  final String savedAt; // ISO8601 string
  final String? tripId;

  const SavedFactSummary({
    required this.wikipediaPageid,
    required this.articleTitle,
    required this.articleUrl,
    required this.savedAt,
    this.tripId,
  });

  factory SavedFactSummary.fromJson(Map<String, dynamic> json) =>
      SavedFactSummary(
        wikipediaPageid: json['wikipedia_pageid'] as int,
        articleTitle: json['article_title'] as String,
        articleUrl: json['article_url'] as String,
        savedAt: json['saved_at'] as String,
        tripId: json['trip_id'] as String?,
      );
}

/// Client for Phase 2 talkback endpoints.
///
/// Three responsibilities:
///   1. Append implicit-interaction events (`recordEvent`). Fire and
///      forget; failures don't surface to the user because the
///      whisper UI doesn't depend on the server-side log.
///   2. Toggle save state (`save` / `unsave`). State *does* matter
///      for UI rendering, so these return success bools.
///   3. Fetch the user's saved-pageid set so the NarrationCard can
///      reflect "already saved" status without flickering.
class NarrationFeedbackService {
  static const String _baseUrl = 'http://10.0.2.2:8000/api/v1';

  static Future<void> recordEvent({
    required int pageid,
    required String eventType,
    int? followUpIndex,
    String? tripId,
  }) async {
    try {
      await AuthedHttp.send(
        () => http.post(
          Uri.parse('$_baseUrl/narration/$pageid/event'),
          headers: _authedHeaders(),
          body: jsonEncode({
            'event_type': eventType,
            if (followUpIndex != null) 'follow_up_index': followUpIndex,
            if (tripId != null) 'trip_id': tripId,
          }),
        ),
      );
    } catch (e) {
      // Phase 2 instrumentation is best-effort. A failed event
      // append doesn't break the user's drive.
      debugPrint('NarrationFeedbackService.recordEvent failed: $e');
    }
  }

  static Future<bool> saveFact({
    required int pageid,
    required String articleTitle,
    required String articleUrl,
    String? tripId,
  }) async {
    try {
      final response = await AuthedHttp.send(
        () => http.post(
          Uri.parse('$_baseUrl/narration/$pageid/save'),
          headers: _authedHeaders(),
          body: jsonEncode({
            'article_title': articleTitle,
            'article_url': articleUrl,
            if (tripId != null) 'trip_id': tripId,
          }),
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('NarrationFeedbackService.saveFact failed: $e');
      return false;
    }
  }

  static Future<bool> unsaveFact({required int pageid}) async {
    try {
      final response = await AuthedHttp.send(
        () => http.delete(
          Uri.parse('$_baseUrl/narration/$pageid/save'),
          headers: _authedHeaders(),
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('NarrationFeedbackService.unsaveFact failed: $e');
      return false;
    }
  }

  /// Fetch the user's full Discoveries timeline — every fact they've
  /// saved, visited, or heard, merged by pageid and sorted by most
  /// recent activity. Used to power the Discoveries screen.
  static Future<List<DiscoveryItem>> listDiscoveries() async {
    try {
      final response = await AuthedHttp.send(
        () => http.get(
          Uri.parse('$_baseUrl/narration/discoveries'),
          headers: _authedHeaders(),
        ),
      );
      if (response.statusCode != 200) {
        debugPrint('GET /narration/discoveries: HTTP ${response.statusCode}');
        return const [];
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = (data['items'] as List).cast<Map<String, dynamic>>();
      return raw.map(DiscoveryItem.fromJson).toList();
    } catch (e) {
      debugPrint('NarrationFeedbackService.listDiscoveries failed: $e');
      return const [];
    }
  }

  static Future<List<SavedFactSummary>> listSaved() async {
    try {
      final response = await AuthedHttp.send(
        () => http.get(
          Uri.parse('$_baseUrl/narration/saved'),
          headers: _authedHeaders(),
        ),
      );
      if (response.statusCode != 200) {
        debugPrint('GET /narration/saved: HTTP ${response.statusCode}');
        return const [];
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = (data['saved'] as List).cast<Map<String, dynamic>>();
      return raw.map(SavedFactSummary.fromJson).toList();
    } catch (e) {
      debugPrint('NarrationFeedbackService.listSaved failed: $e');
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
