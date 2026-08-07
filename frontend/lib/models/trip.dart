import 'package:flutter/foundation.dart';

import 'trip_pin.dart';

/// In-memory representation of a saved trip — mirrors the backend's
/// `Trip` Beanie document. See docs/trip-planning-brief.md.
///
/// This is the slice-A skeleton; `pins` and `days` are stored as raw
/// dicts here because their structure is still being designed in slices
/// C/D. The Dart side passes them through unchanged for now.
@immutable
class Trip {
  /// Server-assigned id. `null` only on an unsaved draft built locally.
  final String? id;
  final String name;

  final String originName;
  final double originLat;
  final double originLng;

  final String destinationName;
  final double destinationLat;
  final double destinationLng;

  /// ISO date string (e.g. "2026-08-15") or null for "anytime".
  final String? startDate;
  final String? endDate;
  /// "HH:MM" wall-clock string or null when there's no arrival constraint.
  final String? arrivalTime;

  final int dailyDriveCapHours;
  final String timeBudgetMode; // hurry | moderate | discovery

  /// Canvas anchor pins (slice C+). Typed as [TripPin] now that the
  /// canvas widgets need direct field access. Backend stores as raw
  /// JSON; toJson()/fromJson() handles the round-trip.
  final List<TripPin> pins;
  final List<Map<String, dynamic>> days;

  final String? notes;

  /// Mapbox precision-6 encoded polyline of the driving route. Server
  /// computes it at trip-create via Mapbox Directions and persists it
  /// so the canvas can render the route without re-asking the network.
  /// Null on legacy trips created before this field existed.
  final String? polyline;

  /// Real drive stats from the same Mapbox Directions call that produced
  /// [polyline]. Null until a polyline has been computed at least once.
  final double? distanceMiles;
  final int? durationMinutes;

  /// Monologue v1 — see docs/companion-monologue-v1-plan.md.
  /// Two independent dimensions of trip vibe:
  /// - [narrationThemes] tilts what the companion talks about
  ///   (history, landscape, food_culture, quirky)
  /// - [stopInterests] surfaces "pull off here" cards; each entry is
  ///   `{category, detail}` where category ∈ food/entertainment/
  ///   attractions/shopping and detail is an optional free-text
  ///   qualifier ("Mexican, hole-in-the-wall").
  final List<String> narrationThemes;
  final List<Map<String, dynamic>> stopInterests;

  /// ISO-8601 timestamps from the server. Local-only drafts leave both null.
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Trip({
    this.id,
    required this.name,
    required this.originName,
    required this.originLat,
    required this.originLng,
    required this.destinationName,
    required this.destinationLat,
    required this.destinationLng,
    this.startDate,
    this.endDate,
    this.arrivalTime,
    this.dailyDriveCapHours = 6,
    this.timeBudgetMode = 'moderate',
    this.pins = const <TripPin>[],
    this.days = const [],
    this.notes,
    this.polyline,
    this.distanceMiles,
    this.durationMinutes,
    this.narrationThemes = const ['history'],
    this.stopInterests = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'] as String?,
        name: json['name'] as String,
        originName: json['origin_name'] as String,
        originLat: (json['origin_lat'] as num).toDouble(),
        originLng: (json['origin_lng'] as num).toDouble(),
        destinationName: json['destination_name'] as String,
        destinationLat: (json['destination_lat'] as num).toDouble(),
        destinationLng: (json['destination_lng'] as num).toDouble(),
        startDate: json['start_date'] as String?,
        endDate: json['end_date'] as String?,
        arrivalTime: json['arrival_time'] as String?,
        dailyDriveCapHours: (json['daily_drive_cap_hours'] as int?) ?? 6,
        timeBudgetMode:
            (json['time_budget_mode'] as String?) ?? 'moderate',
        pins: ((json['pins'] as List?) ?? const [])
            .map((e) => TripPin.fromJson(e as Map<String, dynamic>))
            .toList(),
        days: ((json['days'] as List?) ?? const [])
            .cast<Map<String, dynamic>>(),
        notes: json['notes'] as String?,
        polyline: json['polyline'] as String?,
        distanceMiles: (json['distance_miles'] as num?)?.toDouble(),
        durationMinutes: json['duration_minutes'] as int?,
        narrationThemes: ((json['narration_themes'] as List?) ?? const ['history'])
            .map((e) => e.toString())
            .toList(),
        stopInterests: ((json['stop_interests'] as List?) ?? const [])
            .cast<Map<String, dynamic>>(),
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
        updatedAt: json['updated_at'] != null
            ? DateTime.tryParse(json['updated_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        // id only included on update; create omits it so the server
        // assigns. We include it here unconditionally — the server's
        // POST handler ignores it.
        if (id != null) 'id': id,
        'name': name,
        'origin_name': originName,
        'origin_lat': originLat,
        'origin_lng': originLng,
        'destination_name': destinationName,
        'destination_lat': destinationLat,
        'destination_lng': destinationLng,
        'start_date': startDate,
        'end_date': endDate,
        'arrival_time': arrivalTime,
        'daily_drive_cap_hours': dailyDriveCapHours,
        'time_budget_mode': timeBudgetMode,
        'pins': pins.map((p) => p.toJson()).toList(),
        'days': days,
        'notes': notes,
        // Server overrides on save when origin/destination change; we
        // include it here so a no-op PUT preserves the value.
        if (polyline != null) 'polyline': polyline,
        if (distanceMiles != null) 'distance_miles': distanceMiles,
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
        'narration_themes': narrationThemes,
        'stop_interests': stopInterests,
      };

  Trip copyWith({
    String? id,
    String? name,
    String? originName,
    double? originLat,
    double? originLng,
    String? destinationName,
    double? destinationLat,
    double? destinationLng,
    String? startDate,
    String? endDate,
    String? arrivalTime,
    int? dailyDriveCapHours,
    String? timeBudgetMode,
    List<TripPin>? pins,
    List<Map<String, dynamic>>? days,
    String? notes,
    String? polyline,
    double? distanceMiles,
    int? durationMinutes,
    List<String>? narrationThemes,
    List<Map<String, dynamic>>? stopInterests,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearStartDate = false,
    bool clearEndDate = false,
    bool clearArrivalTime = false,
    bool clearNotes = false,
  }) =>
      Trip(
        id: id ?? this.id,
        name: name ?? this.name,
        originName: originName ?? this.originName,
        originLat: originLat ?? this.originLat,
        originLng: originLng ?? this.originLng,
        destinationName: destinationName ?? this.destinationName,
        destinationLat: destinationLat ?? this.destinationLat,
        destinationLng: destinationLng ?? this.destinationLng,
        startDate: clearStartDate ? null : (startDate ?? this.startDate),
        endDate: clearEndDate ? null : (endDate ?? this.endDate),
        arrivalTime:
            clearArrivalTime ? null : (arrivalTime ?? this.arrivalTime),
        dailyDriveCapHours: dailyDriveCapHours ?? this.dailyDriveCapHours,
        timeBudgetMode: timeBudgetMode ?? this.timeBudgetMode,
        pins: pins ?? this.pins,
        days: days ?? this.days,
        notes: clearNotes ? null : (notes ?? this.notes),
        polyline: polyline ?? this.polyline,
        distanceMiles: distanceMiles ?? this.distanceMiles,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        narrationThemes: narrationThemes ?? this.narrationThemes,
        stopInterests: stopInterests ?? this.stopInterests,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
