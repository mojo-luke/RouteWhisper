import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// A single user interest. See docs/recommendations-brief.md →
/// "Personalization vocabulary". The `label` is user-facing; the other
/// two fields drive Mapbox query expansion when the engine consults
/// interests. Free-text labels start with empty arrays pending
/// LLM-normalization at profile-save (see backend Task #7).
@immutable
class UserInterest {
  final String label;
  final List<String> mapboxCategories;
  final List<String> keywords;

  const UserInterest({
    required this.label,
    this.mapboxCategories = const [],
    this.keywords = const [],
  });

  factory UserInterest.fromJson(Map<String, dynamic> json) => UserInterest(
        label: json['label'] as String,
        mapboxCategories:
            (json['mapbox_categories'] as List? ?? const []).cast<String>(),
        keywords: (json['keywords'] as List? ?? const []).cast<String>(),
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'mapbox_categories': mapboxCategories,
        'keywords': keywords,
      };
}

/// In-memory representation of `/api/v1/user/profile`.
@immutable
class UserProfile {
  final List<String> preferredPoiTypes;
  final int? defaultTimeBudgetMinutes;
  final List<String> dietaryRestrictions;
  final List<UserInterest> interests;

  // Recommendation surface controls — mirror server-side fields.
  final bool recommendationsEnabled;
  final int recommendationsMaxPerTrip;
  final int recommendationsMinGapMinutes;

  const UserProfile({
    this.preferredPoiTypes = const [],
    this.defaultTimeBudgetMinutes,
    this.dietaryRestrictions = const [],
    this.interests = const [],
    this.recommendationsEnabled = true,
    this.recommendationsMaxPerTrip = 3,
    this.recommendationsMinGapMinutes = 15,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        preferredPoiTypes:
            (json['preferred_poi_types'] as List? ?? const []).cast<String>(),
        defaultTimeBudgetMinutes: json['default_time_budget_minutes'] as int?,
        dietaryRestrictions:
            (json['dietary_restrictions'] as List? ?? const []).cast<String>(),
        interests: ((json['interests'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(UserInterest.fromJson)
            .toList(),
        recommendationsEnabled:
            (json['recommendations_enabled'] as bool?) ?? true,
        recommendationsMaxPerTrip:
            (json['recommendations_max_per_trip'] as int?) ?? 3,
        recommendationsMinGapMinutes:
            (json['recommendations_min_gap_minutes'] as int?) ?? 15,
      );

  Map<String, dynamic> toJson() => {
        'preferred_poi_types': preferredPoiTypes,
        'default_time_budget_minutes': defaultTimeBudgetMinutes,
        'dietary_restrictions': dietaryRestrictions,
        'interests': interests.map((i) => i.toJson()).toList(),
        'recommendations_enabled': recommendationsEnabled,
        'recommendations_max_per_trip': recommendationsMaxPerTrip,
        'recommendations_min_gap_minutes': recommendationsMinGapMinutes,
      };

  UserProfile copyWith({
    List<String>? preferredPoiTypes,
    int? defaultTimeBudgetMinutes,
    bool clearTimeBudget = false,
    List<String>? dietaryRestrictions,
    List<UserInterest>? interests,
    bool? recommendationsEnabled,
    int? recommendationsMaxPerTrip,
    int? recommendationsMinGapMinutes,
  }) =>
      UserProfile(
        preferredPoiTypes: preferredPoiTypes ?? this.preferredPoiTypes,
        defaultTimeBudgetMinutes: clearTimeBudget
            ? null
            : (defaultTimeBudgetMinutes ?? this.defaultTimeBudgetMinutes),
        dietaryRestrictions: dietaryRestrictions ?? this.dietaryRestrictions,
        interests: interests ?? this.interests,
        recommendationsEnabled:
            recommendationsEnabled ?? this.recommendationsEnabled,
        recommendationsMaxPerTrip:
            recommendationsMaxPerTrip ?? this.recommendationsMaxPerTrip,
        recommendationsMinGapMinutes:
            recommendationsMinGapMinutes ?? this.recommendationsMinGapMinutes,
      );
}

/// Thin client over `/user/profile`. Stateless — callers cache the result
/// at whatever scope makes sense (e.g., a Provider on the home screen).
class UserProfileService {
  static const String _baseUrl = 'http://10.0.2.2:8000/api/v1';

  static Future<UserProfile?> fetch() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/user/profile'),
        headers: _authedJsonHeaders(),
      );
      if (response.statusCode != 200) {
        debugPrint('GET /user/profile: HTTP ${response.statusCode}');
        return null;
      }
      return UserProfile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('UserProfileService.fetch failed: $e');
      return null;
    }
  }

  static Future<UserProfile?> save(UserProfile profile) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/user/profile'),
        headers: _authedJsonHeaders(),
        body: jsonEncode(profile.toJson()),
      );
      if (response.statusCode != 200) {
        debugPrint('PUT /user/profile: HTTP ${response.statusCode} ${response.body}');
        return null;
      }
      return UserProfile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('UserProfileService.save failed: $e');
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
