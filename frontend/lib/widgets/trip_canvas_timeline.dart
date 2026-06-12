import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../models/trip_pin.dart';

/// Horizontal strip at the top of the trip canvas showing the route
/// sequence: origin → anchor stops (in added order) → destination.
///
/// Tapping the × on an anchor chip triggers [onRemovePin]; the caller
/// is responsible for showing the undo SnackBar (UX rule #4).
class TripCanvasTimeline extends StatelessWidget {
  final Trip trip;
  final List<TripPin> pins;
  final void Function(TripPin pin) onRemovePin;

  const TripCanvasTimeline({
    super.key,
    required this.trip,
    required this.pins,
    required this.onRemovePin,
  });

  @override
  Widget build(BuildContext context) {
    final anchors = pins.where((p) => p.type == 'anchor').toList();
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
          if (anchors.isNotEmpty) ...[
            const _Divider(),
            for (final pin in anchors) ...[
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
