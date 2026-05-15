import 'package:flutter/foundation.dart';

/// Wire-shape mirror of backend `RouteMonologue` Beanie document.
///
/// Generated once at trip-save (or vibe-change) on the server and
/// cached globally by (polyline_hash, vibe_hash). The device fetches
/// this artifact at trip-start to drive the companion's spoken-
/// narration track.
///
/// See: docs/companion-monologue-v1-plan.md
@immutable
class RouteMonologue {
  final String polylineHash;
  final String vibeHash;
  final List<String> narrationThemes;
  final List<Map<String, dynamic>> stopInterests;
  final List<MonologueTown> towns;
  final String characterization;
  final List<MonologueUtterance> utterances;
  final List<MonologueStop> stops;

  const RouteMonologue({
    required this.polylineHash,
    required this.vibeHash,
    required this.narrationThemes,
    required this.stopInterests,
    required this.towns,
    required this.characterization,
    required this.utterances,
    required this.stops,
  });

  factory RouteMonologue.fromJson(Map<String, dynamic> json) => RouteMonologue(
        polylineHash: (json['polyline_hash'] ?? '') as String,
        vibeHash: (json['vibe_hash'] ?? '') as String,
        narrationThemes: ((json['narration_themes'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        stopInterests: ((json['stop_interests'] as List?) ?? const [])
            .cast<Map<String, dynamic>>(),
        towns: ((json['towns'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(MonologueTown.fromJson)
            .toList(),
        characterization: (json['characterization'] ?? '') as String,
        utterances: ((json['utterances'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(MonologueUtterance.fromJson)
            .toList(),
        stops: ((json['stops'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(MonologueStop.fromJson)
            .toList(),
      );
}

@immutable
class MonologueTown {
  final String name;
  final double lat;
  final double lng;

  const MonologueTown({
    required this.name,
    required this.lat,
    required this.lng,
  });

  factory MonologueTown.fromJson(Map<String, dynamic> json) => MonologueTown(
        name: (json['name'] ?? '') as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );
}

@immutable
class MonologueUtterance {
  /// 1-based index from the author.
  final int i;

  /// The town (or named landmark) this utterance is anchored to. The
  /// device fires the utterance when GPS enters this town's vicinity.
  final String anchor;

  /// Spoken text — falls back here when audio URL is null/missing.
  final String text;

  /// Pre-synthesized mp3 URL. Relative path like
  /// `/api/v1/audio/monologue/<sha>`; the native side prepends the
  /// backend host before playing. Null if synthesis failed and the
  /// device should use on-board TTS as fallback.
  final String? audioUrl;

  const MonologueUtterance({
    required this.i,
    required this.anchor,
    required this.text,
    this.audioUrl,
  });

  factory MonologueUtterance.fromJson(Map<String, dynamic> json) =>
      MonologueUtterance(
        i: (json['i'] as num?)?.toInt() ?? 0,
        anchor: (json['anchor'] ?? '') as String,
        text: (json['utterance'] ?? '') as String,
        audioUrl: json['audio_url'] as String?,
      );
}

@immutable
class MonologueStop {
  /// One of "food", "entertainment", "attractions", "shopping".
  final String category;
  final String name;
  final String town;
  final double lat;
  final double lng;
  final String? placeFormatted;
  final String? source; // "mapbox" or "osm"
  final double distanceFromRouteMiles;
  final int? tiedToUtterance;
  final String? reason;

  const MonologueStop({
    required this.category,
    required this.name,
    required this.town,
    required this.lat,
    required this.lng,
    required this.distanceFromRouteMiles,
    this.placeFormatted,
    this.source,
    this.tiedToUtterance,
    this.reason,
  });

  factory MonologueStop.fromJson(Map<String, dynamic> json) => MonologueStop(
        category: (json['category'] ?? '') as String,
        name: (json['name'] ?? '') as String,
        town: (json['town'] ?? '') as String,
        lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
        distanceFromRouteMiles:
            (json['distance_from_route_miles'] as num?)?.toDouble() ?? 0.0,
        placeFormatted: json['place_formatted'] as String?,
        source: json['source'] as String?,
        tiedToUtterance: (json['tied_to_utterance'] as num?)?.toInt(),
        reason: json['reason'] as String?,
      );
}
