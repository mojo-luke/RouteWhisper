import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A single pin on the trip canvas. Four types align with the
/// trip-planning brief's pin vocabulary; only 'anchor' is user-
/// placeable in v1. The others are reserved for future slices.
@immutable
class TripPin {
  final String type; // 'anchor' | 'suggested' | 'lodging' | 'wing_it'
  final String id;
  final String name;
  final double lat;
  final double lng;
  final int? dayIndex;
  final String? timeOfDay;

  const TripPin({
    required this.type,
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.dayIndex,
    this.timeOfDay,
  });

  factory TripPin.fromJson(Map<String, dynamic> json) => TripPin(
        type: (json['type'] as String?) ?? 'anchor',
        id: (json['id'] as String?) ?? _uuid.v4(),
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        dayIndex: json['day_index'] as int?,
        timeOfDay: json['time_of_day'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        if (dayIndex != null) 'day_index': dayIndex,
        if (timeOfDay != null) 'time_of_day': timeOfDay,
      };

  TripPin copyWith({
    String? type,
    String? id,
    String? name,
    double? lat,
    double? lng,
    int? dayIndex,
    String? timeOfDay,
    bool clearDayIndex = false,
    bool clearTimeOfDay = false,
  }) =>
      TripPin(
        type: type ?? this.type,
        id: id ?? this.id,
        name: name ?? this.name,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        dayIndex: clearDayIndex ? null : (dayIndex ?? this.dayIndex),
        timeOfDay: clearTimeOfDay ? null : (timeOfDay ?? this.timeOfDay),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripPin &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
