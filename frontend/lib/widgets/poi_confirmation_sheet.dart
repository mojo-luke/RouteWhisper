import 'package:flutter/material.dart';
import '../models/waypoint.dart';
import '../services/navigation_service.dart';
import '../services/poi_api_service.dart';

/// Bottom sheet shown when the user taps a POI marker on the in-nav map.
///
/// Surfaces the minimum a driver glancing at the screen needs: name, category,
/// distance from route, rating. Confirming runs the existing in-place route
/// update path (`updateNavigationRoute`) and shows a 5-second undo SnackBar
/// per the destructive-action rule. Cancel just dismisses; markers stay on
/// the map so the user can tap a different one.
class POIConfirmationSheet extends StatelessWidget {
  final POI poi;

  const POIConfirmationSheet({Key? key, required this.poi}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(poi.categoryIcon, style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        poi.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        poi.categoryName,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Chip(
                  icon: Icons.alt_route,
                  label: '${poi.distanceFormatted} from route',
                ),
                if (poi.rating != null) ...[
                  const SizedBox(width: 8),
                  _Chip(
                    icon: Icons.star,
                    label: poi.rating!.toStringAsFixed(1),
                  ),
                ],
              ],
            ),
            if (poi.address != null) ...[
              const SizedBox(height: 12),
              Text(
                poi.address!,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    key: const Key('add-stop-button'),
                    onPressed: () => _confirm(context),
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Add stop'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

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
        waypoints: intermediates.map((w) => [w.longitude, w.latitude]).toList(),
        waypointNames: intermediates.map((w) => w.name).toList(),
      );
    }

    await NavigationService.controller.bridge.clearPoisFromMap();

    navigator.pop();

    messenger.showSnackBar(
      SnackBar(
        content: Text('${poi.name} added to your route'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            NavigationService.waypointManager.removeWaypoint(waypoint.id);
            // Best-effort: roll the route back too. Failures here just
            // surface the pre-undo route, which is still drivable.
            final route = NavigationService.currentRoute;
            if (route != null && NavigationService.isNavigating) {
              final remaining = NavigationService.waypointManager
                  .getWaypoints()
                  .where((w) =>
                      w.type != WaypointType.origin &&
                      w.type != WaypointType.destination)
                  .toList();
              NavigationService.controller.updateNavigationRoute(
                originLat: route.originLat,
                originLng: route.originLng,
                destLat: route.destLat,
                destLng: route.destLng,
                waypoints: remaining
                    .map((w) => [w.longitude, w.latitude])
                    .toList(),
                waypointNames: remaining.map((w) => w.name).toList(),
              );
            }
          },
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
