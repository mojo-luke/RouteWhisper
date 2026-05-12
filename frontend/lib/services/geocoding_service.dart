import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'authed_http.dart';

/// One geocoded address candidate. Matches the backend `GeocodeCandidate`
/// shape.
class GeocodeCandidate {
  final String name;
  final String? fullAddress;
  final double lat;
  final double lng;
  final String? placeType;
  final String mapboxId;

  const GeocodeCandidate({
    required this.name,
    this.fullAddress,
    required this.lat,
    required this.lng,
    this.placeType,
    this.mapboxId = '',
  });

  factory GeocodeCandidate.fromJson(Map<String, dynamic> json) {
    return GeocodeCandidate(
      name: json['name'] as String? ?? '',
      fullAddress: json['full_address'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      placeType: json['place_type'] as String?,
      mapboxId: json['mapbox_id'] as String? ?? '',
    );
  }

  /// What the wizard displays in the suggestion list: prefer the
  /// full_address (it already includes the name); fall back to name.
  String get displayLine => fullAddress?.isNotEmpty == true ? fullAddress! : name;
}

class GeocodingService {
  static const String _baseUrl = 'http://10.0.2.2:8000/api/v1';

  /// Forward-geocode [query]. Pass [proximity] (lat, lng) to bias results
  /// toward the user's region. Returns an empty list on failure so the
  /// wizard never crashes mid-typing.
  static Future<List<GeocodeCandidate>> search(
    String query, {
    (double, double)? proximity,
    int limit = 5,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final params = <String, String>{
        'q': trimmed,
        'limit': limit.toString(),
        if (proximity != null) 'proximity_lat': proximity.$1.toString(),
        if (proximity != null) 'proximity_lng': proximity.$2.toString(),
      };
      final uri = Uri.parse('$_baseUrl/geocode').replace(queryParameters: params);
      final response = await AuthedHttp.send(
        () => http.get(uri, headers: _authedHeaders()),
      );
      if (response.statusCode != 200) {
        debugPrint('GET /geocode: HTTP ${response.statusCode}');
        return const [];
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawList = (data['candidates'] as List).cast<Map<String, dynamic>>();
      return rawList.map(GeocodeCandidate.fromJson).toList();
    } catch (e) {
      debugPrint('GeocodingService.search failed: $e');
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
