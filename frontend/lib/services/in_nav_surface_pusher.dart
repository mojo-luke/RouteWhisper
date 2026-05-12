import 'package:flutter/foundation.dart';
import 'navigation_host_bridge.dart';
import 'navigation_service.dart';
import 'recommendation_service.dart';

/// One-way bridge glue: listens to [WaypointManager] and
/// [RecommendationService] and pushes their state down to the native
/// MapActivity so the in-nav surfaces (budget chip + recommendation
/// banner) reflect what Flutter currently has.
///
/// Single instance, wired at app start. Cleans itself up on disposal —
/// we don't expect repeated `attach()`/`detach()` cycles in practice.
class InNavSurfacePusher {
  final NavigationHostBridge _bridge;
  bool _attached = false;
  int? _lastBudgetUsed;
  int? _lastBudgetTotal;
  String? _lastRecommendationId;

  InNavSurfacePusher({NavigationHostBridge? bridge})
      : _bridge = bridge ?? NavigationService.controller.bridge;

  void attach() {
    if (_attached) return;
    _attached = true;
    NavigationService.waypointManager.addListener(_pushBudget);
    NavigationService.recommendations.addListener(_pushRecommendation);
    // Send an initial snapshot so the native side isn't stale.
    _pushBudget();
    _pushRecommendation();
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    NavigationService.waypointManager.removeListener(_pushBudget);
    NavigationService.recommendations.removeListener(_pushRecommendation);
  }

  void _pushBudget() {
    final manager = NavigationService.waypointManager;
    final total = manager.tripBudgetMinutes;
    if (total == null) {
      if (_lastBudgetTotal != null) {
        _bridge.clearBudgetStatus();
        _lastBudgetUsed = null;
        _lastBudgetTotal = null;
      }
      return;
    }
    final used = manager.usedBudgetMinutes;
    if (used == _lastBudgetUsed && total == _lastBudgetTotal) return;
    _lastBudgetUsed = used;
    _lastBudgetTotal = total;
    _bridge.setBudgetStatus(usedMinutes: used, totalMinutes: total);
  }

  void _pushRecommendation() {
    final current = NavigationService.recommendations.current;
    if (current == null) {
      if (_lastRecommendationId != null) {
        _bridge.clearRecommendation();
        _lastRecommendationId = null;
      }
      return;
    }
    if (current.poi.id == _lastRecommendationId) return;
    _lastRecommendationId = current.poi.id;
    _bridge.setRecommendation(
      poiId: current.poi.id,
      name: current.poi.name,
      category: current.poi.category,
      reason: current.reason,
    );
  }

  @visibleForTesting
  bool get isAttached => _attached;
}
