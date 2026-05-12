import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/trip_service.dart';

/// Single-trip detail. Slice A landed read-only; this slice makes the
/// secondary fields editable in place (name, dates, arrival time, daily
/// drive cap, mode, notes). Origin/destination stay read-only here —
/// they need the geocoding picker the new-trip wizard provides; that's
/// the next sub-slice.
///
/// The full planning canvas (timeline + map + pin types) is still
/// further out; the "Canvas coming soon" placeholder remains at the
/// bottom of the form.
class TripDetailScreen extends StatefulWidget {
  final Trip trip;
  const TripDetailScreen({super.key, required this.trip});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  late Trip _trip = widget.trip;
  late final _nameCtrl = TextEditingController(text: _trip.name);
  late final _notesCtrl = TextEditingController(text: _trip.notes ?? '');

  bool _deleting = false;
  bool _saving = false;
  bool _dirty = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_parseIsoDate(_trip.startDate) ?? DateTime.now())
        : (_parseIsoDate(_trip.endDate) ??
            _parseIsoDate(_trip.startDate) ??
            DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    final iso = _formatIsoDate(picked);
    setState(() {
      _trip = isStart
          ? _trip.copyWith(startDate: iso)
          : _trip.copyWith(endDate: iso);
      _dirty = true;
    });
  }

  void _clearDate({required bool isStart}) {
    setState(() {
      _trip = isStart
          ? _trip.copyWith(clearStartDate: true)
          : _trip.copyWith(clearEndDate: true);
      _dirty = true;
    });
  }

  Future<void> _pickArrivalTime() async {
    final initial = _parseHM(_trip.arrivalTime) ?? const TimeOfDay(hour: 17, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      _trip = _trip.copyWith(
        arrivalTime:
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
      );
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final next = _trip.copyWith(
      name: _nameCtrl.text.trim().isEmpty ? _trip.name : _nameCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      clearNotes: _notesCtrl.text.trim().isEmpty,
    );
    final saved = await TripService.update(next);
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save trip')),
      );
      return;
    }
    setState(() {
      _trip = saved;
      _nameCtrl.text = saved.name;
      _notesCtrl.text = saved.notes ?? '';
      _dirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trip saved')),
    );
  }

  Future<void> _delete() async {
    final id = _trip.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete trip?'),
        content: Text('"${_trip.name}" will be removed permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    final ok = await TripService.delete(id);
    if (!mounted) return;
    if (!ok) {
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete trip')),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Trip'),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete trip',
              onPressed: _deleting ? null : _delete,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Trip name',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _markDirty(),
            ),
            const SizedBox(height: 24),
            _ReadOnlyRow(label: 'From', value: _trip.originName),
            _ReadOnlyRow(label: 'To', value: _trip.destinationName),
            const SizedBox(height: 8),
            const _Hint(
                'Origin and destination editing comes with the new-trip wizard.'),
            const SizedBox(height: 24),
            _SectionLabel('Dates'),
            _DateRow(
              label: 'Start',
              value: _trip.startDate,
              onPick: () => _pickDate(isStart: true),
              onClear: _trip.startDate != null
                  ? () => _clearDate(isStart: true)
                  : null,
            ),
            _DateRow(
              label: 'End',
              value: _trip.endDate,
              onPick: () => _pickDate(isStart: false),
              onClear: _trip.endDate != null
                  ? () => _clearDate(isStart: false)
                  : null,
            ),
            const SizedBox(height: 24),
            _SectionLabel('Arrive by'),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.access_time),
                    label: Text(_trip.arrivalTime ?? 'No constraint'),
                    onPressed: _pickArrivalTime,
                  ),
                ),
                if (_trip.arrivalTime != null)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _trip = _trip.copyWith(clearArrivalTime: true);
                        _dirty = true;
                      });
                    },
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            _SectionLabel('Daily drive cap'),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _trip.dailyDriveCapHours.toDouble(),
                    min: 2,
                    max: 12,
                    divisions: 10,
                    label: '${_trip.dailyDriveCapHours} hr',
                    onChanged: (v) {
                      setState(() {
                        _trip = _trip.copyWith(dailyDriveCapHours: v.round());
                        _dirty = true;
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '${_trip.dailyDriveCapHours} hr',
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionLabel('Mode'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'hurry', label: Text('Hurry')),
                ButtonSegment(value: 'moderate', label: Text('Moderate')),
                ButtonSegment(value: 'discovery', label: Text('Discovery')),
              ],
              selected: {_trip.timeBudgetMode},
              onSelectionChanged: (selected) {
                final mode = selected.first;
                setState(() {
                  _trip = _trip.copyWith(timeBudgetMode: mode);
                  _dirty = true;
                });
              },
            ),
            const SizedBox(height: 24),
            _SectionLabel('Notes'),
            TextField(
              controller: _notesCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. Already booked the Mendocino Inn — confirmation #ABC123',
              ),
              onChanged: (_) => _markDirty(),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Icon(Icons.construction, size: 18),
                      SizedBox(width: 8),
                      Text('Canvas coming soon',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Timeline, map, and stop pins land in a future update. '
                    'For now this screen confirms the trip is saved and '
                    'lets you adjust the basics.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: (_dirty && !_saving) ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check),
              label: const Text('Save changes'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

DateTime? _parseIsoDate(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  return DateTime.tryParse(iso);
}

String _formatIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

TimeOfDay? _parseHM(String? hm) {
  if (hm == null || hm.isEmpty) return null;
  final parts = hm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h, minute: m);
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReadOnlyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 12,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const _DateRow({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text(value ?? 'Pick a date'),
              onPressed: onPick,
            ),
          ),
          if (onClear != null)
            TextButton(
              onPressed: onClear,
              child: const Text('Clear'),
            ),
        ],
      ),
    );
  }
}
