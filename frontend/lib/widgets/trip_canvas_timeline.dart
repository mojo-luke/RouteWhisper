import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../models/trip_pin.dart';

/// Horizontal strip at the top of the trip canvas showing the route
/// sequence: origin → stops (anchors + suggested) → destination.
///
/// Anchor chips (amber) show a × to remove.
/// Suggested chips (blue-grey) show a ✓ to promote to anchor and a × to dismiss.
///
/// The caller handles undo SnackBars (UX rule #4).
class TripCanvasTimeline extends StatelessWidget {
  final Trip trip;
  final List<TripPin> pins;
  final void Function(TripPin pin) onRemovePin;
  final void Function(TripPin pin)? onPromotePin;

  const TripCanvasTimeline({
    super.key,
    required this.trip,
    required this.pins,
    required this.onRemovePin,
    this.onPromotePin,
  });

  @override
  Widget build(BuildContext context) {
    final stops = pins
        .where((p) => p.type == 'anchor' || p.type == 'suggested')
        .toList();

    return Container(
      height: 64,
      color: Colors.black.withOpacity(0.75),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        children: [
          _EndpointChip(
            label: trip.originName,
            color: const Color(0xFF66BB6A),
          ),
          if (stops.isNotEmpty) ...[
            const _Divider(),
            for (final pin in stops) ...[
              if (pin.type == 'suggested')
                _SuggestedChip(
                  pin: pin,
                  onPromote: onPromotePin != null ? () => onPromotePin!(pin) : null,
                  onDismiss: () => onRemovePin(pin),
                )
              else
                _AnchorChip(
                  pin: pin,
                  onRemove: () => onRemovePin(pin),
                ),
              const _Divider(),
            ],
          ] else
            const _Divider(),
          _EndpointChip(
            label: trip.destinationName,
            color: const Color(0xFFEF5350),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Center(
        child: Icon(Icons.chevron_right, size: 16, color: Colors.white38),
      ),
    );
  }
}

class _EndpointChip extends StatelessWidget {
  final String label;
  final Color color;

  const _EndpointChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 5),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
      backgroundColor: Colors.white12,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _AnchorChip extends StatelessWidget {
  final TripPin pin;
  final VoidCallback onRemove;

  const _AnchorChip({required this.pin, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: const CircleAvatar(
        backgroundColor: Color(0xFFFFA726),
        radius: 5,
      ),
      label: Text(
        pin.name,
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
      backgroundColor: Colors.white12,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      onDeleted: onRemove,
      deleteIconColor: Colors.white54,
      deleteButtonTooltipMessage: 'Remove stop',
    );
  }
}

/// Suggested pin chip — shows a ✓ (promote) and × (dismiss) action pair.
class _SuggestedChip extends StatelessWidget {
  final TripPin pin;
  final VoidCallback? onPromote;
  final VoidCallback onDismiss;

  const _SuggestedChip({
    required this.pin,
    required this.onPromote,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF78909C), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFF78909C),
            radius: 5,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Text(
              pin.name,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onPromote != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onPromote,
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.check, size: 14, color: Color(0xFF66BB6A)),
              ),
            ),
          ],
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onDismiss,
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }
}
