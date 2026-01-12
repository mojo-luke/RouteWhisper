import 'package:frontend/models/waypoint.dart';

/// WaypointManager - Manages waypoint state and operations
///
/// Handles:
/// - Adding/removing waypoints
/// - Reordering waypoints
/// - Updating waypoint status
/// - Calculating trip duration with stops
/// - Converting waypoints to Mapbox coordinates
/// - Notifying listeners of changes
class WaypointManager {
  List<Waypoint> _waypoints = [];

  /// Callback triggered when waypoints list changes
  Function(List<Waypoint>)? onWaypointsChanged;

  WaypointManager();

  /// Get all waypoints in order
  List<Waypoint> getWaypoints() => List.unmodifiable(_waypoints);

  /// Get waypoint by ID
  Waypoint? getWaypointById(String id) {
    try {
      return _waypoints.firstWhere((wp) => wp.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Add new waypoint
  ///
  /// Automatically assigns order number and notifies listeners.
  /// Returns the added waypoint with correct order.
  Waypoint addWaypoint(Waypoint waypoint) {
    // Assign correct order (insert before destination if it exists)
    final hasDestination = _waypoints.any((wp) => wp.type == WaypointType.destination);
    final order = hasDestination ? _waypoints.length - 1 : _waypoints.length;

    final waypointWithOrder = waypoint.copyWith(order: order);

    if (hasDestination) {
      // Insert before destination
      _waypoints.insert(_waypoints.length - 1, waypointWithOrder);
      // Update destination order
      _updateWaypointOrders();
    } else {
      _waypoints.add(waypointWithOrder);
    }

    print('📍 Waypoint added: ${waypointWithOrder.name} (order: $order)');
    _notifyListeners();

    return waypointWithOrder;
  }

  /// Remove waypoint by ID
  bool removeWaypoint(String waypointId) {
    final waypoint = getWaypointById(waypointId);
    if (waypoint == null) return false;

    // Don't allow removing origin or destination
    if (waypoint.type == WaypointType.origin || waypoint.type == WaypointType.destination) {
      print('⚠️ Cannot remove ${waypoint.type.name} waypoint');
      return false;
    }

    _waypoints.removeWhere((wp) => wp.id == waypointId);
    _updateWaypointOrders();

    print('🗑️ Waypoint removed: ${waypoint.name}');
    _notifyListeners();

    return true;
  }

  /// Remove all intermediate waypoints (keep origin and destination)
  void clearIntermediateWaypoints() {
    _waypoints.removeWhere((wp) =>
        wp.type != WaypointType.origin && wp.type != WaypointType.destination);
    _updateWaypointOrders();

    print('🗑️ All intermediate waypoints cleared');
    _notifyListeners();
  }

  /// Reorder waypoint from oldIndex to newIndex
  ///
  /// Note: This only reorders intermediate waypoints.
  /// Origin stays at position 0, destination stays at end.
  void reorderWaypoint(int oldIndex, int newIndex) {
    // Get intermediate waypoints only
    final intermediateWaypoints = _waypoints
        .where((wp) =>
            wp.type != WaypointType.origin && wp.type != WaypointType.destination)
        .toList();

    if (oldIndex < 0 ||
        oldIndex >= intermediateWaypoints.length ||
        newIndex < 0 ||
        newIndex >= intermediateWaypoints.length) {
      print('⚠️ Invalid reorder indices: $oldIndex → $newIndex');
      return;
    }

    // Reorder
    final waypoint = intermediateWaypoints.removeAt(oldIndex);
    intermediateWaypoints.insert(newIndex, waypoint);

    // Rebuild full waypoints list
    _waypoints = [
      if (_waypoints.any((wp) => wp.type == WaypointType.origin))
        _waypoints.firstWhere((wp) => wp.type == WaypointType.origin),
      ...intermediateWaypoints,
      if (_waypoints.any((wp) => wp.type == WaypointType.destination))
        _waypoints.firstWhere((wp) => wp.type == WaypointType.destination),
    ];

    _updateWaypointOrders();

    print('🔄 Waypoint reordered: $oldIndex → $newIndex');
    _notifyListeners();
  }

  /// Update waypoint (e.g., change status, duration, etc.)
  void updateWaypoint(Waypoint updatedWaypoint) {
    final index = _waypoints.indexWhere((wp) => wp.id == updatedWaypoint.id);
    if (index == -1) {
      print('⚠️ Waypoint not found for update: ${updatedWaypoint.id}');
      return;
    }

    _waypoints[index] = updatedWaypoint;

    print('✏️ Waypoint updated: ${updatedWaypoint.name}');
    _notifyListeners();
  }

  /// Skip waypoint during navigation
  void skipWaypoint(String waypointId) {
    final waypoint = getWaypointById(waypointId);
    if (waypoint == null) return;

    final skippedWaypoint = waypoint.copyWith(status: WaypointStatus.skipped);
    updateWaypoint(skippedWaypoint);

    print('⏭️ Waypoint skipped: ${waypoint.name}');
  }

  /// Get coordinates list for Mapbox Navigation SDK
  ///
  /// Returns List of [longitude, latitude] pairs for Mapbox RouteOptions.
  /// Format: [[lng1, lat1], [lng2, lat2], ...]
  List<List<double>> getCoordinatesList() {
    return _waypoints
        .map((wp) => [wp.longitude, wp.latitude])
        .toList();
  }

  /// Get intermediate waypoints only (excludes origin and destination)
  List<Waypoint> getIntermediateWaypoints() {
    return _waypoints
        .where((wp) =>
            wp.type != WaypointType.origin && wp.type != WaypointType.destination)
        .toList();
  }

  /// Calculate total trip duration including stop times
  ///
  /// [drivingTime] - Total driving time from Mapbox
  /// Returns total trip duration (driving + all stops)
  Duration calculateTotalTripDuration({required Duration drivingTime}) {
    final stopTime = _waypoints
        .where((wp) =>
            wp.type != WaypointType.origin && wp.type != WaypointType.destination)
        .fold<int>(0, (sum, wp) => sum + wp.estimatedDurationMinutes);

    return drivingTime + Duration(minutes: stopTime);
  }

  /// Get summary of all stops
  ///
  /// Returns map with:
  /// - waypointCount: Number of intermediate waypoints
  /// - totalStopMinutes: Total planned stop time in minutes
  /// - totalStopHours: Total planned stop time in hours (formatted)
  /// - waypoints: List of intermediate waypoints
  Map<String, dynamic> getStopSummary() {
    final intermediateWaypoints = getIntermediateWaypoints();

    final totalStopMinutes = intermediateWaypoints.fold<int>(
      0,
      (sum, wp) => sum + wp.estimatedDurationMinutes,
    );

    return {
      'waypointCount': intermediateWaypoints.length,
      'totalStopMinutes': totalStopMinutes,
      'totalStopHours': (totalStopMinutes / 60).toStringAsFixed(1),
      'waypoints': intermediateWaypoints,
    };
  }

  /// Check if route has waypoints (excluding origin/destination)
  bool hasIntermediateWaypoints() {
    return _waypoints.any(
        (wp) => wp.type != WaypointType.origin && wp.type != WaypointType.destination);
  }

  /// Get next pending waypoint
  Waypoint? getNextPendingWaypoint() {
    try {
      return _waypoints.firstWhere((wp) => wp.status == WaypointStatus.pending);
    } catch (e) {
      return null;
    }
  }

  /// Get currently active waypoint
  Waypoint? getActiveWaypoint() {
    try {
      return _waypoints.firstWhere((wp) => wp.status == WaypointStatus.active);
    } catch (e) {
      return null;
    }
  }

  /// Set origin waypoint
  void setOrigin({required double latitude, required double longitude, String? name}) {
    // Remove existing origin
    _waypoints.removeWhere((wp) => wp.type == WaypointType.origin);

    // Add new origin
    final origin = Waypoint.origin(
      latitude: latitude,
      longitude: longitude,
      name: name ?? 'Start',
    );

    _waypoints.insert(0, origin);
    _updateWaypointOrders();

    print('🎯 Origin set: ${origin.name}');
    _notifyListeners();
  }

  /// Set destination waypoint
  void setDestination({required double latitude, required double longitude, String? name}) {
    // Remove existing destination
    _waypoints.removeWhere((wp) => wp.type == WaypointType.destination);

    // Add new destination
    final destination = Waypoint.destination(
      latitude: latitude,
      longitude: longitude,
      name: name ?? 'Destination',
      order: _waypoints.length,
    );

    _waypoints.add(destination);
    _updateWaypointOrders();

    print('🏁 Destination set: ${destination.name}');
    _notifyListeners();
  }

  /// Clear all waypoints (including origin and destination)
  void clearAll() {
    _waypoints.clear();
    print('🗑️ All waypoints cleared');
    _notifyListeners();
  }

  /// Reset all waypoints to pending status (before starting navigation)
  void resetWaypointStatuses() {
    _waypoints = _waypoints.map((wp) {
      if (wp.status != WaypointStatus.pending) {
        return wp.copyWith(
          status: WaypointStatus.pending,
          arrivalTime: null,
          departureTime: null,
          actualDurationMinutes: null,
        );
      }
      return wp;
    }).toList();

    print('🔄 All waypoint statuses reset to pending');
    _notifyListeners();
  }

  /// Update all waypoint orders sequentially
  void _updateWaypointOrders() {
    for (int i = 0; i < _waypoints.length; i++) {
      if (_waypoints[i].order != i) {
        _waypoints[i] = _waypoints[i].copyWith(order: i);
      }
    }
  }

  /// Notify listeners of waypoint changes
  void _notifyListeners() {
    if (onWaypointsChanged != null) {
      onWaypointsChanged!(_waypoints);
    }
  }

  /// Debug: Print all waypoints
  void debugPrintWaypoints() {
    print('═════════════════════════════════════════════════');
    print('📍 Waypoint Manager - Current State');
    print('═════════════════════════════════════════════════');
    print('Total waypoints: ${_waypoints.length}');
    print('Intermediate waypoints: ${getIntermediateWaypoints().length}');

    final stopSummary = getStopSummary();
    print('Total stop time: ${stopSummary['totalStopMinutes']} min');

    print('\nWaypoints:');
    for (final waypoint in _waypoints) {
      final statusIcon = _getStatusIcon(waypoint.status);
      final typeIcon = _getTypeIcon(waypoint.type);
      print(
          '  $statusIcon $typeIcon ${waypoint.order}. ${waypoint.name} (${waypoint.estimatedDurationMinutes} min)');
    }
    print('═════════════════════════════════════════════════');
  }

  String _getStatusIcon(WaypointStatus status) {
    switch (status) {
      case WaypointStatus.pending:
        return '⏳';
      case WaypointStatus.active:
        return '🔵';
      case WaypointStatus.completed:
        return '✅';
      case WaypointStatus.skipped:
        return '⏭️';
    }
  }

  String _getTypeIcon(WaypointType type) {
    switch (type) {
      case WaypointType.origin:
        return '🎯';
      case WaypointType.destination:
        return '🏁';
      case WaypointType.poi:
        return '📍';
      case WaypointType.manual:
        return '✏️';
      case WaypointType.search:
        return '🔍';
    }
  }
}
