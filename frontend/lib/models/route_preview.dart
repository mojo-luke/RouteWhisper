import 'package:flutter/foundation.dart';

import 'trip_pin.dart';

/// Wire-shape mirror of backend `RoutePreview` Beanie document (see
/// app/services/route_preview.py). Fetched by the trip-creation wizard
/// to show "here's what this drive is" before the trip is saved —
/// real stats immediately, rundown + hotspots filled in progressively
/// by a background LLM call the client polls for.
///
/// Unlike [RouteMonologue] this is text-only (no audio) and cached by
/// polyline alone, not polyline+vibe — see route_preview.py for why.
@immutable
class RoutePreview {
  final String polylineHash;
  final String polyline;
  final PreviewStatus status;
  final String stage; // routing | towns | authoring | done
  final double distanceMiles;
  final int durationMinutes;
  final List<PreviewTown> towns;
  final String rundown;
  final List<PreviewHotspot> hotspots;
  final String? error;

  const RoutePreview({
    required this.polylineHash,
    required this.polyline,
    required this.status,
    required this.stage,
    required this.distanceMiles,
    required this.durationMinutes,
    required this.towns,
    required this.rundown,
    required this.hotspots,
    this.error,
  });

  bool get isReady => status == PreviewStatus.ready;
  bool get isFailed => status == PreviewStatus.failed;

  String get distanceLabel => '${distanceMiles.round()} mi';

  String get durationLabel {
    final h = durationMinutes ~/ 60;
    final m = durationMinutes % 60;
    if (h == 0) return '$m min';
    return '$h hr $m min';
  }

  factory RoutePreview.fromJson(Map<String, dynamic> json) => RoutePreview(
        polylineHash: (json['polyline_hash'] ?? '') as String,
        polyline: (json['polyline'] ?? '') as String,
        status: _statusFromString(json['status'] as String?),
        stage: (json['stage'] ?? 'routing') as String,
        distanceMiles: (json['distance_miles'] as num?)?.toDouble() ?? 0.0,
        durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
        towns: ((json['towns'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(PreviewTown.fromJson)
            .toList(),
        rundown: (json['rundown'] ?? '') as String,
        hotspots: ((json['hotspots'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(PreviewHotspot.fromJson)
            .toList(),
        error: json['error'] as String?,
      );
}

enum PreviewStatus { pending, ready, failed }

PreviewStatus _statusFromString(String? s) {
  switch (s) {
    case 'ready':
      return PreviewStatus.ready;
    case 'failed':
      return PreviewStatus.failed;
    default:
      return PreviewStatus.pending;
  }
}

@immutable
class PreviewTown {
  final String name;
  final double lat;
  final double lng;

  const PreviewTown({required this.name, required this.lat, required this.lng});

  factory PreviewTown.fromJson(Map<String, dynamic> json) => PreviewTown(
        name: (json['name'] ?? '') as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );
}

/// One curated highlight along the route. Anchored to the nearest
/// extracted town, not individually geocoded — "near Truckee", not a
/// pinpoint. [toPin] is the whole reuse story with the trip canvas: it
/// becomes a plain `suggested` pin, so the canvas's existing promote/
/// dismiss chips and rendering apply with no new pin type.
@immutable
class PreviewHotspot {
  final String id;
  final String title;
  final String town;
  final double lat;
  final double lng;
  final String theme; // history | landscape | food_culture | quirky
  final String blurb;
  final String? detourHint;

  const PreviewHotspot({
    required this.id,
    required this.title,
    required this.town,
    required this.lat,
    required this.lng,
    required this.theme,
    required this.blurb,
    this.detourHint,
  });

  factory PreviewHotspot.fromJson(Map<String, dynamic> json) => PreviewHotspot(
        id: (json['id'] ?? '') as String,
        title: (json['title'] ?? '') as String,
        town: (json['town'] ?? '') as String,
        lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
        theme: (json['theme'] ?? 'quirky') as String,
        blurb: (json['blurb'] ?? '') as String,
        detourHint: json['detour_hint'] as String?,
      );

  TripPin toPin() => TripPin(
        type: 'suggested',
        id: 'hs-$id',
        name: title,
        lat: lat,
        lng: lng,
      );
}
