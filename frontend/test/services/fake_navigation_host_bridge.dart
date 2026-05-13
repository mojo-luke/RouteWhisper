import 'package:frontend/services/navigation_host_bridge.dart';

/// In-memory [NavigationHostBridge] for fast unit tests.
///
/// Records every outbound (Flutter → Native) call into [sentCalls] and exposes
/// one `emitX` method per inbound (Native → Flutter) event on
/// [NavigationHostHandlers]. Tests construct one of these, hand it to the
/// component under test, and:
///
/// 1. Assert what the component sent outward (via [sentCalls] / [lastCall]
///    / [callsTo]).
/// 2. Drive inbound behavior by calling the matching `emitX(...)`.
///
/// Deliberately dumb — no event sequencing, no state simulation, no smarts.
/// A "smart" simulator can sit on top of this class later by calling the same
/// `emitX` methods in a realistic order; nothing in this file needs to change
/// to support that.
class FakeNavigationHostBridge implements NavigationHostBridge {
  /// Outbound calls in the order they were made.
  final List<RecordedCall> sentCalls = <RecordedCall>[];

  /// Configurable stub return values for outbound commands. Default `'ok'`
  /// for the three String?-returning methods. Set to `null` (or any value)
  /// to simulate a different native response.
  String? calculateRouteResult = 'ok';
  String? updateNavigationRouteResult = 'ok';
  String? openMapViewResult = 'ok';

  /// Configurable per-method exceptions. If set, the matching outbound call
  /// will throw the exception instead of returning. Cleared after one use so
  /// the next call returns normally — this matches how real bridge failures
  /// behave (one bad call doesn't poison the bridge).
  Object? calculateRouteError;
  Object? updateNavigationRouteError;
  Object? cancelNavigationError;
  Object? openMapViewError;
  Object? showPoisOnMapError;
  Object? clearPoisFromMapError;
  Object? hideOverlayError;
  Object? setBudgetStatusError;
  Object? clearBudgetStatusError;
  Object? setRecommendationError;
  Object? clearRecommendationError;
  Object? speakNarrationError;
  Object? playNarrationAudioError;
  Object? setTurnByTurnVoiceEnabledError;
  Object? addNarrationMarkerError;
  Object? setActiveNarrationMarkerError;
  Object? clearNarrationMarkersError;

  NavigationHostHandlers? _handlers;

  /// The handler bag the component under test registered (or null if it
  /// hasn't called [setHandlers] yet). Exposed for assertions like "the
  /// controller registered handlers during initialize()."
  NavigationHostHandlers? get handlers => _handlers;

  @override
  void setHandlers(NavigationHostHandlers handlers) {
    _handlers = handlers;
  }

  // --- Outbound (Flutter → Native): record & stub ---

  @override
  Future<String?> calculateRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    List<List<double>>? waypoints,
    List<String>? waypointNames,
  }) async {
    sentCalls.add(RecordedCall('calculateRoute', {
      'originLat': originLat,
      'originLng': originLng,
      'destLat': destLat,
      'destLng': destLng,
      if (waypoints != null && waypoints.isNotEmpty) 'waypoints': waypoints,
      if (waypointNames != null && waypointNames.isNotEmpty)
        'waypointNames': waypointNames,
    }));
    final err = calculateRouteError;
    if (err != null) {
      calculateRouteError = null;
      throw err;
    }
    return calculateRouteResult;
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
    sentCalls.add(RecordedCall('updateNavigationRoute', {
      'originLat': originLat,
      'originLng': originLng,
      'destLat': destLat,
      'destLng': destLng,
      if (waypoints != null && waypoints.isNotEmpty) 'waypoints': waypoints,
      if (waypointNames != null && waypointNames.isNotEmpty)
        'waypointNames': waypointNames,
    }));
    final err = updateNavigationRouteError;
    if (err != null) {
      updateNavigationRouteError = null;
      throw err;
    }
    return updateNavigationRouteResult;
  }

  @override
  Future<void> cancelNavigation() async {
    sentCalls.add(const RecordedCall('cancelNavigation', <String, dynamic>{}));
    final err = cancelNavigationError;
    if (err != null) {
      cancelNavigationError = null;
      throw err;
    }
  }

  @override
  Future<String?> openMapView() async {
    sentCalls.add(const RecordedCall('openMapView', <String, dynamic>{}));
    final err = openMapViewError;
    if (err != null) {
      openMapViewError = null;
      throw err;
    }
    return openMapViewResult;
  }

  @override
  Future<void> showPoisOnMap({
    required List<Map<String, dynamic>> pois,
    required List<double> bounds,
  }) async {
    sentCalls.add(RecordedCall('showPoisOnMap', {
      'pois': pois,
      'bounds': bounds,
    }));
    final err = showPoisOnMapError;
    if (err != null) {
      showPoisOnMapError = null;
      throw err;
    }
  }

  @override
  Future<void> clearPoisFromMap() async {
    sentCalls.add(const RecordedCall('clearPoisFromMap', <String, dynamic>{}));
    final err = clearPoisFromMapError;
    if (err != null) {
      clearPoisFromMapError = null;
      throw err;
    }
  }

  @override
  Future<void> hideOverlay() async {
    sentCalls.add(const RecordedCall('hideOverlay', <String, dynamic>{}));
    final err = hideOverlayError;
    if (err != null) {
      hideOverlayError = null;
      throw err;
    }
  }

  @override
  Future<void> setBudgetStatus({
    required int usedMinutes,
    required int totalMinutes,
  }) async {
    sentCalls.add(RecordedCall('setBudgetStatus', {
      'usedMinutes': usedMinutes,
      'totalMinutes': totalMinutes,
    }));
    final err = setBudgetStatusError;
    if (err != null) {
      setBudgetStatusError = null;
      throw err;
    }
  }

  @override
  Future<void> clearBudgetStatus() async {
    sentCalls.add(const RecordedCall('clearBudgetStatus', <String, dynamic>{}));
    final err = clearBudgetStatusError;
    if (err != null) {
      clearBudgetStatusError = null;
      throw err;
    }
  }

  @override
  Future<void> setRecommendation({
    required String poiId,
    required String name,
    required String category,
    required String reason,
  }) async {
    sentCalls.add(RecordedCall('setRecommendation', {
      'poiId': poiId,
      'name': name,
      'category': category,
      'reason': reason,
    }));
    final err = setRecommendationError;
    if (err != null) {
      setRecommendationError = null;
      throw err;
    }
  }

  @override
  Future<void> clearRecommendation() async {
    sentCalls.add(const RecordedCall('clearRecommendation', <String, dynamic>{}));
    final err = clearRecommendationError;
    if (err != null) {
      clearRecommendationError = null;
      throw err;
    }
  }

  @override
  Future<void> speakNarration({required String text}) async {
    sentCalls.add(RecordedCall('speakNarration', {'text': text}));
    final err = speakNarrationError;
    if (err != null) {
      speakNarrationError = null;
      throw err;
    }
  }

  @override
  Future<void> playNarrationAudio({required String url}) async {
    sentCalls.add(RecordedCall('playNarrationAudio', {'url': url}));
    final err = playNarrationAudioError;
    if (err != null) {
      playNarrationAudioError = null;
      throw err;
    }
  }

  @override
  Future<void> setTurnByTurnVoiceEnabled({required bool enabled}) async {
    sentCalls.add(RecordedCall('setTurnByTurnVoiceEnabled', {'enabled': enabled}));
    final err = setTurnByTurnVoiceEnabledError;
    if (err != null) {
      setTurnByTurnVoiceEnabledError = null;
      throw err;
    }
  }

  @override
  Future<void> addNarrationMarker({
    required String id,
    required double lat,
    required double lng,
    required String title,
  }) async {
    sentCalls.add(RecordedCall('addNarrationMarker', {
      'id': id,
      'lat': lat,
      'lng': lng,
      'title': title,
    }));
    final err = addNarrationMarkerError;
    if (err != null) {
      addNarrationMarkerError = null;
      throw err;
    }
  }

  @override
  Future<void> setActiveNarrationMarker({required String? id}) async {
    sentCalls.add(RecordedCall('setActiveNarrationMarker', {'id': id}));
    final err = setActiveNarrationMarkerError;
    if (err != null) {
      setActiveNarrationMarkerError = null;
      throw err;
    }
  }

  @override
  Future<void> clearNarrationMarkers() async {
    sentCalls.add(const RecordedCall('clearNarrationMarkers', <String, dynamic>{}));
    final err = clearNarrationMarkersError;
    if (err != null) {
      clearNarrationMarkersError = null;
      throw err;
    }
  }

  // --- Inbound (Native → Flutter): one emit per NavigationHostHandlers field ---
  //
  // If a new handler is added to NavigationHostHandlers, add the matching
  // emit method below. The static drift check in
  // navigation_host_bridge_test.dart and the abstract-class implements check
  // both protect the outbound side; the convention "one emit per handler"
  // is what protects the inbound side.

  void emitRoutePolyline(String polyline) {
    _requireHandlers().onRoutePolyline(polyline);
  }

  void emitWaypointArrived({
    required int legIndex,
    required double latitude,
    required double longitude,
  }) {
    _requireHandlers().onWaypointArrived(
      legIndex: legIndex,
      latitude: latitude,
      longitude: longitude,
    );
  }

  void emitAutoDeparture({
    required double distanceMeters,
    required double speedMph,
  }) {
    _requireHandlers().onAutoDeparture(
      distanceMeters: distanceMeters,
      speedMph: speedMph,
    );
  }

  void emitDestinationArrived() {
    _requireHandlers().onDestinationArrived();
  }

  void emitShowOverlay(String route) {
    _requireHandlers().onShowOverlay(route);
  }

  void emitPopRoute() {
    _requireHandlers().onPopRoute();
  }

  void emitRequestPoisOnMap() {
    _requireHandlers().onRequestPoisOnMap();
  }

  void emitPoiTapped(String poiId) {
    _requireHandlers().onPoiTapped(poiId);
  }

  void emitRecommendationAccept(String poiId) {
    _requireHandlers().onRecommendationAccept(poiId);
  }

  void emitRecommendationDismiss(String poiId) {
    _requireHandlers().onRecommendationDismiss(poiId);
  }

  void emitSuggestStopRequested() {
    _requireHandlers().onSuggestStopRequested();
  }

  Map<String, dynamic>? emitWaypointProgressRequest({
    required int legIndex,
    required double distanceMeters,
    required double durationSeconds,
  }) {
    return _requireHandlers().onWaypointProgressRequest(
      legIndex: legIndex,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
  }

  void emitLocationUpdate({
    required double latitude,
    required double longitude,
    required double speedMph,
    double distanceAlongRouteMeters = 0.0,
  }) {
    _requireHandlers().onLocationUpdate(
      latitude: latitude,
      longitude: longitude,
      speedMph: speedMph,
      distanceAlongRouteMeters: distanceAlongRouteMeters,
    );
  }

  // --- Test ergonomics ---

  /// Most recent recorded outbound call, or null if there are none.
  RecordedCall? get lastCall =>
      sentCalls.isEmpty ? null : sentCalls.last;

  /// All recorded calls whose method name matches [method]. Useful for
  /// assertions like "exactly one call to calculateRoute happened."
  List<RecordedCall> callsTo(String method) =>
      sentCalls.where((c) => c.method == method).toList();

  /// Forget every recorded call. Stubs and registered handlers are kept.
  void clear() {
    sentCalls.clear();
  }

  NavigationHostHandlers _requireHandlers() {
    final h = _handlers;
    if (h == null) {
      throw StateError(
        'FakeNavigationHostBridge: emit*() called before setHandlers(). '
        'The component under test must call bridge.setHandlers(...) — '
        'usually inside its initialize() — before tests can fire events.',
      );
    }
    return h;
  }
}

/// One recorded outbound call. [args] mirrors the named args the caller
/// passed (the same shape the real bridge sends over the method channel).
class RecordedCall {
  final String method;
  final Map<String, dynamic> args;

  const RecordedCall(this.method, this.args);

  @override
  String toString() => 'RecordedCall($method, $args)';
}
