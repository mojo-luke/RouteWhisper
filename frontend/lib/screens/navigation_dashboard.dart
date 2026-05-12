import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'my_trips_screen.dart';
import 'preferences_screen.dart';
import '../services/navigation_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/budget_pill.dart';
import '../widgets/narration_card.dart';
import '../widgets/route_input_dialog.dart';
import '../widgets/poi_dashboard.dart';
import '../widgets/waypoint_list.dart';
import '../widgets/edit_stop_duration_dialog.dart';
import '../widgets/search_waypoint_dialog.dart';
import '../models/waypoint.dart';

class NavigationDashboard extends StatefulWidget {
  const NavigationDashboard({super.key});

  @override
  State<NavigationDashboard> createState() => _NavigationDashboardState();
}

class _NavigationDashboardState extends State<NavigationDashboard> {
  // UI-only state (transient, not managed by Provider)
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    NavigationService.initialize();
    // Navigation state, waypoints, and route polyline come from Provider — widgets
    // rebuild automatically when state changes.
    _hydrateBudgetFromProfile();
  }

  /// Pull the signed-in user's profile and apply it to the live services:
  ///   * Seeds `WaypointManager.tripBudgetMinutes` so the BudgetPill renders
  ///     on first paint.
  ///   * Configures `RecommendationService` with the user's enable toggle
  ///     and per-trip / gap limits, so the in-nav surfaces respect their
  ///     choice on the next trip.
  /// Best-effort: if the profile fetch fails, both surfaces fall back to
  /// their default (built-in) settings.
  Future<void> _hydrateBudgetFromProfile() async {
    final profile = await UserProfileService.fetch();
    if (!mounted || profile == null) return;
    NavigationService.waypointManager
        .setTripBudget(profile.defaultTimeBudgetMinutes);
    NavigationService.recommendations.configure(
      enabled: profile.recommendationsEnabled,
      maxPerTrip: profile.recommendationsMaxPerTrip,
      minGapBetweenSurfaces:
          Duration(minutes: profile.recommendationsMinGapMinutes),
    );
  }

  @override
  void dispose() {
    // Clean up (good practice)
    super.dispose();
  }

  String _getStatusMessage(NavigationState state) {
    switch (state) {
      case NavigationState.idle:
        return 'Ready to start your journey';
      case NavigationState.calculating:
        return 'Finding the best route...';
      case NavigationState.navigating:
        return 'Navigation active • Drive safely';
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
    // Get state from Provider (automatically rebuilds when state changes)
    final navigationController = context.watch<NavigationController>();
    final waypointManager = context.watch<WaypointManager>();

    final currentState = navigationController.currentState;
    final waypoints = waypointManager.getWaypoints();
    final statusMessage = _getStatusMessage(currentState);

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
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Center(child: BudgetPill()),
          ),
          IconButton(
            icon: const Icon(Icons.map_outlined, color: Colors.white),
            tooltip: 'My trips',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyTripsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.white),
            tooltip: 'Preferences',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PreferencesScreen(),
                ),
              );
              // Pull in any budget edit the user just made.
              _hydrateBudgetFromProfile();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Status Card
              _buildStatusCard(currentState, statusMessage),
              const SizedBox(height: 16),

              // Phase 1 narration: visible whenever a whisper is live.
              // Renders an empty SizedBox when there's no active narration,
              // so the layout doesn't jump when one arrives.
              const NarrationCard(),

              const SizedBox(height: 16),

              // Navigation Controls
              Expanded(child: _buildNavigationControls(currentState, waypoints)),

              // Bottom Actions
              _buildBottomActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(NavigationState currentState, String statusMessage) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _getStateColor(currentState).withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          // State Icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _getStateColor(currentState).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getStateIcon(currentState),
              size: 48,
              color: _getStateColor(currentState),
            ),
          ),
          const SizedBox(height: 16),

          // State Text
          Text(
            currentState.name.toUpperCase(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _getStateColor(currentState),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),

          // Status Message
          Text(
            statusMessage,
            style: const TextStyle(fontSize: 16, color: Colors.white70),
            textAlign: TextAlign.center,
          ),

          // Show route info when navigating
          if (NavigationService.currentRoute != null &&
              currentState == NavigationState.navigating) ...[
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

  Widget _buildNavigationControls(NavigationState currentState, List<Waypoint> waypoints) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Primary Action Button
          _buildPrimaryActionButton(currentState),
          const SizedBox(height: 20),

          // Secondary Actions
          Row(
            children: [
              Expanded(child: _buildOpenMapButton()),
              const SizedBox(width: 16),
              Expanded(child: _buildQuickNavigationButton()),
            ],
          ),

          const SizedBox(height: 16),

          // POI Discovery Button (Debug: showing unconditionally for now)
          _buildDiscoverPOIsButton(),
          const SizedBox(height: 8),
          // Debug info
          if (NavigationService.routePolyline != null)
            Text(
              'Route polyline available (${NavigationService.routePolyline!.length} chars)',
              style: TextStyle(color: Colors.green, fontSize: 10),
            )
          else
            const Text(
              'Waiting for route polyline...',
              style: TextStyle(color: Colors.orange, fontSize: 10),
            ),

          const SizedBox(height: 24),

          // Waypoint List (if there are waypoints)
          if (NavigationService.hasWaypoints) ...[
            // Visual separator before waypoints
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1,
                    color: Colors.white24,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'ROUTE STOPS',
                    style: TextStyle(
                      color: Colors.blue.shade300,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 1,
                    color: Colors.white24,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildWaypointSection(waypoints),
            const SizedBox(height: 24),
            // Visual separator after waypoints
            Container(
              height: 1,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
          ],

          // Cancel Button (when applicable)
          if (NavigationService.canCancel) ...[_buildCancelButton()],
        ],
      ),
    );
  }

  Widget _buildWaypointSection(List<Waypoint> waypoints) {
    final intermediateWaypoints = waypoints
        .where((wp) =>
            wp.type != WaypointType.origin && wp.type != WaypointType.destination)
        .toList();

    // Calculate total stop time
    final stopSummary = NavigationService.waypointManager.getStopSummary();
    final totalStopMinutes = stopSummary['totalStopMinutes'] as int;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blue.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Header with count
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.withOpacity(0.2), Colors.blue.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.alt_route, color: Colors.blue, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Route Stops',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${intermediateWaypoints.length} ${intermediateWaypoints.length == 1 ? 'stop' : 'stops'} planned',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {
                        // Show full waypoint list in dialog
                        _showWaypointListDialog();
                      },
                      icon: const Icon(Icons.settings, color: Colors.blue, size: 20),
                      tooltip: 'Manage Waypoints',
                    ),
                  ],
                ),
                // Trip time summary
                if (totalStopMinutes > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.green.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildTripSummaryItem(
                          icon: Icons.directions_car,
                          label: 'Stops',
                          value: '${intermediateWaypoints.length}',
                          color: Colors.blue,
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: Colors.white24,
                        ),
                        _buildTripSummaryItem(
                          icon: Icons.access_time,
                          label: 'Stop Time',
                          value: _formatStopDuration(totalStopMinutes),
                          color: Colors.orange,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Compact waypoint preview (first 3)
          if (intermediateWaypoints.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (int i = 0; i < intermediateWaypoints.length.clamp(0, 3); i++)
                    _buildCompactWaypointItem(intermediateWaypoints[i], i),
                  if (intermediateWaypoints.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '+${intermediateWaypoints.length - 3} more',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),

          // Action buttons
          Container(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                // Search Place button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showSearchWaypointDialog,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Search Place'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Recalculate Route button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _recalculateRouteWithWaypoints,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Recalculate'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactWaypointItem(Waypoint waypoint, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.blue,
            child: Text(
              '${index + 1}',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  waypoint.name,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${waypoint.estimatedDurationMinutes} min stop',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                ),
              ],
            ),
          ),
          Icon(waypoint.sourcePOI?.categoryIcon != null
              ? Icons.place
              : Icons.edit_location,
            color: Colors.blue,
            size: 16,
          ),
        ],
      ),
    );
  }

  Widget _buildTripSummaryItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade400,
          ),
        ),
      ],
    );
  }

  String _formatStopDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
    }
  }

  void _showWaypointListDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text(
          'Manage Waypoints',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: WaypointListWithHeader(
            allowEditing: true,
            onEdit: (waypoint) => _editStopDuration(waypoint),
            onRemove: (waypoint) {
              NavigationService.waypointManager.removeWaypoint(waypoint.id);
              // Rebuild dialog
              Navigator.pop(context);
              _showWaypointListDialog();
            },
            onReorder: (oldIndex, newIndex) {
              NavigationService.waypointManager.reorderWaypoint(oldIndex, newIndex);
            },
            onClearAll: () {
              NavigationService.waypointManager.clearIntermediateWaypoints();
              Navigator.pop(context);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _recalculateRouteWithWaypoints();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Recalculate Route'),
          ),
        ],
      ),
    );
  }

  void _editStopDuration(Waypoint waypoint) {
    showDialog(
      context: context,
      builder: (context) => EditStopDurationDialog(
        waypoint: waypoint,
        onDurationChanged: (newDuration) {
          final updatedWaypoint = waypoint.copyWith(
            estimatedDurationMinutes: newDuration,
          );
          NavigationService.waypointManager.updateWaypoint(updatedWaypoint);

          // Show confirmation
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Stop duration updated to $newDuration minutes'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }

  void _showSearchWaypointDialog() {
    final nextOrder = NavigationService.waypointManager.getWaypoints().length;

    showDialog(
      context: context,
      builder: (context) => SearchWaypointDialog(
        nextOrder: nextOrder,
        onWaypointAdded: (waypoint) {
          // Add waypoint to manager
          NavigationService.waypointManager.addWaypoint(waypoint);

          // Show confirmation
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
                          'Stop Added',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('${waypoint.name} added to your route'),
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
                  NavigationService.waypointManager.removeWaypoint(waypoint.id);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _recalculateRouteWithWaypoints() async {
    if (NavigationService.currentRoute == null) {
      _showErrorSnackBar('No active route. Please plan a route first.');
      return;
    }

    final route = NavigationService.currentRoute!;

    // No setState needed - NavigationController will notify Provider
    // when state changes to calculating

    try {
      // Use startNavigationWithWaypoints which handles everything
      await NavigationService.startNavigationWithWaypoints(
        originLat: route.originLat,
        originLng: route.originLng,
        destLat: route.destLat,
        destLng: route.destLng,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Route recalculated with waypoints!'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      _showErrorSnackBar('Failed to recalculate route: $e');
    }
  }

  Widget _buildPrimaryActionButton(NavigationState currentState) {
    String buttonText;
    VoidCallback? onPressed;
    Color buttonColor;

    switch (currentState) {
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
      case NavigationState.navigating:
        buttonText = 'View Navigation';
        buttonColor = Colors.green;
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
        label: const Text('Test Route (10 min)'),
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

  Widget _buildDiscoverPOIsButton() {
    final hasPOIs = NavigationService.hasPOIs;
    final hasPolyline = NavigationService.routePolyline != null;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: hasPolyline ? () {
          print('🔍 Discover POIs button pressed!');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const POIDashboard(),
            ),
          );
        } : null,
        icon: Icon(
          hasPOIs ? Icons.explore : Icons.search,
          size: 20,
        ),
        label: Text(
          hasPolyline
            ? (hasPOIs ? 'View POIs (${NavigationService.lastPOIResponse?.totalFound})' : 'Discover POIs')
            : 'Waiting for route...'
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: hasPOIs ? Colors.green.shade700 : Colors.blue.shade700,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade700,
          disabledForegroundColor: Colors.grey.shade400,
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
    // Short test route: SF Embarcadero to Fisherman's Wharf (~2.5 miles, 10 min)
    // Passes by: Ferry Building, restaurants, cafes, Pier 39
    // Perfect for testing waypoint arrivals with lots of POIs!
    await NavigationService.startNavigation(
      originLat: 37.7955,  // Embarcadero Center
      originLng: -122.3937,
      destLat: 37.8080,     // Fisherman's Wharf
      destLng: -122.4177,
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
      case NavigationState.navigating:
        return Colors.green;
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
      case NavigationState.navigating:
        return Icons.navigation;
      case NavigationState.completed:
        return Icons.check_circle;
      case NavigationState.cancelled:
        return Icons.cancel;
    }
  }
}
