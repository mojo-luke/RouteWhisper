import 'package:flutter/material.dart';
import '../services/navigation_service.dart';
import '../widgets/route_input_dialog.dart';

class NavigationDashboard extends StatefulWidget {
  const NavigationDashboard({super.key});

  @override
  State<NavigationDashboard> createState() => _NavigationDashboardState();
}

class _NavigationDashboardState extends State<NavigationDashboard> {
  NavigationState _currentState = NavigationState.idle;
  String _statusMessage = 'Ready to navigate';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    NavigationService.initialize();

    // Set up callbacks using the new method
    NavigationService.setCallbacks(
      onStateChanged: (state) {
        setState(() {
          _currentState = state;
          _statusMessage = _getStatusMessage(state);
          _errorMessage = null; // Clear error when state changes
        });
      },
      onError: (error) {
        setState(() {
          _errorMessage = error;
        });
        _showErrorSnackBar(error);
      },
      onLocationUpdate: (location) {
        // Handle location updates if needed
        print('🎯 Location update: ${location.lat}, ${location.lng}');
      },
    );
  }

  String _getStatusMessage(NavigationState state) {
    switch (state) {
      case NavigationState.idle:
        return 'Ready to start your journey';
      case NavigationState.calculating:
        return 'Finding the best route...';
      case NavigationState.ready:
        return 'Route calculated • Ready to navigate';
      case NavigationState.navigating:
        return 'Navigation active • Drive safely';
      case NavigationState.paused:
        return 'Navigation paused';
      case NavigationState.completed:
        return 'You have arrived at your destination!';
      case NavigationState.cancelled:
        return 'Navigation cancelled';
    }
  }

  void _showErrorSnackBar(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A), // Dark theme for driving
      appBar: AppBar(
        title: const Text(
          'RouteWhisper',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF2D2D2D),
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Status Card
              _buildStatusCard(),
              const SizedBox(height: 32),

              // Navigation Controls
              Expanded(child: _buildNavigationControls()),

              // Bottom Actions
              _buildBottomActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _getStateColor(_currentState).withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          // State Icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _getStateColor(_currentState).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getStateIcon(_currentState),
              size: 48,
              color: _getStateColor(_currentState),
            ),
          ),
          const SizedBox(height: 16),

          // State Text
          Text(
            _currentState.name.toUpperCase(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _getStateColor(_currentState),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),

          // Status Message
          Text(
            _statusMessage,
            style: const TextStyle(fontSize: 16, color: Colors.white70),
            textAlign: TextAlign.center,
          ),

          // Show route info when navigating
          if (NavigationService.currentRoute != null &&
              (_currentState == NavigationState.ready ||
                  _currentState == NavigationState.navigating)) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          NavigationService.currentRoute!.originName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          NavigationService.currentRoute!.destName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Error Message
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
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
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavigationControls() {
    return Column(
      children: [
        // Primary Action Button
        _buildPrimaryActionButton(),
        const SizedBox(height: 20),

        // Secondary Actions
        Row(
          children: [
            Expanded(child: _buildOpenMapButton()),
            const SizedBox(width: 16),
            Expanded(child: _buildQuickNavigationButton()),
          ],
        ),

        const SizedBox(height: 24),

        // Cancel Button (when applicable)
        if (NavigationService.canCancel) ...[_buildCancelButton()],
      ],
    );
  }

  Widget _buildPrimaryActionButton() {
    String buttonText;
    VoidCallback? onPressed;
    Color buttonColor;

    switch (_currentState) {
      case NavigationState.idle:
        buttonText = 'Plan New Route';
        buttonColor = Colors.blue;
        onPressed = () => _showRouteInputDialog();
        break;
      case NavigationState.calculating:
        buttonText = 'Calculating...';
        buttonColor = Colors.orange;
        onPressed = null;
        break;
      case NavigationState.ready:
        buttonText = 'Start Navigation';
        buttonColor = Colors.green;
        onPressed = () => NavigationService.openMapView();
        break;
      case NavigationState.navigating:
        buttonText = 'View Navigation';
        buttonColor = Colors.green;
        onPressed = () => NavigationService.openMapView();
        break;
      case NavigationState.paused:
        buttonText = 'Resume Navigation';
        buttonColor = Colors.yellow;
        onPressed = () => NavigationService.openMapView();
        break;
      case NavigationState.completed:
        buttonText = 'Plan New Route';
        buttonColor = Colors.purple;
        onPressed = () => _showRouteInputDialog();
        break;
      case NavigationState.cancelled:
        buttonText = 'Plan New Route';
        buttonColor = Colors.blue;
        onPressed = () => _showRouteInputDialog();
        break;
    }

    return SizedBox(
      width: double.infinity,
      height: 64,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 8,
          disabledBackgroundColor: Colors.grey,
        ),
        child: Text(
          buttonText,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildOpenMapButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: () => NavigationService.openMapView(),
        icon: const Icon(Icons.map, size: 20),
        label: const Text('View Map'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3D3D3D),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickNavigationButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: () => _startSampleNavigation(),
        icon: const Icon(Icons.near_me, size: 20),
        label: const Text('Sample Route'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3D3D3D),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: () => NavigationService.cancelNavigation(),
        icon: const Icon(Icons.close, size: 20),
        label: const Text('Cancel Navigation'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildActionChip(
          icon: Icons.settings,
          label: 'Settings',
          onTap: () => _showSettingsDialog(),
        ),
        _buildActionChip(
          icon: Icons.history,
          label: 'Recent',
          onTap: () => _showRecentRoutesDialog(),
        ),
        _buildActionChip(
          icon: Icons.info_outline,
          label: 'About',
          onTap: () => _showAboutDialog(),
        ),
      ],
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // Action Methods
  void _showRouteInputDialog() {
    showDialog(
      context: context,
      builder: (context) => const RouteInputDialog(),
    );
  }

  void _startSampleNavigation() async {
    await NavigationService.startNavigation(
      originLat: 37.7749,
      originLng: -122.4194,
      destLat: 34.0522,
      destLng: -118.2437,
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settings'),
        content: const Text('Settings panel coming soon!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showRecentRoutesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recent Routes'),
        content: const Text('Recent routes feature coming soon!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About RouteWhisper'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RouteWhisper v1.0'),
            SizedBox(height: 8),
            Text('Navigate with interesting stories along the way.'),
            SizedBox(height: 8),
            Text('Powered by Mapbox Navigation SDK'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Color _getStateColor(NavigationState state) {
    switch (state) {
      case NavigationState.idle:
        return Colors.blue;
      case NavigationState.calculating:
        return Colors.orange;
      case NavigationState.ready:
        return Colors.green;
      case NavigationState.navigating:
        return Colors.green;
      case NavigationState.paused:
        return Colors.yellow;
      case NavigationState.completed:
        return Colors.purple;
      case NavigationState.cancelled:
        return Colors.red;
    }
  }

  IconData _getStateIcon(NavigationState state) {
    switch (state) {
      case NavigationState.idle:
        return Icons.explore;
      case NavigationState.calculating:
        return Icons.route;
      case NavigationState.ready:
        return Icons.play_arrow;
      case NavigationState.navigating:
        return Icons.navigation;
      case NavigationState.paused:
        return Icons.pause;
      case NavigationState.completed:
        return Icons.check_circle;
      case NavigationState.cancelled:
        return Icons.cancel;
    }
  }
}
