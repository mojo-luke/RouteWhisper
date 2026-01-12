import 'package:flutter/material.dart';
import 'package:frontend/models/waypoint.dart';
import 'edit_stop_duration_dialog.dart';

/// Waypoint List Widget - Displays and manages route waypoints
///
/// Features:
/// - Display all waypoints in order
/// - Reorder waypoints (drag & drop)
/// - Remove waypoints
/// - Show stop duration
/// - Show waypoint status (during navigation)
class WaypointList extends StatefulWidget {
  final List<Waypoint> waypoints;
  final bool allowEditing; // Allow reorder/remove before navigation
  final bool showStatus; // Show waypoint status during navigation
  final Function(Waypoint)? onEdit;
  final Function(Waypoint)? onRemove;
  final Function(int, int)? onReorder;

  const WaypointList({
    Key? key,
    required this.waypoints,
    this.allowEditing = true,
    this.showStatus = false,
    this.onEdit,
    this.onRemove,
    this.onReorder,
  }) : super(key: key);

  @override
  State<WaypointList> createState() => _WaypointListState();
}

class _WaypointListState extends State<WaypointList> {
  @override
  Widget build(BuildContext context) {
    if (widget.waypoints.isEmpty) {
      return _buildEmptyState();
    }

    // Get intermediate waypoints only (exclude origin/destination for display)
    final intermediateWaypoints = widget.waypoints
        .where((wp) =>
            wp.type != WaypointType.origin && wp.type != WaypointType.destination)
        .toList();

    if (intermediateWaypoints.isEmpty && widget.allowEditing) {
      return _buildEmptyState();
    }

    if (widget.allowEditing && widget.onReorder != null) {
      // Reorderable list for editing
      return ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: intermediateWaypoints.length,
        onReorder: (oldIndex, newIndex) {
          widget.onReorder?.call(oldIndex, newIndex);
        },
        itemBuilder: (context, index) {
          final waypoint = intermediateWaypoints[index];
          return _buildWaypointCard(waypoint, index, key: ValueKey(waypoint.id));
        },
      );
    } else {
      // Standard list (navigation or read-only)
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: intermediateWaypoints.length,
        itemBuilder: (context, index) {
          final waypoint = intermediateWaypoints[index];
          return _buildWaypointCard(waypoint, index);
        },
      );
    }
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.add_location_alt_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No waypoints added',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add POIs as stops to customize your route',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaypointCard(Waypoint waypoint, int index, {Key? key}) {
    return Card(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      child: ListTile(
        leading: _buildLeadingIcon(waypoint, index),
        title: Text(
          waypoint.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_getTypeLabel(waypoint.type)),
            const SizedBox(height: 4),
            _buildDurationRow(waypoint),
          ],
        ),
        trailing: widget.allowEditing
            ? _buildRemoveButton(waypoint)
            : (widget.showStatus ? _buildStatusIcon(waypoint) : null),
      ),
    );
  }

  Widget _buildLeadingIcon(Waypoint waypoint, int index) {
    if (widget.showStatus) {
      return _buildStatusIcon(waypoint);
    }

    // Show number for editing/planning mode
    return CircleAvatar(
      backgroundColor: Theme.of(context).primaryColor,
      child: Text(
        '${index + 1}',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDurationRow(Waypoint waypoint) {
    return Row(
      children: [
        const Icon(Icons.access_time, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text(
          '${waypoint.estimatedDurationMinutes} min stop',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (widget.allowEditing && widget.onEdit != null) ...[
          const SizedBox(width: 8),
          InkWell(
            onTap: () => widget.onEdit?.call(waypoint),
            child: Text(
              'Edit',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).primaryColor,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRemoveButton(Waypoint waypoint) {
    return IconButton(
      icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
      onPressed: () {
        // Show confirmation dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove Waypoint'),
            content: Text('Remove ${waypoint.name} from your route?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onRemove?.call(waypoint);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusIcon(Waypoint waypoint) {
    IconData icon;
    Color color;

    switch (waypoint.status) {
      case WaypointStatus.pending:
        icon = Icons.radio_button_unchecked;
        color = Colors.grey;
        break;
      case WaypointStatus.active:
        icon = Icons.location_on;
        color = Colors.blue;
        break;
      case WaypointStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case WaypointStatus.skipped:
        icon = Icons.cancel;
        color = Colors.orange;
        break;
    }

    return Icon(icon, color: color, size: 32);
  }

  String _getTypeLabel(WaypointType type) {
    switch (type) {
      case WaypointType.poi:
        return 'POI Stop';
      case WaypointType.manual:
        return 'Custom Stop';
      case WaypointType.search:
        return 'Address';
      case WaypointType.origin:
        return 'Start';
      case WaypointType.destination:
        return 'End';
    }
  }
}

/// Waypoint List with Header - Complete widget with title and summary
class WaypointListWithHeader extends StatelessWidget {
  final List<Waypoint> waypoints;
  final bool allowEditing;
  final bool showStatus;
  final String? title;
  final Function(Waypoint)? onEdit;
  final Function(Waypoint)? onRemove;
  final Function(int, int)? onReorder;
  final VoidCallback? onClearAll;

  const WaypointListWithHeader({
    Key? key,
    required this.waypoints,
    this.allowEditing = true,
    this.showStatus = false,
    this.title,
    this.onEdit,
    this.onRemove,
    this.onReorder,
    this.onClearAll,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final intermediateWaypoints = waypoints
        .where((wp) =>
            wp.type != WaypointType.origin && wp.type != WaypointType.destination)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title ?? 'Waypoints',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (intermediateWaypoints.isNotEmpty && allowEditing && onClearAll != null)
                TextButton.icon(
                  onPressed: onClearAll,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear All'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
            ],
          ),
        ),

        // Summary
        if (intermediateWaypoints.isNotEmpty) _buildSummary(intermediateWaypoints),

        // List
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: WaypointList(
            waypoints: waypoints,
            allowEditing: allowEditing,
            showStatus: showStatus,
            onEdit: onEdit,
            onRemove: onRemove,
            onReorder: onReorder,
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(List<Waypoint> intermediateWaypoints) {
    final totalStopMinutes = intermediateWaypoints.fold<int>(
      0,
      (sum, wp) => sum + wp.estimatedDurationMinutes,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem(
            icon: Icons.location_on,
            label: 'Stops',
            value: '${intermediateWaypoints.length}',
          ),
          _buildSummaryItem(
            icon: Icons.access_time,
            label: 'Total Time',
            value: _formatDuration(totalStopMinutes),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.blue.shade700),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade900,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.blue.shade700,
          ),
        ),
      ],
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
    }
  }
}
