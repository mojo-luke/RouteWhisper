import 'package:flutter/material.dart';
import '../models/waypoint.dart';
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
      onWaypointProgressRequest: _onWaypointProgressRequest,
    ));
    debugPrint('🎯 NavigationController initialized');
  }

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
}
