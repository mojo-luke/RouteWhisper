import 'package:flutter/services.dart';
import 'navigation_controller.dart';
import 'poi_api_service.dart';

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
  static final POIApiService _poiApi = POIApiService();

  // Current route info
  static RouteInfo? _currentRoute;

  // POI discovery state
  static String? _routePolyline;
  static POIResponse? _lastPOIResponse;
  static bool _isDiscoveringPOIs = false;

  // Delegate to controller
  static NavigationState get currentState => _controller.currentState;
  static bool get isNavigating => _controller.isNavigating;
  static RouteInfo? get currentRoute => _currentRoute;

  // POI discovery getters
  static String? get routePolyline => _routePolyline;
  static POIResponse? get lastPOIResponse => _lastPOIResponse;
  static bool get isDiscoveringPOIs => _isDiscoveringPOIs;
  static bool get hasPOIs => _lastPOIResponse != null && _lastPOIResponse!.pois.isNotEmpty;

  static void initialize() {
    _controller.initialize();
  }

  static void setCallbacks({
    Function(NavigationState)? onStateChanged,
    Function(String)? onError,
    Function(RoutePoint)? onLocationUpdate,
    Function()? onRoutePolylineReceived,
  }) {
    _controller.onStateChanged = onStateChanged;
    _controller.onError = onError;
    _controller.onLocationUpdate = onLocationUpdate;
    // Set route polyline callback to store polyline for POI discovery
    _controller.onRoutePolyline = (polyline) {
      setRoutePolyline(polyline);
      // Notify UI that polyline was received
      onRoutePolylineReceived?.call();
    };
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

  // ========== POI Discovery Methods ==========

  /// Store route polyline from Android
  ///
  /// Called via method channel when route geometry is extracted from Mapbox SDK
  static void setRoutePolyline(String polyline) {
    _routePolyline = polyline;
    print('📍 Route polyline stored: ${polyline.substring(0, polyline.length > 50 ? 50 : polyline.length)}...');
  }

  /// Discover POIs along the current route
  ///
  /// [categories] - Optional list of category filters (e.g., ['restaurant', 'gas_station'])
  /// [radiusMiles] - Search radius from route (default 5.0 miles)
  ///
  /// Returns [POIResponse] with discovered POIs or null on error
  static Future<POIResponse?> discoverPOIs({
    List<String>? categories,
    double radiusMiles = 5.0,
  }) async {
    if (_routePolyline == null) {
      print('❌ No route polyline available for POI discovery');
      return null;
    }

    if (_isDiscoveringPOIs) {
      print('⏳ POI discovery already in progress');
      return null;
    }

    _isDiscoveringPOIs = true;

    try {
      print('🔍 Discovering POIs along route...');
      print('   Categories: ${categories?.join(", ") ?? "all"}');
      print('   Radius: $radiusMiles miles');

      final response = await _poiApi.discoverRoutePOIs(
        encodedPolyline: _routePolyline!,
        categories: categories,
        corridorRadiusMiles: radiusMiles,
        limitPerCategory: 5,
      );

      _lastPOIResponse = response;

      print('✅ POI Discovery Complete:');
      print('   Found: ${response.totalFound} POIs');
      print('   Cached: ${response.cached}');
      print('   Categories: ${_getCategoryCounts(response.pois)}');

      return response;
    } catch (e) {
      print('❌ POI discovery failed: $e');
      return null;
    } finally {
      _isDiscoveringPOIs = false;
    }
  }

  /// Clear POI discovery state
  static void clearPOIs() {
    _lastPOIResponse = null;
    print('🗑️ POI discovery state cleared');
  }

  /// Helper to get category counts from POI list
  static Map<String, int> _getCategoryCounts(List<POI> pois) {
    final counts = <String, int>{};
    for (final poi in pois) {
      counts[poi.category] = (counts[poi.category] ?? 0) + 1;
    }
    return counts;
  }

  /// Dispose resources
  static void dispose() {
    _poiApi.dispose();
  }
}
