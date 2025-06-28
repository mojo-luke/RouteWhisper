import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';

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

class NavigationController {
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

  // Callbacks
  Function(NavigationState)? onStateChanged;
  Function(String)? onError;
  Function(RoutePoint)? onLocationUpdate;

  NavigationState get currentState => _currentState;
  bool get isNavigating => _currentState == NavigationState.navigating;
  bool get isSimulating => _simulationTimer?.isActive ?? false;

  void initialize() {
    _channel.setMethodCallHandler(_handleMethodCall);
    print('🎯 NavigationController initialized');
  }

  Future<void> _handleMethodCall(MethodCall call) async {
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
        onError?.call(error);
        break;
    }
  }

  // Public API
  Future<String?> calculateRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    print('🎯 Calculating route from Flutter');
    _setState(NavigationState.calculating);

    try {
      final result = await _channel.invokeMethod('calculateRoute', {
        'originLat': originLat,
        'originLng': originLng,
        'destLat': destLat,
        'destLng': destLng,
      });

      return result?.toString();
    } catch (e) {
      print('❌ Route calculation failed: $e');
      _setState(NavigationState.idle);
      onError?.call('Route calculation failed: $e');
      return null;
    }
  }

  Future<void> startNavigation() async {
    if (_currentState != NavigationState.ready) {
      onError?.call('Cannot start navigation from state: $_currentState');
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
      onStateChanged?.call(newState);
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
      onError?.call('Failed to parse route data: $e');
    }
  }

  void _handleLocationUpdate(Map<String, dynamic> data) {
    // Handle any location updates from native side if needed
  }

  // Simulation logic (moved from Android)
  void _startSimulation() {
    if (_routePoints.isEmpty) {
      onError?.call('No route points for simulation');
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

    // Send to native side and callbacks
    _sendLocationUpdate(updatedPoint);
    onLocationUpdate?.call(updatedPoint);

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
