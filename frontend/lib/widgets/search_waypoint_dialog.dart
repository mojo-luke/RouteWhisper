import 'package:flutter/material.dart';
import 'package:frontend/models/waypoint.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Dialog for searching and adding places as waypoints
///
/// Features:
/// - Search for any place or address
/// - Results powered by Mapbox Geocoding API
/// - Select a result to add as waypoint
/// - Custom stop duration
class SearchWaypointDialog extends StatefulWidget {
  final Function(Waypoint) onWaypointAdded;
  final int nextOrder;

  const SearchWaypointDialog({
    Key? key,
    required this.onWaypointAdded,
    required this.nextOrder,
  }) : super(key: key);

  @override
  State<SearchWaypointDialog> createState() => _SearchWaypointDialogState();
}

class _SearchWaypointDialogState extends State<SearchWaypointDialog> {
  final _searchController = TextEditingController();
  List<SearchResult> _searchResults = [];
  bool _isSearching = false;
  String? _error;
  SearchResult? _selectedResult;
  int _stopDuration = 15; // Default 15 minutes

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2D2D2D),
      title: const Text(
        'Search for a Place',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search field
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search for a place or address...',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                filled: true,
                fillColor: Colors.black.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade700),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blue),
                ),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.blue,
                          ),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.search, color: Colors.blue),
                        onPressed: _search,
                      ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 16),

            // Error message
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Search results
            if (_searchResults.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 250),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final result = _searchResults[index];
                    final isSelected = _selectedResult == result;

                    return Card(
                      color: isSelected
                          ? Colors.blue.withOpacity(0.3)
                          : Colors.black.withOpacity(0.3),
                      child: ListTile(
                        leading: Icon(
                          Icons.place,
                          color: isSelected ? Colors.blue : Colors.white70,
                        ),
                        title: Text(
                          result.name,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          result.address,
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: Colors.blue)
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedResult = result;
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Stop duration selector (only show if result selected)
              if (_selectedResult != null) ...[
                const Divider(color: Colors.white24),
                const SizedBox(height: 8),
                _buildStopDurationSelector(),
              ],
            ],

            // Empty state
            if (_searchResults.isEmpty && !_isSearching && _searchController.text.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.search_off, size: 48, color: Colors.grey.shade600),
                    const SizedBox(height: 12),
                    Text(
                      'No results found',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedResult != null ? _addWaypoint : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade800,
          ),
          child: const Text('Add Stop'),
        ),
      ],
    );
  }

  Widget _buildStopDurationSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Stop Duration',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),

        // Quick select buttons
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [5, 10, 15, 30, 45, 60].map((min) {
            final isSelected = _stopDuration == min;
            return ChoiceChip(
              label: Text('$min min'),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _stopDuration = min);
                }
              },
              selectedColor: Colors.blue,
              backgroundColor: Colors.grey.shade800,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _error = null;
      _searchResults = [];
      _selectedResult = null;
    });

    try {
      // Call backend geocoding endpoint
      final response = await http.get(
        Uri.parse('http://10.0.2.2:8000/api/v1/search/geocode?query=$query&limit=5'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = (data['results'] as List)
            .map((r) => SearchResult.fromJson(r))
            .toList();

        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      } else {
        setState(() {
          _error = 'Search failed. Please try again.';
          _isSearching = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Network error. Please check your connection.';
        _isSearching = false;
      });
    }
  }

  void _addWaypoint() {
    if (_selectedResult == null) return;

    final result = _selectedResult!;

    // Create waypoint from search result
    final waypoint = Waypoint(
      id: const Uuid().v4(),
      name: result.name,
      latitude: result.latitude,
      longitude: result.longitude,
      type: WaypointType.search,
      order: widget.nextOrder,
      estimatedDurationMinutes: _stopDuration,
      address: result.address,
    );

    widget.onWaypointAdded(waypoint);
    Navigator.pop(context);
  }
}

/// Search result from geocoding API
class SearchResult {
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  SearchResult({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      name: json['name'] as String,
      address: json['address'] as String,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResult &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}
