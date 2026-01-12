import 'package:flutter/material.dart';
import 'dart:async';
import '../models/waypoint.dart';
import '../services/navigation_service.dart';

/// Floating arrival notification shown during navigation when reaching a waypoint
///
/// Features:
/// - Live stop timer with 1-second updates
/// - Visual comparison of planned vs actual time
/// - Manual acknowledgment ("I'm Here" button)
/// - Quick actions (Skip, Continue)
/// - Overtime indicator when exceeding planned duration
/// - Auto-departure hint for user awareness
class WaypointArrivalNotification extends StatefulWidget {
  final Waypoint waypoint;
  final VoidCallback? onDismiss;

  const WaypointArrivalNotification({
    Key? key,
    required this.waypoint,
    this.onDismiss,
  }) : super(key: key);

  @override
  State<WaypointArrivalNotification> createState() =>
      _WaypointArrivalNotificationState();
}

class _WaypointArrivalNotificationState
    extends State<WaypointArrivalNotification> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _acknowledged = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsed = Duration(seconds: timer.tick);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final plannedMinutes = widget.waypoint.estimatedDurationMinutes;
    final elapsedMinutes = _elapsed.inMinutes;
    final isOvertime = elapsedMinutes > plannedMinutes;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue.shade700,
              Colors.blue.shade900,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with icon and waypoint name
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Arrived at Stop',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.waypoint.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Stop timer card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isOvertime
                    ? Colors.orange.withOpacity(0.2)
                    : Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isOvertime
                      ? Colors.orange.withOpacity(0.5)
                      : Colors.white.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  // Large timer display
                  Text(
                    _formatElapsed(_elapsed),
                    style: TextStyle(
                      color: isOvertime ? Colors.orange : Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Planned duration info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Planned: $plannedMinutes min',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),

                  // Overtime indicator
                  if (isOvertime) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${elapsedMinutes - plannedMinutes} min over',
                      style: TextStyle(
                        color: Colors.orange.shade200,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Action buttons
            if (!_acknowledged) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _acknowledged = true);
                    // Optional: Could trigger additional UI feedback
                  },
                  icon: const Icon(Icons.check_circle),
                  label: const Text("I'm Here"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blue.shade900,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Skip and Continue buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await NavigationService.skipCurrentWaypoint();
                      widget.onDismiss?.call();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await NavigationService.continueFromWaypoint();
                      widget.onDismiss?.call();
                    },
                    icon: const Icon(Icons.navigation),
                    label: const Text('Continue'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),

            // Auto-departure hint
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Colors.white60,
                ),
                const SizedBox(width: 6),
                Text(
                  'Auto-continues when you start driving',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Format elapsed duration as MM:SS
  String _formatElapsed(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
