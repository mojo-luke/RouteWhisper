import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/waypoint_manager.dart';

/// Compact "X / Y min slack" chip that reflects the user's remaining
/// trip-budget time. Color codes:
///   * green  — slack remaining
///   * amber  — at zero
///   * red    — over budget
///
/// Renders nothing when no budget is set (so screens can drop the pill
/// in unconditionally without a wrapper).
class BudgetPill extends StatelessWidget {
  const BudgetPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WaypointManager>(
      builder: (context, manager, _) {
        final budget = manager.tripBudgetMinutes;
        if (budget == null) return const SizedBox.shrink();

        final remaining = manager.remainingBudgetMinutes ?? 0;
        final used = manager.usedBudgetMinutes;

        final Color background;
        final Color foreground;
        if (remaining > 0) {
          background = const Color(0xFF1F3D2A);
          foreground = const Color(0xFF7BE08F);
        } else if (remaining == 0) {
          background = const Color(0xFF3D331F);
          foreground = const Color(0xFFFFC857);
        } else {
          background = const Color(0xFF3D1F1F);
          foreground = const Color(0xFFFF8585);
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule, size: 14, color: foreground),
              const SizedBox(width: 6),
              Text(
                '$used / $budget min slack',
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
