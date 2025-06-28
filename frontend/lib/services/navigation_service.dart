import 'package:flutter/services.dart';

// Navigation state enum (top-level, not inside class)
enum NavigationState {
  idle,
  calculating,
  ready,
  navigating,
  paused,
  completed,
  cancelled,
}

// Add route information tracking
class RouteInfo {
  final double originLat;
  final double originLng;
  final double destLat;
  final double destLng;
  final String originName;
  final String destName;

  RouteInfo({
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
    this.originName = "Current Location",
    this.destName = "Destination",
  });
}

// Navigation methods we'll implement via platform channels
class NavigationService {
  static const MethodChannel _channel = MethodChannel(
    'routewhisper.com/navigation',
  );

  // Current state
  static NavigationState _currentState = NavigationState.idle;
  static RouteInfo? _currentRoute;

  // State change callback
  static Function(NavigationState)? onStateChanged;
  static Function(String)? onError;

  // Simulation mode for testing
  static bool _simulationMode = true; // Enable for emulator testing

  static void initialize() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static Future<void> _handleMethodCall(MethodCall call) async {
    print('📱 Flutter received method call: ${call.method}'); // DEBUG
    switch (call.method) {
      case 'navigationStateChanged':
        final stateString = call.arguments['state'] as String;
        final newState = NavigationState.values.firstWhere(
          (state) => state.name.toLowerCase() == stateString.toLowerCase(),
          orElse: () => NavigationState.idle,
        );

        _currentState = newState;
        onStateChanged?.call(newState);
        break;

      case 'navigationError':
        final error = call.arguments['error'] as String;
        onError?.call(error);
        break;
    }
  }

  static NavigationState get currentState => _currentState;
  static RouteInfo? get currentRoute => _currentRoute;

  static bool get isNavigating => _currentState == NavigationState.navigating;
  static bool get canStart => _currentState == NavigationState.ready;
  static bool get canCancel => [
    NavigationState.calculating,
    NavigationState.ready,
    NavigationState.navigating,
  ].contains(_currentState);

  // Enable/disable simulation mode
  static void setSimulationMode(bool enabled) {
    _simulationMode = enabled;
    print('📱 Simulation mode: ${enabled ? "ENABLED" : "DISABLED"}');
  }

  static Future<String?> startNavigation({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    print('📱 Flutter calling startNavigation...'); // DEBUG

    // Store route info
    _currentRoute = RouteInfo(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
      originName: "San Francisco, CA",
      destName: "Los Angeles, CA",
    );

    if (_simulationMode) {
      return _simulateNavigation(originLat, originLng, destLat, destLng);
    }

    try {
      final result = await _channel.invokeMethod('startNavigation', {
        'originLat': originLat,
        'originLng': originLng,
        'destLat': destLat,
        'destLng': destLng,
      });
      print('📱 Flutter startNavigation result: $result'); // DEBUG
      return result?.toString();
    } catch (e) {
      print('📱 Flutter startNavigation error: $e'); // DEBUG
      return 'Error: $e';
    }
  }

  // Simulate navigation flow for testing
  static Future<String?> _simulateNavigation(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) async {
    print('🎭 SIMULATION: Starting navigation simulation');

    // Simulate state progression
    _updateState(NavigationState.calculating);

    // Simulate route calculation delay
    await Future.delayed(const Duration(seconds: 2));
    _updateState(NavigationState.ready);

    await Future.delayed(const Duration(seconds: 1));
    _updateState(NavigationState.navigating);

    // Simulate navigation progress
    _simulateNavigationProgress();

    return 'Simulation started';
  }

  static void _simulateNavigationProgress() {
    // Simulate a 30-second navigation
    Future.delayed(const Duration(seconds: 30), () {
      _updateState(NavigationState.completed);

      // Reset to idle after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        _updateState(NavigationState.idle);
        _currentRoute = null; // Clear route
      });
    });
  }

  static void _updateState(NavigationState newState) {
    _currentState = newState;
    onStateChanged?.call(newState);
    print('🎭 SIMULATION: State changed to ${newState.name}');
  }

  static Future<String?> cancelNavigation() async {
    print('📱 Flutter calling cancelNavigation...'); // DEBUG

    if (_simulationMode) {
      _updateState(NavigationState.cancelled);
      Future.delayed(const Duration(milliseconds: 500), () {
        _updateState(NavigationState.idle);
        _currentRoute = null; // Clear route
      });
      return 'Navigation cancelled (simulated)';
    }

    try {
      final result = await _channel.invokeMethod('cancelNavigation');
      print('📱 Flutter cancelNavigation result: $result'); // DEBUG
      return result?.toString();
    } catch (e) {
      print('📱 Flutter cancelNavigation error: $e'); // DEBUG
      return 'Error: $e';
    }
  }

  static Future<String?> openMapView() async {
    print('📱 Flutter calling openMapView...'); // DEBUG

    if (_simulationMode && _currentRoute != null) {
      print('🎭 SIMULATION: Opening map with simulated navigation');
      // Pass route info and simulation mode to MapActivity
      try {
        final result = await _channel.invokeMethod('openMapView', {
          'simulationMode': true,
          'navigationState': _currentState.name,
          'originLat': _currentRoute!.originLat,
          'originLng': _currentRoute!.originLng,
          'destLat': _currentRoute!.destLat,
          'destLng': _currentRoute!.destLng,
        });
        return result?.toString();
      } catch (e) {
        print('📱 Flutter openMapView error: $e');
        return 'Error: $e';
      }
    }

    try {
      final result = await _channel.invokeMethod('openMapView');
      print('📱 Flutter openMapView result: $result'); // DEBUG
      return result?.toString();
    } catch (e) {
      print('📱 Flutter openMapView error: $e'); // DEBUG
      return 'Error: $e';
    }
  }

  static void setNavigationCallbacks({
    Function()? onMapReady,
    Function(Map<String, dynamic>)? onRouteReady,
    Function(String)? onError,
    Function()? onNavigationStopped,
  }) {
    // Note: Since we're using a separate activity, callbacks won't work the same way
    // We'll handle status through the activities directly
  }
}
