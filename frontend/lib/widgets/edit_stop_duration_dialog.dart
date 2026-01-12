import 'package:flutter/material.dart';
import 'package:frontend/models/waypoint.dart';

/// Dialog for editing waypoint stop duration
///
/// Features:
/// - Quick select buttons (5, 10, 15, 30, 45, 60 min)
/// - Custom slider (0-120 min)
/// - Category-based hints
class EditStopDurationDialog extends StatefulWidget {
  final Waypoint waypoint;
  final Function(int) onDurationChanged;

  const EditStopDurationDialog({
    super.key,
    required this.waypoint,
    required this.onDurationChanged,
  });

  @override
  State<EditStopDurationDialog> createState() => _EditStopDurationDialogState();
}

class _EditStopDurationDialogState extends State<EditStopDurationDialog> {
  late int _minutes;

  @override
  void initState() {
    super.initState();
    _minutes = widget.waypoint.estimatedDurationMinutes;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2D2D2D),
      title: const Text(
        'Stop Duration',
        style: TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How long do you plan to stop at ${widget.waypoint.name}?',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),

            // Quick select buttons
            const Text(
              'Quick Select:',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [5, 10, 15, 30, 45, 60].map((min) {
                final isSelected = _minutes == min;
                return ChoiceChip(
                  label: Text('$min min'),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _minutes = min);
                    }
                  },
                  selectedColor: Colors.blue,
                  backgroundColor: Colors.grey.shade800,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // Custom slider
            const Text(
              'Custom Duration:',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue.withOpacity(0.3),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.access_time, color: Colors.blue, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        '$_minutes minutes',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    value: _minutes.toDouble(),
                    min: 0,
                    max: 120,
                    divisions: 24,
                    label: '$_minutes min',
                    activeColor: Colors.blue,
                    inactiveColor: Colors.grey.shade700,
                    onChanged: (value) {
                      setState(() => _minutes = value.toInt());
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '0 min',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                      ),
                      Text(
                        '2 hrs',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Category average hint
            if (widget.waypoint.sourcePOI != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Typical ${widget.waypoint.sourcePOI!.categoryName} stop: ${_getTypicalDuration(widget.waypoint.sourcePOI!.category)} min',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.green,
                        ),
                      ),
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
          onPressed: () {
            widget.onDurationChanged(_minutes);
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }

  int _getTypicalDuration(String category) {
    switch (category.toLowerCase()) {
      case 'gas_station':
        return 10;
      case 'restaurant':
        return 45;
      case 'coffee':
      case 'cafe':
        return 20;
      case 'scenic':
      case 'viewpoint':
        return 30;
      case 'park':
        return 60;
      case 'rest_area':
        return 15;
      default:
        return 15;
    }
  }
}
