import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import '../models/waypoint.dart';
import '../widgets/poi_confirmation_sheet.dart';
import '../widgets/poi_dashboard.dart';
import '../main.dart'; // navigatorKey
import 'navigation_host_bridge.dart';
import 'navigation_service.dart';

enum NavigationState {
  idle,
  calculating,
  navigating,
  completed,
  cancelled,
}

/// Drives the Flutter side of navigation by consuming a [NavigationHostBridge].
///
/// Ownership rules (see [NavigationHostBridge] docs for the full contract):
///   - Native owns runtime state (route geometry, location, voice, route
///     progress, leg index). We don't mirror it here.
///   - This controller + [NavigationService] + [WaypointManager] own intent
///     state (lifecycle, waypoint plans, POI selections).
class NavigationController extends ChangeNotifier {
  final NavigationHostBridge _bridge;

  NavigationController({NavigationHostBridge? bridge})
      : _bridge = bridge ?? MethodChannelNavigationHostBridge();

  NavigationState _currentState = NavigationState.idle;

  NavigationState get currentState => _currentState;
  bool get isNavigating => _currentState == NavigationState.navigating;

  void initialize() {
    _bridge.setHandlers(NavigationHostHandlers(
      onRoutePolyline: _onRoutePolyline,
      onWaypointArrived: _onWaypointArrived,
      onAutoDeparture: _onAutoDeparture,
      onDestinationArrived: _onDestinationArrived,
      onShowOverlay: _onShowOverlay,
      onPopRoute: _onPopRoute,
      onRequestPoisOnMap: _onRequestPoisOnMap,
      onPoiTapped: _onPoiTapped,
      onRecommendationAccept: _onRecommendationAccept,
      onRecommendationDismiss: _onRecommendationDismiss,
      onSuggestStopRequested: _onSuggestStopRequested,
      onWaypointProgressRequest: _onWaypointProgressRequest,
    ));
    debugPrint('🎯 NavigationController initialized');
  }

  NavigationHostBridge get bridge => _bridge;

  Future<String?> calculateRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    List<List<double>>? waypoints,
    List<String>? waypointNames,
  }) async {
    _setState(NavigationState.calculating);
    try {
      final result = await _bridge.calculateRoute(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
        waypoints: waypoints,
        waypointNames: waypointNames,
      );
      _setState(NavigationState.navigating);
      return result;
    } catch (e) {
      debugPrint('❌ calculateRoute failed: $e');
      _setState(NavigationState.idle);
      return null;
    }
  }

  Future<String?> updateNavigationRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    List<List<double>>? waypoints,
    List<String>? waypointNames,
  }) async {
    try {
      return await _bridge.updateNavigationRoute(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
        waypoints: waypoints,
        waypointNames: waypointNames,
      );
    } catch (e) {
      debugPrint('❌ updateNavigationRoute failed: $e');
      return null;
    }
  }

  Future<void> cancelNavigation() async {
    _setState(NavigationState.cancelled);
    try {
      await _bridge.cancelNavigation();
    } catch (e) {
      debugPrint('❌ cancelNavigation failed: $e');
    }
    Future.delayed(const Duration(milliseconds: 500), () {
      _setState(NavigationState.idle);
    });
  }

  Future<String?> openMapView() async {
    try {
      return await _bridge.openMapView();
    } catch (e) {
      debugPrint('❌ openMapView failed: $e');
      return null;
    }
  }

  void _setState(NavigationState newState) {
    if (_currentState != newState) {
      debugPrint('🎯 State: $_currentState -> $newState');
      _currentState = newState;
      notifyListeners();
    }
  }

  /// Test-only seam to drive the navigation state machine without going
  /// through the bridge / native side. Used by RecommendationService and
  /// any other test that needs `NavigationService.isNavigating == true`
  /// without standing up a real nav session.
  @visibleForTesting
  void setStateForTesting(NavigationState state) {
    _setState(state);
  }

  // --- inbound event handlers (registered with the bridge in initialize) ---

  void _onRoutePolyline(String polyline) {
    NavigationService.setRoutePolyline(polyline);
    notifyListeners();
  }

  void _onWaypointArrived({
    required int legIndex,
    required double latitude,
    required double longitude,
  }) {
    final intermediates = NavigationService.waypointManager
        .getWaypoints()
        .where((wp) =>
            wp.type != WaypointType.origin &&
            wp.type != WaypointType.destination)
        .toList();

    if (legIndex >= 0 && legIndex < intermediates.length) {
      NavigationService.markWaypointArrival(intermediates[legIndex]);
    } else {
      debugPrint(
        '⚠️ legIndex $legIndex out of range (${intermediates.length})',
      );
    }
  }

  void _onAutoDeparture({
    required double distanceMeters,
    required double speedMph,
  }) {
    final active = NavigationService.activeWaypoint;
    if (active != null) {
      NavigationService.markWaypointDeparture(active, isAutomatic: true);
    }
  }

  void _onDestinationArrived() {
    _setState(NavigationState.completed);
  }

  Map<String, dynamic>? _onWaypointProgressRequest({
    required int legIndex,
    required double distanceMeters,
    required double durationSeconds,
  }) {
    return NavigationService.waypointManager.getWaypointProgressData(
      legIndex: legIndex,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
  }

  void _onShowOverlay(String route) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      debugPrint('❌ showOverlay: no navigator context');
      return;
    }

    final Widget overlay;
    switch (route) {
      case '/poi-discovery':
        overlay = const POIDashboard();
        break;
      default:
        debugPrint('⚠️ Unknown overlay: $route, defaulting to POI');
        overlay = const POIDashboard();
    }

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => PrimaryScrollController(
          controller: scrollController,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: overlay,
          ),
        ),
      ),
    );
  }

  void _onPopRoute() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    if (Navigator.of(ctx).canPop()) {
      Navigator.of(ctx).pop();
    }
  }

  // FAB tap during navigation: fetch POIs (or reuse cached) and push them
  // down to native for on-map rendering. The native side handles markers
  // and the Google-style camera overview.
  Future<void> _onRequestPoisOnMap() async {
    try {
      var response = NavigationService.lastPOIResponse;
      response ??= await NavigationService.discoverPOIs();
      if (response == null || response.pois.isEmpty) {
        debugPrint('⚠️ No POIs to show on map');
        return;
      }
      // The backend currently returns duplicate `poi.id` values for every POI
      // in a response (truncates `mapbox_poi_id` to a prefix that's shared
      // across all Mapbox POI URNs). Until that's fixed, identify POIs across
      // the bridge by their position in this response. See memory:
      // backend_poi_id_bug.md.
      final pois = <Map<String, dynamic>>[];
      for (var i = 0; i < response.pois.length; i++) {
        final poi = response.pois[i];
        pois.add({
          'id': i.toString(),
          'lat': poi.latitude,
          'lng': poi.longitude,
          'category': poi.category,
        });
      }
      await _bridge.showPoisOnMap(pois: pois, bounds: response.corridorBounds);
    } catch (e) {
      debugPrint('❌ requestPoisOnMap failed: $e');
    }
  }

  // User tapped a marker on the native map. The "poiId" here is the index
  // into the cached response (see _onRequestPoisOnMap for why we don't trust
  // the backend's poi.id). Native made flutterContainer visible before
  // sending this event so the modal has somewhere to draw — we hide it
  // again once the sheet dismisses (either path).
  void _onPoiTapped(String poiId) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final response = NavigationService.lastPOIResponse;
    final index = int.tryParse(poiId);
    if (response == null ||
        index == null ||
        index < 0 ||
        index >= response.pois.length) {
      debugPrint('⚠️ poiTapped fired with bad index: $poiId');
      await _bridge.hideOverlay();
      return;
    }
    final poi = response.pois[index];

    final navigator = Navigator.of(ctx);
    await navigator.push(_TransparentSheetRoute(
      child: POIConfirmationSheet(poi: poi),
    ));
    await _bridge.hideOverlay();
  }

  // Native banner button: "Add stop". Same flow as the Flutter
  // RecommendationCard — convert the suggestion's POI to a waypoint, run
  // an in-place route update, then tell the service it was accepted so
  // it suppresses the POI for the rest of the trip.
  Future<void> _onRecommendationAccept(String poiId) async {
    final service = NavigationService.recommendations;
    final suggestion = service.current;
    if (suggestion == null || suggestion.poi.id != poiId) {
      debugPrint('⚠️ recommendationAccept for stale poiId $poiId; ignoring');
      service.dismissCurrent();
      return;
    }

    final poi = suggestion.poi;
    final waypoint = Waypoint.fromPOI(
      poi,
      NavigationService.waypointManager.getWaypoints().length,
    );
    NavigationService.waypointManager.addWaypoint(waypoint);

    if (NavigationService.isNavigating &&
        NavigationService.currentRoute != null) {
      final route = NavigationService.currentRoute!;
      final intermediates = NavigationService.waypointManager
          .getWaypoints()
          .where((w) =>
              w.type != WaypointType.origin &&
              w.type != WaypointType.destination)
          .toList();
      await updateNavigationRoute(
        originLat: route.originLat,
        originLng: route.originLng,
        destLat: route.destLat,
        destLng: route.destLng,
        waypoints: intermediates.map((w) => [w.longitude, w.latitude]).toList(),
        waypointNames: intermediates.map((w) => w.name).toList(),
      );
    }
    service.acceptCurrent();
  }

  // Native banner button: "Not now". Suppress for the rest of the trip.
  void _onRecommendationDismiss(String poiId) {
    NavigationService.recommendations.dismissCurrent();
  }

  // Native FAB: user tapped "Suggest a stop". Force a one-off poll that
  // bypasses the time/per-trip caps.
  Future<void> _onSuggestStopRequested() async {
    await NavigationService.recommendations.forcePoll();
  }
}

/// Bottom-sheet-style route used while the live map is the actual background.
///
/// Why a custom route instead of `showModalBottomSheet`: the underlying
/// Flutter route (NavigationDashboard home screen) has an opaque Scaffold
/// that would paint over the native map. With `opaque: true`, Flutter detaches
/// the route below so it doesn't paint at all — combined with a transparent
/// FlutterSurfaceView on the native side, the native map shows through
/// everywhere this route's content is transparent. The scrim and sheet are
/// painted explicitly here.
class _TransparentSheetRoute<T> extends PageRoute<T> {
  final Widget child;

  _TransparentSheetRoute({required this.child});

  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _SheetScaffold(child: child);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation);
    return SlideTransition(position: slide, child: child);
  }
}

class _SheetScaffold extends StatelessWidget {
  final Widget child;

  const _SheetScaffold({required this.child});

  @override
  Widget build(BuildContext context) {
    // A bare Scaffold gives the sheet a ScaffoldMessenger so SnackBars fired
    // from inside the sheet have somewhere to render *while the sheet is
    // still on top* — important for the "undo" snack that pairs with the
    // route update.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        behavior: HitTestBehavior.opaque,
        child: Container(
          // Semi-opaque scrim — alpha-blends with the native map underneath
          // because the FlutterSurfaceView is in renderTransparently mode.
          color: Colors.black54,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // absorb taps so they don't pop the route
            child: Material(
              type: MaterialType.transparency,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
