import 'package:flutter/material.dart';
import '../services/navigation_service.dart';
import '../services/poi_api_service.dart';
import '../models/waypoint.dart';
import 'poi_suggestion_card.dart';

/// POI Dashboard Widget
///
/// Displays list of discovered POIs along the route.
/// Automatically discovers POIs when opened and shows loading/error states.
class POIDashboard extends StatefulWidget {
  const POIDashboard({Key? key}) : super(key: key);

  @override
  State<POIDashboard> createState() => _POIDashboardState();
}

class _POIDashboardState extends State<POIDashboard> {
  List<POI> _pois = [];
  bool _loading = false;
  String? _error;
  bool _cached = false;

  @override
  void initState() {
    super.initState();
    _loadPOIs();
  }

  Future<void> _loadPOIs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await NavigationService.discoverPOIs();

      if (response != null) {
        setState(() {
          _pois = response.pois;
          _cached = response.cached;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'No route polyline available. Please start navigation first.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to discover POIs: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Points of Interest'),
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadPOIs,
            tooltip: 'Refresh POIs',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Loading state
    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Discovering POIs along your route...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      );
    }

    // Error state
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red.shade300,
              ),
              const SizedBox(height: 16),
              Text(
                'Error',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadPOIs,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    // Empty state
    if (_pois.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_searching,
                size: 64,
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 16),
              Text(
                'No POIs Found',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No points of interest were found along your route.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadPOIs,
                icon: const Icon(Icons.search),
                label: const Text('Search Again'),
              ),
            ],
          ),
        ),
      );
    }

    // Success state with POI list
    return Column(
      children: [
        // Header with count and cache status
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blue.shade50,
          child: Row(
            children: [
              Icon(
                Icons.location_on,
                color: Colors.blue.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Found ${_pois.length} POI${_pois.length != 1 ? 's' : ''} along your route',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade900,
                  ),
                ),
              ),
              if (_cached)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 14,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Cached',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // POI list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            itemCount: _pois.length,
            itemBuilder: (context, index) {
              final poi = _pois[index];
              return POISuggestionCard(
                poi: poi,
                onTap: () {
                  _showPOIDetails(poi);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Add POI as waypoint to the route
  void _addPOIAsWaypoint(POI poi) {
    // Create waypoint from POI
    final waypoint = Waypoint.fromPOI(
      poi,
      NavigationService.waypointManager.getWaypoints().length,
    );

    // Add to waypoint manager
    NavigationService.waypointManager.addWaypoint(waypoint);

    // Close the details sheet
    Navigator.pop(context);

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Waypoint Added',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('${poi.name} added to your route'),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          textColor: Colors.white,
          onPressed: () {
            // Remove the waypoint
            NavigationService.waypointManager.removeWaypoint(waypoint.id);
          },
        ),
      ),
    );

    print('📍 POI added as waypoint: ${poi.name}');
  }

  /// Show detailed POI information in a bottom sheet
  void _showPOIDetails(POI poi) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    poi.categoryIcon,
                    style: const TextStyle(fontSize: 32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          poi.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          poi.categoryName,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              // Details
              _buildDetailRow(Icons.location_on, 'Distance', poi.distanceFormatted),
              const SizedBox(height: 12),
              _buildDetailRow(Icons.access_time, 'Est. Duration', poi.durationFormatted),
              if (poi.rating != null) ...[
                const SizedBox(height: 12),
                _buildDetailRow(Icons.star, 'Rating', '${poi.rating!.toStringAsFixed(1)} / 5.0'),
              ],
              if (poi.address != null) ...[
                const SizedBox(height: 12),
                _buildDetailRow(Icons.location_city, 'Address', poi.address!),
              ],
              const SizedBox(height: 24),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _addPOIAsWaypoint(poi),
                      icon: const Icon(Icons.add_location_alt),
                      label: const Text('Add Stop'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
