import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';  // For ChangeNotifier
import 'package:flutter/material.dart';  // For showModalBottomSheet, Colors, etc.
import 'package:flutter/services.dart';
import '../models/waypoint.dart';
import '../widgets/poi_dashboard.dart';
import '../main.dart';  // For navigatorKey
import 'navigation_service.dart';

enum NavigationState {
  idle,
  calculating,
  ready,
  navigating,
  paused,
  completed,
  cancelled,
}

class RoutePoint {
  final double lat;
  final double lng;
  final double bearing;

  RoutePoint({required this.lat, required this.lng, this.bearing = 0.0});

  @override
  String toString() => 'RoutePoint(lat: $lat, lng: $lng, bearing: $bearing)';
}

class NavigationController extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel(
    'routewhisper.com/navigation',
  );

  // State management
  NavigationState _currentState = NavigationState.idle;
  List<RoutePoint> _routePoints = [];
  Timer? _simulationTimer;
  int _currentSimulationIndex = 0;

  // Configuration
  static const Duration _simulationInterval = Duration(milliseconds: 1500);
  static const int _pointSkipCount = 3;

  NavigationState get currentState => _currentState;
  bool get isNavigating => _currentState == NavigationState.navigating;
  bool get isSimulating => _simulationTimer?.isActive ?? false;

  void initialize() {
    _channel.setMethodCallHandler(_handleMethodCall);
    print('🎯 NavigationController initialized');
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    print('📱 Flutter NavigationController received: ${call.method}');

    switch (call.method) {
      case 'routeCalculated':
        print('📱 About to call _handleRouteCalculated');
        try {
          // Cast the arguments to the expected type
          final data = Map<String, dynamic>.from(call.arguments as Map);
          _handleRouteCalculated(data);
          print('📱 _handleRouteCalculated completed successfully');
        } catch (e, stackTrace) {
          print('❌ Error in _handleRouteCalculated: $e');
          print('❌ Stack trace: $stackTrace');
        }
        break;
      case 'locationUpdate':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        _handleLocationUpdate(data);
        break;
      case 'navigationError':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        final error = data['error'] as String;
        notifyListeners();  // Notify Provider of error
        break;
      case 'setRoutePolyline':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        final polyline = data['polyline'] as String;
        print('📍 Received route polyline from Android: ${polyline.substring(0, polyline.length > 50 ? 50 : polyline.length)}...');
        // Store the polyline in NavigationService for POI discovery
        NavigationService.setRoutePolyline(polyline);
        print('✅ Route polyline stored in NavigationService for POI discovery');
        notifyListeners();  // Notify Provider of route polyline
        break;
      case 'waypointArrived':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        _handleWaypointArrived(data);
        break;
      case 'autoDepartureDetected':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        _handleAutoDeparture(data);
        break;
      case 'destinationArrived':
        _handleDestinationArrived();
        break;
      case 'calculateWaypointProgress':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        return _handleCalculateWaypointProgress(data);
      case 'showOverlay':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        _handleShowOverlay(data);
        break;
      // Legacy support for direct openPOIDiscovery calls (can be removed later)
      case 'openPOIDiscovery':
        _handleShowOverlay({'route': '/poi-discovery'});
        break;
    }
    return null;
  }

  // Public API
  Future<String?> calculateRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    List<List<double>>? waypoints, // [[lng, lat], [lng, lat], ...]
    List<String>? waypointNames, // ["Name 1", "Name 2", ...]
  }) async {
    if (waypoints != null && waypoints.isNotEmpty) {
      print('🎯 Calculating route with ${waypoints.length} waypoints from Flutter');
      if (waypointNames != null) {
        print('📍 Waypoint names: $waypointNames');
      }
    } else {
      print('🎯 Calculating route from Flutter');
    }
    _setState(NavigationState.calculating);

    try {
      final Map<String, dynamic> params = {
        'originLat': originLat,
        'originLng': originLng,
        'destLat': destLat,
        'destLng': destLng,
      };

      // Add waypoints if provided
      if (waypoints != null && waypoints.isNotEmpty) {
        params['waypoints'] = waypoints;
        // Add waypoint names if provided
        if (waypointNames != null && waypointNames.isNotEmpty) {
          params['waypointNames'] = waypointNames;
        }
      }

      final result = await _channel.invokeMethod('calculateRoute', params);

      return result?.toString();
    } catch (e) {
      print('❌ Route calculation failed: $e');
      _setState(NavigationState.idle);
      return null;
    }
  }

  Future<void> startNavigation() async {
    if (_currentState != NavigationState.ready) {
      notifyListeners();  // Notify Provider of error
      return;
    }

    print('🎯 Starting navigation from Flutter');
    _setState(NavigationState.navigating);

    // Tell native side to prepare for navigation
    await _channel.invokeMethod('prepareNavigation');

    // Start Flutter-controlled simulation
    _startSimulation();
  }

  Future<void> cancelNavigation() async {
    print('🎯 Cancelling navigation from Flutter');
    _setState(NavigationState.cancelled);
    _stopSimulation();

    await _channel.invokeMethod('cancelNavigation');

    // Reset to idle after brief delay
    Future.delayed(const Duration(milliseconds: 500), () {
      _setState(NavigationState.idle);
      _routePoints.clear();
    });
  }

  Future<String?> openMapView() async {
    try {
      final result = await _channel.invokeMethod('openMapView', {
        'navigationState': _currentState.name,
        'simulationMode': true, // Always use simulation for now
      });
      return result?.toString();
    } catch (e) {
      print('❌ Failed to open map view: $e');
      return null;
    }
  }

  // Private methods
  void _setState(NavigationState newState) {
    if (_currentState != newState) {
      print('🎯 State change: $_currentState -> $newState');
      _currentState = newState;

      // Provider notification
      notifyListeners();
    }
  }

  void _handleRouteCalculated(Map<String, dynamic> data) {
    print('🎯 _handleRouteCalculated called');

    try {
      final points = data['routePoints'] as List<dynamic>;
      print('🎯 Received ${points.length} route points');

      _routePoints = points.map((point) {
        final p = Map<String, dynamic>.from(point as Map);
        return RoutePoint(lat: p['lat'] as double, lng: p['lng'] as double);
      }).toList();

      print('🎯 Route calculated successfully: ${_routePoints.length} points');
      _setState(NavigationState.ready);
    } catch (e, stackTrace) {
      print('❌ Failed to parse route data: $e');
      print('❌ Stack trace: $stackTrace');
      _setState(NavigationState.idle);
    }
  }

  void _handleLocationUpdate(Map<String, dynamic> data) {
    // Handle any location updates from native side if needed
  }

  void _handleWaypointArrived(Map<String, dynamic> data) {
    final legIndex = data['legIndex'] as int;
    final latitude = data['latitude'] as double?;
    final longitude = data['longitude'] as double?;

    print('📍 Flutter: Waypoint arrival - leg $legIndex at ($latitude, $longitude)');

    // Find matching waypoint by leg index
    // Note: Leg 0 = origin→waypoint1, Leg 1 = waypoint1→waypoint2, etc.
    final intermediateWaypoints = NavigationService.waypointManager
        .getWaypoints()
        .where((wp) => wp.type != WaypointType.origin && wp.type != WaypointType.destination)
        .toList();

    if (legIndex >= 0 && legIndex < intermediateWaypoints.length) {
      final waypoint = intermediateWaypoints[legIndex];
      NavigationService.markWaypointArrival(waypoint);

      // Waypoint arrival handled (Provider notifies UI automatically)
    } else {
      print('⚠️ Leg index $legIndex out of range (${intermediateWaypoints.length} intermediate waypoints)');
    }
  }

  void _handleAutoDeparture(Map<String, dynamic> data) {
    final distance = data['distance'] as double;
    final speed = data['speed'] as double;

    print('🚗 Auto-departure: ${distance.toStringAsFixed(1)}m away, ${speed.toStringAsFixed(1)}mph');

    if (NavigationService.activeWaypoint != null) {
      NavigationService.markWaypointDeparture(
        NavigationService.activeWaypoint!,
        isAutomatic: true,
      );
    }
  }

  void _handleDestinationArrived() {
    print('🏁 Destination reached!');
    _setState(NavigationState.completed);
  }

  /// Handle waypoint progress calculation request from Android
  /// Returns formatted progress data or null if waypoint card should be hidden
  Map<String, dynamic>? _handleCalculateWaypointProgress(Map<String, dynamic> data) {
    final legIndex = data['legIndex'] as int;
    final distanceMeters = data['distanceMeters'] as double;
    final durationSeconds = data['durationSeconds'] as double;

    print('📊 Calculating waypoint progress: leg $legIndex, ${distanceMeters.toStringAsFixed(0)}m, ${durationSeconds.toStringAsFixed(0)}s');

    // Use WaypointManager to calculate progress
    final progressData = NavigationService.waypointManager.getWaypointProgressData(
      legIndex: legIndex,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );

    if (progressData != null) {
      print('✅ Waypoint progress: ${progressData['name']}, ${progressData['distanceFormatted']} mi, ${progressData['etaFormatted']}');
    } else {
      print('ℹ️ No waypoint progress to show (final destination or no waypoints)');
    }

    return progressData;
  }

  /// Handle request to open POI discovery from MapActivity
  /// Generic handler for showing Flutter overlays on top of native navigation.
  /// This allows us to modify the UI entirely in Flutter without touching Android code.
  ///
  /// Supported routes:
  ///   - '/poi-discovery': Shows POI discovery dashboard
  ///   - (add more routes here as needed)
  void _handleShowOverlay(Map<String, dynamic> data) {
    final route = data['route'] as String? ?? '/poi-discovery';
    final routeData = data['data'] as String?;

    print('🔍 Opening Flutter overlay: $route');
    if (routeData != null) {
      print('📦 With data: $routeData');
    }

    try {
      final navigatorContext = navigatorKey.currentContext;
      if (navigatorContext == null) {
        print('❌ Cannot open overlay - no navigator context');
        return;
      }

      print('✅ Navigator context found, opening overlay modal...');

      // Determine which widget to show based on route
      Widget overlayWidget;
      switch (route) {
        case '/poi-discovery':
          overlayWidget = const POIDashboard();
          break;
        // Add more routes here in the future:
        // case '/waypoint-manager':
        //   overlayWidget = const WaypointManagerScreen();
        //   break;
        default:
          print('⚠️ Unknown overlay route: $route, defaulting to POI discovery');
          overlayWidget = const POIDashboard();
      }

      // Show as modal bottom sheet with semi-transparent background
      showModalBottomSheet(
        context: navigatorContext,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: overlayWidget,
          ),
        ),
      ).then((_) {
        print('✅ Overlay modal closed');
      }).catchError((error) {
        print('❌ Error showing overlay modal: $error');
      });

      print('✅ Overlay modal initiated');
    } catch (e, stackTrace) {
      print('❌ Exception in _handleShowOverlay: $e');
      print('❌ Stack trace: $stackTrace');
    }
  }

  // Simulation logic (moved from Android)
  void _startSimulation() {
    if (_routePoints.isEmpty) {
      notifyListeners();  // Notify Provider of error
      return;
    }

    print(
      '🎯 Starting Flutter-controlled simulation with ${_routePoints.length} points',
    );
    _currentSimulationIndex = 0;

    // Set initial location
    _sendLocationUpdate(_routePoints[0]);

    // Start timer for subsequent updates
    _simulationTimer = Timer.periodic(_simulationInterval, (_) {
      _simulationStep();
    });
  }

  void _stopSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _currentSimulationIndex = 0;
    print('🎯 Simulation stopped');
  }

  void _simulationStep() {
    if (!isNavigating || _currentSimulationIndex >= _routePoints.length) {
      print('🎯 Simulation completed');
      _setState(NavigationState.completed);
      _stopSimulation();

      // Auto-reset to idle after completion
      Future.delayed(const Duration(seconds: 3), () {
        _setState(NavigationState.idle);
        _routePoints.clear();
      });
      return;
    }

    final point = _routePoints[_currentSimulationIndex];

    // Calculate bearing if we have a next point
    double bearing = 0.0;
    if (_currentSimulationIndex + 1 < _routePoints.length) {
      final nextPoint = _routePoints[_currentSimulationIndex + 1];
      bearing = _calculateBearing(point, nextPoint);
    }

    final updatedPoint = RoutePoint(
      lat: point.lat,
      lng: point.lng,
      bearing: bearing,
    );

    print(
      '🎯 Simulation step $_currentSimulationIndex: ${updatedPoint.lat}, ${updatedPoint.lng}',
    );

    // Send to native side
    _sendLocationUpdate(updatedPoint);

    // Advance to next point
    _currentSimulationIndex += _pointSkipCount;
  }

  Future<void> _sendLocationUpdate(RoutePoint point) async {
    try {
      await _channel.invokeMethod('updateLocation', {
        'lat': point.lat,
        'lng': point.lng,
        'bearing': point.bearing,
      });
    } catch (e) {
      print('❌ Failed to send location update: $e');
    }
  }

  double _calculateBearing(RoutePoint from, RoutePoint to) {
    final lat1 = from.lat * pi / 180;
    final lat2 = to.lat * pi / 180;
    final deltaLng = (to.lng - from.lng) * pi / 180;

    final y = sin(deltaLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLng);

    return atan2(y, x) * 180 / pi;
  }
}
