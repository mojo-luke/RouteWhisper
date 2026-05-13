/// One entry in the user's Discoveries timeline. A pageid can be
/// saved, visited, heard, or any combination — each carries the
/// timestamps for whichever of those happened.
class DiscoveryItem {
  final int wikipediaPageid;
  final String articleTitle;
  final String articleUrl;
  // Friend-voice summary if cached server-side. Null if the user
  // saved/heard the article before the LLM bundle was cached
  // (rare but possible at the boundaries).
  final String? primary;
  final String? firstHeardAt;
  final String? lastHeardAt;
  final String? savedAt;
  final String? visitedAt;
  final String? lastTripId;

  const DiscoveryItem({
    required this.wikipediaPageid,
    required this.articleTitle,
    required this.articleUrl,
    this.primary,
    this.firstHeardAt,
    this.lastHeardAt,
    this.savedAt,
    this.visitedAt,
    this.lastTripId,
  });

  factory DiscoveryItem.fromJson(Map<String, dynamic> json) => DiscoveryItem(
        wikipediaPageid: json['wikipedia_pageid'] as int,
        articleTitle: json['article_title'] as String,
        articleUrl: json['article_url'] as String,
        primary: json['primary'] as String?,
        firstHeardAt: json['first_heard_at'] as String?,
        lastHeardAt: json['last_heard_at'] as String?,
        savedAt: json['saved_at'] as String?,
        visitedAt: json['visited_at'] as String?,
        lastTripId: json['last_trip_id'] as String?,
      );

  bool get isSaved => savedAt != null;
  bool get isVisited => visitedAt != null;
  bool get isHeard => firstHeardAt != null;
}
