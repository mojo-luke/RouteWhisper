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

  /// Request/response: native asks Flutter to format the next-waypoint
  /// progress card. Flutter returns `{name, distanceFormatted, etaFormatted,
  /// stopIndicator, ...}` or null when there's nothing to show (final leg).
  /// **Native trigger:** `MapActivity` `RouteProgressObserver` callback.
  final Map<String, dynamic>? Function({
    required int legIndex,
    required double distanceMeters,
    required double durationSeconds,
  }) onWaypointProgressRequest;

  const NavigationHostHandlers({
    required this.onRoutePolyline,
    required this.onWaypointArrived,
    required this.onAutoDeparture,
    required this.onDestinationArrived,
    required this.onShowOverlay,
    required this.onPopRoute,
    required this.onWaypointProgressRequest,
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

      case 'calculateWaypointProgress':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        return h.onWaypointProgressRequest(
          legIndex: data['legIndex'] as int,
          distanceMeters: (data['distanceMeters'] as num).toDouble(),
          durationSeconds: (data['durationSeconds'] as num).toDouble(),
        );
    }
    return null;
  }
}
