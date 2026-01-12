import 'package:uuid/uuid.dart';
import 'package:frontend/services/poi_api_service.dart';

/// Waypoint for route navigation with stop time tracking and personalization
class Waypoint {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final WaypointType type;
  final WaypointStatus status;
  final int order;

  // Optional: reference to source data
  final POI? sourcePOI;
  final String? address;

  // ========== STOP TIME TRACKING ==========

  // Planned stop duration (user-editable)
  final int estimatedDurationMinutes;

  // Actual stop tracking
  final DateTime? arrivalTime; // When user arrived
  final DateTime? departureTime; // When user left
  final int? actualDurationMinutes; // Calculated: departure - arrival
  final bool? isAutomaticDeparture; // True if departure auto-detected

  // Stop behavior
  final bool requiresConfirmation; // Pause for user confirmation?
  final bool autoDepart; // Auto-continue after N minutes?
  final int? autoDepartMinutes; // If autoDepart, wait duration

  Waypoint({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.type,
    this.status = WaypointStatus.pending,
    required this.order,
    this.sourcePOI,
    this.address,
    this.estimatedDurationMinutes = 15, // Default 15 min
    this.arrivalTime,
    this.departureTime,
    this.actualDurationMinutes,
    this.isAutomaticDeparture,
    this.requiresConfirmation = true,
    this.autoDepart = false,
    this.autoDepartMinutes,
  });

  /// Calculate actual duration if both times available
  int? get calculatedDuration {
    if (arrivalTime != null && departureTime != null) {
      return departureTime!.difference(arrivalTime!).inMinutes;
    }
    return actualDurationMinutes;
  }

  /// Mark arrival at waypoint (records timestamp)
  Waypoint markArrival() {
    return copyWith(
      arrivalTime: DateTime.now(),
      status: WaypointStatus.active,
    );
  }

  /// Mark departure from waypoint (records timestamp and calculates duration)
  Waypoint markDeparture({bool isAutomatic = false}) {
    final now = DateTime.now();
    final duration = arrivalTime != null
        ? now.difference(arrivalTime!).inMinutes
        : null;

    return copyWith(
      departureTime: now,
      actualDurationMinutes: duration,
      status: WaypointStatus.completed,
      isAutomaticDeparture: isAutomatic,
    );
  }

  /// Factory: Create waypoint from POI
  factory Waypoint.fromPOI(
    POI poi,
    int order, {
    int? estimatedDurationMinutes,
  }) {
    return Waypoint(
      id: const Uuid().v4(),
      name: poi.name,
      latitude: poi.latitude,
      longitude: poi.longitude,
      type: WaypointType.poi,
      order: order,
      sourcePOI: poi,
      estimatedDurationMinutes: estimatedDurationMinutes ?? _getDefaultDurationForCategory(poi.category),
    );
  }

  /// Factory: Create manual waypoint from coordinates
  factory Waypoint.manual({
    required String name,
    required double latitude,
    required double longitude,
    required int order,
    String? address,
    int estimatedDurationMinutes = 15,
  }) {
    return Waypoint(
      id: const Uuid().v4(),
      name: name,
      latitude: latitude,
      longitude: longitude,
      type: WaypointType.manual,
      order: order,
      address: address,
      estimatedDurationMinutes: estimatedDurationMinutes,
    );
  }

  /// Factory: Create origin waypoint
  factory Waypoint.origin({
    required double latitude,
    required double longitude,
    String name = 'Start',
  }) {
    return Waypoint(
      id: const Uuid().v4(),
      name: name,
      latitude: latitude,
      longitude: longitude,
      type: WaypointType.origin,
      order: 0,
      estimatedDurationMinutes: 0, // No stop time at origin
      requiresConfirmation: false,
    );
  }

  /// Factory: Create destination waypoint
  factory Waypoint.destination({
    required double latitude,
    required double longitude,
    String name = 'Destination',
    required int order,
  }) {
    return Waypoint(
      id: const Uuid().v4(),
      name: name,
      latitude: latitude,
      longitude: longitude,
      type: WaypointType.destination,
      order: order,
      estimatedDurationMinutes: 0, // No stop time at destination
      requiresConfirmation: false,
    );
  }

  /// Get default stop duration based on POI category
  static int _getDefaultDurationForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'gas_station':
        return 10; // Quick gas stop
      case 'restaurant':
        return 45; // Full meal
      case 'coffee':
      case 'cafe':
        return 20; // Coffee break
      case 'scenic':
      case 'viewpoint':
        return 30; // Photo stop
      case 'park':
        return 60; // Park visit
      case 'rest_area':
        return 15; // Rest stop
      default:
        return 15; // Default
    }
  }

  /// Create a copy with updated fields
  Waypoint copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    WaypointType? type,
    WaypointStatus? status,
    int? order,
    POI? sourcePOI,
    String? address,
    int? estimatedDurationMinutes,
    DateTime? arrivalTime,
    DateTime? departureTime,
    int? actualDurationMinutes,
    bool? isAutomaticDeparture,
    bool? requiresConfirmation,
    bool? autoDepart,
    int? autoDepartMinutes,
  }) {
    return Waypoint(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      type: type ?? this.type,
      status: status ?? this.status,
      order: order ?? this.order,
      sourcePOI: sourcePOI ?? this.sourcePOI,
      address: address ?? this.address,
      estimatedDurationMinutes: estimatedDurationMinutes ?? this.estimatedDurationMinutes,
      arrivalTime: arrivalTime ?? this.arrivalTime,
      departureTime: departureTime ?? this.departureTime,
      actualDurationMinutes: actualDurationMinutes ?? this.actualDurationMinutes,
      isAutomaticDeparture: isAutomaticDeparture ?? this.isAutomaticDeparture,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      autoDepart: autoDepart ?? this.autoDepart,
      autoDepartMinutes: autoDepartMinutes ?? this.autoDepartMinutes,
    );
  }

  /// Convert to JSON (for API communication)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'type': type.name,
      'status': status.name,
      'order': order,
      'address': address,
      'estimated_duration_minutes': estimatedDurationMinutes,
      'arrival_time': arrivalTime?.toIso8601String(),
      'departure_time': departureTime?.toIso8601String(),
      'actual_duration_minutes': actualDurationMinutes,
      'is_automatic_departure': isAutomaticDeparture,
      'waypoint_category': sourcePOI?.category,
    };
  }

  /// Create from JSON
  factory Waypoint.fromJson(Map<String, dynamic> json) {
    return Waypoint(
      id: json['id'],
      name: json['name'],
      latitude: json['latitude'],
      longitude: json['longitude'],
      type: WaypointType.values.byName(json['type']),
      status: WaypointStatus.values.byName(json['status']),
      order: json['order'],
      address: json['address'],
      estimatedDurationMinutes: json['estimated_duration_minutes'] ?? 15,
      arrivalTime: json['arrival_time'] != null
          ? DateTime.parse(json['arrival_time'])
          : null,
      departureTime: json['departure_time'] != null
          ? DateTime.parse(json['departure_time'])
          : null,
      actualDurationMinutes: json['actual_duration_minutes'],
      isAutomaticDeparture: json['is_automatic_departure'],
    );
  }

  @override
  String toString() {
    return 'Waypoint(name: $name, type: $type, status: $status, order: $order)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Waypoint && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Type of waypoint
enum WaypointType {
  origin, // Starting point
  poi, // Created from POI
  manual, // Manually entered coordinates
  search, // From address search
  destination, // Final destination
}

/// Status of waypoint during navigation
enum WaypointStatus {
  pending, // Not yet reached
  active, // Currently at waypoint
  completed, // Departed from waypoint
  skipped, // User skipped this waypoint
}
