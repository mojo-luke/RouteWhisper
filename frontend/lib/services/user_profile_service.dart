import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// In-memory representation of `/api/v1/user/profile`.
@immutable
class UserProfile {
  final List<String> preferredPoiTypes;
  final int? defaultTimeBudgetMinutes;
  final List<String> dietaryRestrictions;

  const UserProfile({
    this.preferredPoiTypes = const [],
    this.defaultTimeBudgetMinutes,
    this.dietaryRestrictions = const [],
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        preferredPoiTypes:
            (json['preferred_poi_types'] as List? ?? const []).cast<String>(),
        defaultTimeBudgetMinutes: json['default_time_budget_minutes'] as int?,
        dietaryRestrictions:
            (json['dietary_restrictions'] as List? ?? const []).cast<String>(),
      );

  Map<String, dynamic> toJson() => {
        'preferred_poi_types': preferredPoiTypes,
        'default_time_budget_minutes': defaultTimeBudgetMinutes,
        'dietary_restrictions': dietaryRestrictions,
      };

  UserProfile copyWith({
    List<String>? preferredPoiTypes,
    int? defaultTimeBudgetMinutes,
    bool clearTimeBudget = false,
    List<String>? dietaryRestrictions,
  }) =>
      UserProfile(
        preferredPoiTypes: preferredPoiTypes ?? this.preferredPoiTypes,
        defaultTimeBudgetMinutes: clearTimeBudget
            ? null
            : (defaultTimeBudgetMinutes ?? this.defaultTimeBudgetMinutes),
        dietaryRestrictions: dietaryRestrictions ?? this.dietaryRestrictions,
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
