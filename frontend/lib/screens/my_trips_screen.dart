import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/trip_service.dart';
import 'trip_detail_screen.dart';

/// "My Trips" — the list of trips the user has saved. Empty state on
/// first load. Tap a trip to open its detail screen (slice C will build
/// out the canvas there; slice A shows a placeholder).
///
/// The new-trip wizard is slice B; for now, this screen has a "New
/// trip" FAB that creates a placeholder Trip via the API so the
/// persistence path is exercisable end-to-end.
class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  bool _loading = true;
  bool _creating = false;
  List<Trip> _trips = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final trips = await TripService.list();
    if (!mounted) return;
    setState(() {
      _trips = trips;
      _loading = false;
    });
  }

  /// Placeholder until slice B's wizard ships: creates a minimal trip
  /// at SF → LA with default constraints. Lets us exercise the full
  /// list/create/detail loop today.
  Future<void> _createPlaceholderTrip() async {
    setState(() => _creating = true);
    final draft = Trip(
      name: 'New trip ${DateTime.now().toIso8601String().substring(0, 16)}',
      originName: 'Current location',
      originLat: 37.7749,
      originLng: -122.4194,
      destinationName: 'Destination',
      destinationLat: 34.0522,
      destinationLng: -118.2437,
    );
    final saved = await TripService.create(draft);
    if (!mounted) return;
    setState(() => _creating = false);
    if (saved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to create trip')),
      );
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TripDetailScreen(trip: saved),
    ));
    _refresh();
  }

  Future<void> _openTrip(Trip trip) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TripDetailScreen(trip: trip),
    ));
    // Detail screen may have edited or deleted; reload list either way.
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My trips')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _trips.isEmpty
              ? _EmptyState()
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _trips.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final trip = _trips[i];
                      return _TripTile(
                        trip: trip,
                        onTap: () => _openTrip(trip),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating ? null : _createPlaceholderTrip,
        icon: _creating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add),
        label: const Text('New trip'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map_outlined,
              size: 56,
              color: Colors.white.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'No trips yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Plan ahead — pick stops, set overnight stays, and have everything ready before you drive.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripTile extends StatelessWidget {
  final Trip trip;
  final VoidCallback onTap;

  const _TripTile({required this.trip, required this.onTap});

  String _subtitle() {
    final parts = <String>[
      '${trip.originName} → ${trip.destinationName}',
    ];
    if (trip.startDate != null) {
      parts.add(trip.startDate!);
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.route)),
      title: Text(
        trip.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        _subtitle(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
