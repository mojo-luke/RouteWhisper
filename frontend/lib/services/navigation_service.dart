import 'package:flutter/services.dart';

// Navigation methods we'll implement via platform channels
class NavigationService {
  static const MethodChannel _channel = MethodChannel(
    'routewhisper.com/navigation',
  );

  static Future<void> showMap() async {
    try {
      await _channel.invokeMethod('showMap');
    } on PlatformException catch (e) {
      print("Failed to show map: ${e.message}");
    }
  }

  static Future<String?> startNavigation({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      await _channel.invokeMethod('startNavigation', {
        'originLat': originLat,
        'originLng': originLng,
        'destLat': destLat,
        'destLng': destLng,
      });
      return null; // Success
    } on PlatformException catch (e) {
      return "Failed to start navigation: ${e.message}";
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
