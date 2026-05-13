/// A whisper-ready fact returned by the backend `/api/v1/route/facts`.
///
/// `primary` is the conversational summary the narrator speaks.
/// `followUps` is an ordered list (most-interesting first) for the
/// "tell me more" path. `isThin` lets the UI say "that's all I've
/// got on this one" honestly when the source article didn't support
/// additional material.
class RouteFact {
  final double lat;
  final double lng;
  final String articleTitle;
  final String articleUrl;
  final int wikipediaPageid;
  final String primary;
  // Server-relative path to the pre-synthesized mp3 for `primary`.
  // Null when TTS synthesis failed for this line — the device falls
  // back to local Android TTS on the text.
  final String? primaryAudioUrl;
  final List<String> followUps;
  // Same length as `followUps`. Each entry mirrors `primaryAudioUrl`
  // semantics for the corresponding follow-up line.
  final List<String?> followUpAudioUrls;
  final bool isThin;
  final double distanceFromRouteMiles;
  final double rankedScore;

  const RouteFact({
    required this.lat,
    required this.lng,
    required this.articleTitle,
    required this.articleUrl,
    required this.wikipediaPageid,
    required this.primary,
    this.primaryAudioUrl,
    this.followUps = const [],
    this.followUpAudioUrls = const [],
    this.isThin = false,
    required this.distanceFromRouteMiles,
    required this.rankedScore,
  });

  factory RouteFact.fromJson(Map<String, dynamic> json) => RouteFact(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        articleTitle: json['article_title'] as String,
        articleUrl: json['article_url'] as String,
        wikipediaPageid: json['wikipedia_pageid'] as int,
        primary: json['primary'] as String,
        primaryAudioUrl: json['primary_audio_url'] as String?,
        followUps: (json['follow_ups'] as List?)?.cast<String>() ?? const [],
        followUpAudioUrls: (json['follow_up_audio_urls'] as List?)
                ?.map((e) => e as String?)
                .toList() ??
            const [],
        isThin: (json['is_thin'] as bool?) ?? false,
        distanceFromRouteMiles:
            (json['distance_from_route_miles'] as num).toDouble(),
        rankedScore: (json['ranked_score'] as num).toDouble(),
      );
}
