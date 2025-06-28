import 'package:flutter/services.dart';
import 'navigation_controller.dart';

// Export everything from navigation_controller for easier imports
export 'navigation_controller.dart';

// Add route information tracking (keeping this here since it's service-level)
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

// Navigation service - simplified wrapper around NavigationController
class NavigationService {
  static final NavigationController _controller = NavigationController();

  // Current route info
  static RouteInfo? _currentRoute;

  // Delegate to controller
  static NavigationState get currentState => _controller.currentState;
  static bool get isNavigating => _controller.isNavigating;
  static RouteInfo? get currentRoute => _currentRoute;

  static void initialize() {
    _controller.initialize();
  }

  static void setCallbacks({
    Function(NavigationState)? onStateChanged,
    Function(String)? onError,
    Function(RoutePoint)? onLocationUpdate,
  }) {
    _controller.onStateChanged = onStateChanged;
    _controller.onError = onError;
    _controller.onLocationUpdate = onLocationUpdate;
  }

  static Future<String?> startNavigation({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    // Store route info
    _currentRoute = RouteInfo(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
      originName: "San Francisco, CA",
      destName: "Los Angeles, CA",
    );

    // First calculate route
    final result = await _controller.calculateRoute(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
    );

    if (result != null && _controller.currentState == NavigationState.ready) {
      // Then start navigation
      await _controller.startNavigation();
    }

    return result;
  }

  static Future<void> cancelNavigation() async {
    await _controller.cancelNavigation();
    _currentRoute = null; // Clear route info
  }

  static Future<String?> openMapView() => _controller.openMapView();

  // Legacy compatibility methods (can be removed later)
  static bool get canStart => _controller.currentState == NavigationState.ready;
  static bool get canCancel => [
    NavigationState.calculating,
    NavigationState.ready,
    NavigationState.navigating,
  ].contains(_controller.currentState);

  // Enable/disable simulation mode (if needed)
  static void setSimulationMode(bool enabled) {
    print('📱 Simulation mode: ${enabled ? "ENABLED" : "DISABLED"}');
    // This could be passed to the controller if needed
  }
}
