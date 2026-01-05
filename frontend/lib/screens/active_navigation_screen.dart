import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// ActiveNavigationScreen - Full-screen Flutter navigation with Google Maps style
///
/// This screen provides turn-by-turn navigation entirely in Flutter using:
/// - Mapbox Maps Flutter for map display
/// - Custom Flutter widgets for turn-by-turn UI
/// - Native method channels for route calculation and progress
///
/// Features:
/// - Clean Google Maps-style interface
/// - Turn-by-turn instruction banner
/// - ETA and distance information
/// - Customizable and testable Flutter code
class ActiveNavigationScreen extends StatefulWidget {
  final double originLat;
  final double originLng;
  final double destLat;
  final double destLng;

  const ActiveNavigationScreen({
    Key? key,
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
  }) : super(key: key);

  @override
  State<ActiveNavigationScreen> createState() => _ActiveNavigationScreenState();
}

class _ActiveNavigationScreenState extends State<ActiveNavigationScreen> {
  MapboxMap? _mapboxMap;

  // Navigation state
  String _currentInstruction = 'Starting navigation...';
  String _distanceToManeuver = '';
  String _eta = '--:--';
  String _distanceRemaining = '-- mi';
  String _timeRemaining = '-- min';

  @override
  void initState() {
    super.initState();
    _initializeNavigation();
  }

  Future<void> _initializeNavigation() async {
    // TODO: Call native method channel to start route calculation
    // For now, show placeholder UI
    setState(() {
      _currentInstruction = 'Route calculating...';
    });
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;

    // Set initial camera position to origin
    _mapboxMap?.setCamera(
      CameraOptions(
        center: Point(
          coordinates: Position(widget.originLng, widget.originLat),
        ),
        zoom: 15.0,
      ),
    );
  }

  Future<void> _exitNavigation() async {
    // Show confirmation dialog
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Navigation?'),
        content: const Text('Are you sure you want to stop navigation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Exit'),
          ),
        ],
      ),
    );

    if (shouldExit == true && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Full-screen Mapbox map
          MapWidget(
            key: const ValueKey('navigation_map'),
            onMapCreated: _onMapCreated,
          ),

          // Turn-by-turn instruction banner (top)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _buildInstructionBanner(),
            ),
          ),

          // Exit button (top-left)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: _buildExitButton(),
          ),

          // ETA and distance info (bottom)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _buildTripInfoCard(),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionBanner() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Distance to next maneuver
          if (_distanceToManeuver.isNotEmpty)
            Text(
              _distanceToManeuver,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.blue[700],
              ),
            ),

          const SizedBox(height: 4),

          // Current instruction
          Text(
            _currentInstruction,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExitButton() {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: _exitNavigation,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: const Icon(
            Icons.close,
            size: 28,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildTripInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // ETA
          _buildInfoColumn(
            icon: Icons.access_time,
            label: 'ETA',
            value: _eta,
          ),

          // Divider
          Container(
            width: 1,
            height: 40,
            color: Colors.grey[300],
          ),

          // Distance remaining
          _buildInfoColumn(
            icon: Icons.straighten,
            label: 'Distance',
            value: _distanceRemaining,
          ),

          // Divider
          Container(
            width: 1,
            height: 40,
            color: Colors.grey[300],
          ),

          // Time remaining
          _buildInfoColumn(
            icon: Icons.timer,
            label: 'Time',
            value: _timeRemaining,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    // TODO: Stop navigation via method channel
    super.dispose();
  }
}
