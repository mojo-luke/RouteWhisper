import 'package:flutter/material.dart';
import '../services/poi_api_service.dart';

/// POI Suggestion Card Widget
///
/// Displays a single POI with name, category, distance, rating, and duration.
/// Simplified version for MVP - budget integration deferred to later step.
class POISuggestionCard extends StatelessWidget {
  final POI poi;
  final VoidCallback? onTap;

  const POISuggestionCard({
    Key? key,
    required this.poi,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Icon, Name, and Distance
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category Icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _getCategoryColor().withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        poi.categoryIcon,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Name and Category
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          poi.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          poi.categoryName,
                          style: TextStyle(
                            fontSize: 14,
                            color: _getCategoryColor(),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Distance Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      poi.distanceFormatted,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Details: Rating, Duration, Address
              Row(
                children: [
                  // Rating
                  if (poi.rating != null) ...[
                    Icon(
                      Icons.star,
                      size: 16,
                      color: Colors.amber.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      poi.rating!.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  // Duration
                  const Icon(
                    Icons.access_time,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    poi.durationFormatted,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              // Address (if available)
              if (poi.address != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        poi.address!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              // Action Button (disabled for MVP)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: null, // TODO: Enable when waypoint management is ready
                  icon: const Icon(Icons.add_location_alt, size: 18),
                  label: const Text('Add as Waypoint'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Get color for POI category
  Color _getCategoryColor() {
    switch (poi.category) {
      case 'gas_station':
        return Colors.red;
      case 'restaurant':
        return Colors.orange;
      case 'coffee':
        return Colors.brown;
      case 'hotel':
        return Colors.blue;
      case 'camping':
        return Colors.green;
      case 'attraction':
        return Colors.purple;
      case 'shopping':
        return Colors.pink;
      case 'scenic':
        return Colors.teal;
      case 'museum':
        return Colors.deepPurple;
      case 'park':
        return Colors.lightGreen;
      case 'hospital':
        return Colors.red.shade700;
      case 'pharmacy':
        return Colors.cyan;
      case 'bank':
        return Colors.indigo;
      case 'grocery':
        return Colors.lime;
      default:
        return Colors.grey;
    }
  }
}
