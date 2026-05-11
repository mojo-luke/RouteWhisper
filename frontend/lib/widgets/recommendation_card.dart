import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/waypoint.dart';
import '../services/navigation_service.dart';
import '../services/recommendation_service.dart';

/// Non-modal banner that slides up from the bottom of the in-nav map when
/// a `RecommendationService` has a suggestion to surface. Two actions:
///   * **Add stop** — converts the suggested POI into a waypoint and
///     runs the standard in-place route update + 5s undo snack.
///   * **Not now** — suppresses this POI for the rest of the trip.
///
/// The card is intentionally separate from `POIConfirmationSheet`: that
/// one is modal (user tapped a marker, give it focus), this one is a
/// soft, dismissable surface the driver can ignore without thinking.
class RecommendationCard extends StatelessWidget {
  const RecommendationCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RecommendationService>(
      builder: (context, service, _) {
        final suggestion = service.current;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) {
            final slide = Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(animation);
            return SlideTransition(position: slide, child: child);
          },
          child: suggestion == null
              ? const SizedBox.shrink()
              : _Card(suggestion: suggestion, service: service),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  final StopSuggestion suggestion;
  final RecommendationService service;
  const _Card({required this.suggestion, required this.service});

  Future<void> _add(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final poi = suggestion.poi;
    final waypoint = Waypoint.fromPOI(
      poi,
      NavigationService.waypointManager.getWaypoints().length,
    );
    NavigationService.waypointManager.addWaypoint(waypoint);

    if (NavigationService.isNavigating &&
        NavigationService.currentRoute != null) {
      final route = NavigationService.currentRoute!;
      final intermediates = NavigationService.waypointManager
          .getWaypoints()
          .where((w) =>
              w.type != WaypointType.origin &&
              w.type != WaypointType.destination)
          .toList();
      await NavigationService.controller.updateNavigationRoute(
        originLat: route.originLat,
        originLng: route.originLng,
        destLat: route.destLat,
        destLng: route.destLng,
        waypoints:
            intermediates.map((w) => [w.longitude, w.latitude]).toList(),
        waypointNames: intermediates.map((w) => w.name).toList(),
      );
    }

    service.acceptCurrent();

    messenger.showSnackBar(
      SnackBar(
        content: Text('${poi.name} added to your route'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            NavigationService.waypointManager.removeWaypoint(waypoint.id);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final poi = suggestion.poi;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Material(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(16),
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(poi.categoryIcon, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            poi.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            suggestion.reason,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => service.dismissCurrent(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                        ),
                        child: const Text('Not now'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () => _add(context),
                        icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                        label: const Text('Add stop'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
