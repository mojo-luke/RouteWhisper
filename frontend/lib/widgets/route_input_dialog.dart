import 'package:flutter/material.dart';
import '../services/navigation_service.dart';

class RouteInputDialog extends StatefulWidget {
  const RouteInputDialog({super.key});

  @override
  State<RouteInputDialog> createState() => _RouteInputDialogState();
}

class _RouteInputDialogState extends State<RouteInputDialog> {
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Plan Your Route'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _originController,
            decoration: const InputDecoration(
              labelText: 'From (Origin)',
              hintText: 'Enter starting location',
              prefixIcon: Icon(Icons.my_location),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _destinationController,
            decoration: const InputDecoration(
              labelText: 'To (Destination)',
              hintText: 'Enter destination',
              prefixIcon: Icon(Icons.location_on),
            ),
          ),
          const SizedBox(height: 16),

          // Quick Options
          const Text(
            'Quick Options:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('SF → LA'),
                onPressed: () => _fillSampleRoute('SF to LA'),
              ),
              ActionChip(
                label: const Text('Current → SF'),
                onPressed: () => _fillSampleRoute('Current to SF'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _startNavigation,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Start Navigation'),
        ),
      ],
    );
  }

  void _fillSampleRoute(String route) {
    switch (route) {
      case 'SF to LA':
        _originController.text = 'San Francisco, CA';
        _destinationController.text = 'Los Angeles, CA';
        break;
      case 'Current to SF':
        _originController.text = 'Current Location';
        _destinationController.text = 'San Francisco, CA';
        break;
    }
  }

  void _startNavigation() async {
    if (_originController.text.isEmpty || _destinationController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both origin and destination'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // For now, use sample coordinates
      // In a real app, you'd geocode the addresses
      await NavigationService.startNavigation(
        originLat: 37.7749, // San Francisco
        originLng: -122.4194,
        destLat: 34.0522, // Los Angeles
        destLng: -118.2437,
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to start navigation: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
