import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// POI API Service for communicating with RouteWhisper backend
///
/// Handles HTTP requests to the backend POI discovery endpoint.
class POIApiService {
  // Backend URL - use 10.0.2.2 for Android emulator, localhost for iOS simulator
  static const String baseUrl = 'http://10.0.2.2:8000/api/v1';

  final http.Client _client;

  POIApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Discover POIs along a route
  ///
  /// [encodedPolyline] - Google-encoded polyline from Mapbox route
  /// [categories] - Optional list of POI category filters
  /// [corridorRadiusMiles] - Search radius from route (default 5.0 miles)
  /// [limitPerCategory] - Max POIs per category (default 5)
  ///
  /// Returns [POIResponse] with discovered POIs
  Future<POIResponse> discoverRoutePOIs({
    required String encodedPolyline,
    List<String>? categories,
    double corridorRadiusMiles = 5.0,
    int limitPerCategory = 5,
  }) async {
    final url = Uri.parse('$baseUrl/route/pois');

    final requestBody = {
      'encoded_polyline': encodedPolyline,
      if (categories != null) 'categories': categories,
      'corridor_radius_miles': corridorRadiusMiles,
      'limit_per_category': limitPerCategory,
    };

    print('🔍 POI API Request: ${url.toString()}');
    print('📦 Request body: ${jsonEncode(requestBody).substring(0, 100)}...');

    try {
      final token = AuthService.instance.accessToken;
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('POI request timed out after 30 seconds'),
      );

      print('📡 POI API Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final poiResponse = POIResponse.fromJson(jsonData);

        print('✅ POI Discovery Success: ${poiResponse.totalFound} POIs found');
        print('   Cached: ${poiResponse.cached}');

        return poiResponse;
      } else {
        throw POIApiException(
          'Failed to discover POIs: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      print('❌ POI API Error: $e');
      rethrow;
    }
  }

  /// Close the HTTP client
  void dispose() {
    _client.close();
  }
}

/// POI data model matching backend response
class POI {
  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final String? address;
  final int estimatedDurationMinutes;
  final double? rating;
  final double distanceFromRouteMiles;
  final String? mapboxPoiId;

  POI({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.estimatedDurationMinutes,
    this.rating,
    required this.distanceFromRouteMiles,
    this.mapboxPoiId,
  });

  factory POI.fromJson(Map<String, dynamic> json) {
    return POI(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String?,
      estimatedDurationMinutes: json['estimated_duration_minutes'] as int,
      rating: json['rating'] != null ? (json['rating'] as num).toDouble() : null,
      distanceFromRouteMiles: (json['distance_from_route_miles'] as num).toDouble(),
      mapboxPoiId: json['mapbox_poi_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'estimated_duration_minutes': estimatedDurationMinutes,
      'rating': rating,
      'distance_from_route_miles': distanceFromRouteMiles,
      'mapbox_poi_id': mapboxPoiId,
    };
  }

  /// Get category emoji icon
  String get categoryIcon {
    switch (category) {
      case 'gas_station':
        return '⛽';
      case 'restaurant':
        return '🍽️';
      case 'coffee':
        return '☕';
      case 'hotel':
        return '🏨';
      case 'camping':
        return '🏕️';
      case 'attraction':
        return '🎯';
      case 'shopping':
        return '🛍️';
      case 'scenic':
        return '🏞️';
      case 'museum':
        return '🏛️';
      case 'park':
        return '🌳';
      case 'hospital':
        return '🏥';
      case 'pharmacy':
        return '💊';
      case 'bank':
        return '🏦';
      case 'grocery':
        return '🛒';
      default:
        return '📍';
    }
  }

  /// Get human-readable category name
  String get categoryName {
    return category
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  /// Format distance for display
  String get distanceFormatted {
    if (distanceFromRouteMiles < 0.1) {
      return 'On route';
    } else if (distanceFromRouteMiles < 1.0) {
      return '${(distanceFromRouteMiles * 5280).round()} ft';
    } else {
      return '${distanceFromRouteMiles.toStringAsFixed(1)} mi';
    }
  }

  /// Format duration for display
  String get durationFormatted {
    if (estimatedDurationMinutes < 60) {
      return '$estimatedDurationMinutes min';
    } else {
      final hours = estimatedDurationMinutes ~/ 60;
      final minutes = estimatedDurationMinutes % 60;
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    }
  }
}

/// POI response model matching backend response
class POIResponse {
  final List<POI> pois;
  final int totalFound;
  final bool cached;
  final List<double> corridorBounds;

  POIResponse({
    required this.pois,
    required this.totalFound,
    required this.cached,
    required this.corridorBounds,
  });

  factory POIResponse.fromJson(Map<String, dynamic> json) {
    return POIResponse(
      pois: (json['pois'] as List)
          .map((poiJson) => POI.fromJson(poiJson as Map<String, dynamic>))
          .toList(),
      totalFound: json['total_found'] as int,
      cached: json['cached'] as bool,
      corridorBounds: (json['corridor_bounds'] as List)
          .map((e) => (e as num).toDouble())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pois': pois.map((poi) => poi.toJson()).toList(),
      'total_found': totalFound,
      'cached': cached,
      'corridor_bounds': corridorBounds,
    };
  }
}

/// Custom exception for POI API errors
class POIApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  POIApiException(
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  @override
  String toString() {
    final buffer = StringBuffer('POIApiException: $message');
    if (statusCode != null) {
      buffer.write(' (Status: $statusCode)');
    }
    if (responseBody != null) {
      buffer.write('\nResponse: $responseBody');
    }
    return buffer.toString();
  }
}
