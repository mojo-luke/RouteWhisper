import 'package:flutter/services.dart';

/// The complete native ⇄ Flutter bridge surface for navigation.
///
/// This is the spec the native host (Android `MapActivity` + `MainActivity`,
/// iOS map view controller — when added) must implement. It documents:
///
///   * **Outbound commands** (Flutter → Native): methods on this class.
///   * **Inbound events** (Native → Flutter): callbacks supplied via
///     [NavigationHostHandlers] passed to [setHandlers].
///
/// State ownership rule: native owns runtime state (route geometry, location,
/// voice playback, route progress, leg index). Flutter owns intent state
/// (waypoint plans, POI selections, user preferences). The bridge carries
/// commands one way and events the other; neither side mirrors the other's
/// state.
///
/// To add iOS support later, you do not need a second Dart implementation —
/// [MethodChannelNavigationHostBridge] works for both platforms because
/// method channels are platform-agnostic. What changes is the native code on
/// the other side. Use this file as the spec when you start the Swift work:
/// every method below maps to a `FlutterMethodChannel` handler in iOS.
abstract class NavigationHostBridge {
  /// Launch native navigation with a freshly calculated route.
  ///
  /// [waypoints] is `[[lng, lat], ...]` (note lng-first, matching Mapbox).
  /// Returns a native success message, or null on failure.
  ///
  /// Native effect: starts a new MapActivity (Android) / equivalent on iOS.
  Future<String?> calculateRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    List<List<double>>? waypoints,
    List<String>? waypointNames,
  });

  /// Recompute the route inside the live nav session (no new activity).
  ///
  /// Used when the user adds/removes a waypoint mid-navigation. Critical for
  /// the "never leave navigation" UX rule. Same arg shape as [calculateRoute].
  Future<String?> updateNavigationRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    List<List<double>>? waypoints,
    List<String>? waypointNames,
  });

  /// Stop the active trip session and clear all routes.
  Future<void> cancelNavigation();

  /// Open the native nav surface in display-only mode (no active route).
  Future<String?> openMapView();

  /// Render the given POIs as tappable markers on the live map and animate
  /// the camera to a corridor-bounds overview (Google-style zoom-out). [pois]
  /// is a list of `{id, lat, lng, category}` maps — minimal data the native
  /// renderer needs. [bounds] is `[minLng, minLat, maxLng, maxLat]`. Tapping
  /// a marker on the native side fires [NavigationHostHandlers.onPoiTapped].
  Future<void> showPoisOnMap({
    required List<Map<String, dynamic>> pois,
    required List<double> bounds,
  });

  /// Remove all POI markers and return the camera to follow-mode. Called
  /// after a POI has been committed to the route or when the user dismisses
  /// the POI overlay.
  Future<void> clearPoisFromMap();

  /// Tell the native host to hide the Flutter overlay container so the map
  /// is visible again. Pair with the show-overlay path that fires when a
  /// POI marker is tapped — without this call, the home-screen Flutter route
  /// keeps painting over the live map after the sheet dismisses.
  Future<void> hideOverlay();

  /// Push the current trip-budget status to the native map. Native renders
  /// a small chip near the trip progress card. Pass null to hide the chip
  /// (no budget set / trip ended).
  Future<void> setBudgetStatus({
    required int usedMinutes,
    required int totalMinutes,
  });

  /// Clear the native budget chip (no budget configured for this trip).
  Future<void> clearBudgetStatus();

  /// Push the currently-surfaced recommendation to the native map. Native
  /// renders a bottom banner with [name], [reason], category icon, and
  /// Add stop / Not now buttons. [poiId] is the canonical id (matches
  /// `StopSuggestion.poi.id`), echoed back on the inbound accept/dismiss
  /// events.
  Future<void> setRecommendation({
    required String poiId,
    required String name,
    required String category,
    required String reason,
  });

  /// Clear the native recommendation banner (no current suggestion).
  Future<void> clearRecommendation();

  /// Speak [text] using the native voice player.
  ///
  /// Phase 1 narration text path: routes through Android's `TextToSpeech`
  /// in MainActivity (robotic but always available). Used as a fallback
  /// when the backend didn't synthesize an mp3 for the line.
  /// **Native effect:** TextToSpeech.speak(text).
  Future<void> speakNarration({required String text});

  /// Play a pre-synthesized mp3 from the backend audio endpoint.
  ///
  /// The premium-voice path. Backend has pre-rendered the narration
  /// through OpenAI TTS at trip-prep time; the device just streams
  /// the mp3. Falls back via `speakNarration` if the caller doesn't
  /// have a URL.
  /// **Native effect:** MediaPlayer.setDataSource(url) + start().
  Future<void> playNarrationAudio({required String url});

  /// Push the user's turn-by-turn voice preference to the native side.
  ///
  /// When false, MapActivity drops Mapbox `VoiceInstructions` instead of
  /// generating + playing them — the map still draws the route and the
  /// progress chip, just silently. Narration audio is unaffected.
  /// **Native effect:** sets a flag MapActivity reads inside its
  /// `VoiceInstructionsObserver`.
  Future<void> setTurnByTurnVoiceEnabled({required bool enabled});

  /// Register the inbound-event handlers. Native invokes these via the
  /// underlying transport (method channel) and the bridge dispatches to the
  /// matching field on [handlers]. Calling [setHandlers] again replaces the
  /// previous registration.
  void setHandlers(NavigationHostHandlers handlers);
}

/// Bag of inbound event handlers that the native host invokes.
///
/// Every field corresponds to one method-channel call name on the native side.
/// If you add a new event, add the handler here, document the native trigger,
/// and update [MethodChannelNavigationHostBridge._dispatch].
class NavigationHostHandlers {
  /// Native sends the encoded polyline of the freshly calculated route so
  /// Flutter can run POI discovery against it.
  /// **Native trigger:** `MainActivity.sendRoutePolyline(...)` after Mapbox
  /// returns a route.
  final void Function(String polyline) onRoutePolyline;

  /// Native detected the user reached a waypoint (Mapbox `ArrivalObserver`).
  /// **Native trigger:** `MainActivity.sendWaypointArrived(...)`.
  final void Function({
    required int legIndex,
    required double latitude,
    required double longitude,
  }) onWaypointArrived;

  /// Native detected the user departed a waypoint (>50m away AND >5mph).
  /// **Native trigger:** `MainActivity.sendAutoDepartureDetected(...)`.
  final void Function({
    required double distanceMeters,
    required double speedMph,
  }) onAutoDeparture;

  /// Native detected arrival at the final destination.
  /// **Native trigger:** `MainActivity.sendDestinationArrived()`.
  final void Function() onDestinationArrived;

  /// Native asks Flutter to render a Flutter overlay on top of the live map
  /// (currently `/poi-discovery`). Flutter is responsible for showing the
  /// modal/sheet over the FlutterView embedded in MapActivity.
  /// **Native trigger:** `MapActivity.onFindStopsButtonClick`.
  final void Function(String route) onShowOverlay;

  /// Native asks Flutter to dismiss the current overlay (e.g. user pressed
  /// system back button while overlay was visible).
  /// **Native trigger:** `MapActivity.onBackPressed` when overlay visible.
  final void Function() onPopRoute;

  /// Native asks Flutter to fetch POIs (or use cached ones) and push them
  /// back down via [NavigationHostBridge.showPoisOnMap]. Carries no args.
  /// **Native trigger:** `MapActivity.onFindStopsButtonClick` (the in-nav
  /// "Find Stops" FAB).
  final void Function() onRequestPoisOnMap;

  /// Native reports that the user tapped a POI marker on the map. Flutter
  /// looks the POI up by [poiId] from its cached POI response and shows the
  /// confirmation sheet.
  /// **Native trigger:** `MapActivity` annotation tap listener.
  final void Function(String poiId) onPoiTapped;

  /// User tapped "Add stop" on the native recommendation banner. Flutter
  /// runs the same add-stop flow as the Flutter `RecommendationCard`.
  /// **Native trigger:** banner button in `MapActivity`.
  final void Function(String poiId) onRecommendationAccept;

  /// User tapped "Not now" on the native recommendation banner. Flutter
  /// suppresses this suggestion for the rest of the trip.
  /// **Native trigger:** banner button in `MapActivity`.
  final void Function(String poiId) onRecommendationDismiss;

  /// User tapped the "Suggest a stop" FAB during nav. Flutter runs a manual
  /// poll that bypasses the rate caps.
  /// **Native trigger:** suggestion FAB in `MapActivity`.
  final void Function() onSuggestStopRequested;

  /// Request/response: native asks Flutter to format the next-waypoint
  /// progress card. Flutter returns `{name, distanceFormatted, etaFormatted,
  /// stopIndicator, ...}` or null when there's nothing to show (final leg).
  /// **Native trigger:** `MapActivity` `RouteProgressObserver` callback.
  final Map<String, dynamic>? Function({
    required int legIndex,
    required double distanceMeters,
    required double durationSeconds,
  }) onWaypointProgressRequest;

  /// Native pushes the current vehicle location at the cadence Mapbox's
  /// location observer fires (typically every ~1s while driving). Used
  /// by NarrationService to trigger whispers on proximity to facts.
  /// Speed is mph, may be 0 when stopped.
  /// **Native trigger:** `MapActivity` Mapbox `LocationObserver`.
  final void Function({
    required double latitude,
    required double longitude,
    required double speedMph,
  }) onLocationUpdate;

  const NavigationHostHandlers({
    required this.onRoutePolyline,
    required this.onWaypointArrived,
    required this.onAutoDeparture,
    required this.onDestinationArrived,
    required this.onShowOverlay,
    required this.onPopRoute,
    required this.onRequestPoisOnMap,
    required this.onPoiTapped,
    required this.onRecommendationAccept,
    required this.onRecommendationDismiss,
    required this.onSuggestStopRequested,
    required this.onWaypointProgressRequest,
    required this.onLocationUpdate,
  });
}

/// Concrete bridge implementation backed by a Flutter [MethodChannel]. Works
/// for both Android and iOS; only the native code on the other end differs.
class MethodChannelNavigationHostBridge implements NavigationHostBridge {
  static const String channelName = 'routewhisper.com/navigation';

  final MethodChannel _channel;
  NavigationHostHandlers? _handlers;

  MethodChannelNavigationHostBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_dispatch);
  }

  @override
  Future<String?> calculateRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    List<List<double>>? waypoints,
    List<String>? waypointNames,
  }) async {
    final result = await _channel.invokeMethod('calculateRoute', {
      'originLat': originLat,
      'originLng': originLng,
      'destLat': destLat,
      'destLng': destLng,
      if (waypoints != null && waypoints.isNotEmpty) 'waypoints': waypoints,
      if (waypointNames != null && waypointNames.isNotEmpty)
        'waypointNames': waypointNames,
    });
    return result?.toString();
  }

  @override
  Future<String?> updateNavigationRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    List<List<double>>? waypoints,
    List<String>? waypointNames,
  }) async {
    final result = await _channel.invokeMethod('updateNavigationRoute', {
      'originLat': originLat,
      'originLng': originLng,
      'destLat': destLat,
      'destLng': destLng,
      if (waypoints != null && waypoints.isNotEmpty) 'waypoints': waypoints,
      if (waypointNames != null && waypointNames.isNotEmpty)
        'waypointNames': waypointNames,
    });
    return result?.toString();
  }

  @override
  Future<void> cancelNavigation() async {
    await _channel.invokeMethod('cancelNavigation');
  }

  @override
  Future<String?> openMapView() async {
    final result = await _channel.invokeMethod('openMapView', const {});
    return result?.toString();
  }

  @override
  Future<void> showPoisOnMap({
    required List<Map<String, dynamic>> pois,
    required List<double> bounds,
  }) async {
    await _channel.invokeMethod('showPoisOnMap', {
      'pois': pois,
      'bounds': bounds,
    });
  }

  @override
  Future<void> clearPoisFromMap() async {
    await _channel.invokeMethod('clearPoisFromMap');
  }

  @override
  Future<void> hideOverlay() async {
    await _channel.invokeMethod('hideOverlay');
  }

  @override
  Future<void> setBudgetStatus({
    required int usedMinutes,
    required int totalMinutes,
  }) async {
    await _channel.invokeMethod('setBudgetStatus', {
      'usedMinutes': usedMinutes,
      'totalMinutes': totalMinutes,
    });
  }

  @override
  Future<void> clearBudgetStatus() async {
    await _channel.invokeMethod('clearBudgetStatus');
  }

  @override
  Future<void> setRecommendation({
    required String poiId,
    required String name,
    required String category,
    required String reason,
  }) async {
    await _channel.invokeMethod('setRecommendation', {
      'poiId': poiId,
      'name': name,
      'category': category,
      'reason': reason,
    });
  }

  @override
  Future<void> clearRecommendation() async {
    await _channel.invokeMethod('clearRecommendation');
  }

  @override
  Future<void> speakNarration({required String text}) async {
    await _channel.invokeMethod('speakNarration', {'text': text});
  }

  @override
  Future<void> playNarrationAudio({required String url}) async {
    await _channel.invokeMethod('playNarrationAudio', {'url': url});
  }

  @override
  Future<void> setTurnByTurnVoiceEnabled({required bool enabled}) async {
    await _channel.invokeMethod('setTurnByTurnVoiceEnabled', {'enabled': enabled});
  }

  @override
  void setHandlers(NavigationHostHandlers handlers) {
    _handlers = handlers;
  }

  Future<dynamic> _dispatch(MethodCall call) async {
    final h = _handlers;
    if (h == null) return null;

    switch (call.method) {
      case 'setRoutePolyline':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        h.onRoutePolyline(data['polyline'] as String);
        return null;

      case 'waypointArrived':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        h.onWaypointArrived(
          legIndex: data['legIndex'] as int,
          latitude: (data['latitude'] as num).toDouble(),
          longitude: (data['longitude'] as num).toDouble(),
        );
        return null;

      case 'autoDepartureDetected':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        h.onAutoDeparture(
          distanceMeters: (data['distance'] as num).toDouble(),
          speedMph: (data['speed'] as num).toDouble(),
        );
        return null;

      case 'destinationArrived':
        h.onDestinationArrived();
        return null;

      case 'showOverlay':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        h.onShowOverlay(data['route'] as String? ?? '/poi-discovery');
        return null;

      case 'popRoute':
        h.onPopRoute();
        return null;

      case 'requestPoisOnMap':
        h.onRequestPoisOnMap();
        return null;

      case 'poiTapped':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        h.onPoiTapped(data['poiId'] as String);
        return null;

      case 'recommendationAccept':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        h.onRecommendationAccept(data['poiId'] as String);
        return null;

      case 'recommendationDismiss':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        h.onRecommendationDismiss(data['poiId'] as String);
        return null;

      case 'suggestStopRequested':
        h.onSuggestStopRequested();
        return null;

      case 'calculateWaypointProgress':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        return h.onWaypointProgressRequest(
          legIndex: data['legIndex'] as int,
          distanceMeters: (data['distanceMeters'] as num).toDouble(),
          durationSeconds: (data['durationSeconds'] as num).toDouble(),
        );

      case 'locationUpdate':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        h.onLocationUpdate(
          latitude: (data['latitude'] as num).toDouble(),
          longitude: (data['longitude'] as num).toDouble(),
          speedMph: (data['speedMph'] as num).toDouble(),
        );
        return null;
    }
    return null;
  }
}
