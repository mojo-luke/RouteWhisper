import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/trip_service.dart';
import 'trip_canvas_screen.dart';

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

  // Monologue v1 vibe controls. See docs/companion-monologue-v1-plan.md.
  // The companion-vibe section lets a user pick narration themes and
  // add stop interests; both are sent to the backend on save and the
  // monologue is regenerated (idempotent — cache hit if vibe unchanged).

  /// Toggle a narration theme. Don't allow the empty set — fall back to
  /// History if the user deselects everything, so we always have a
  /// companion mode.
  void _toggleNarrationTheme(String theme) {
    final current = List<String>.from(_trip.narrationThemes);
    if (current.contains(theme)) {
      current.remove(theme);
      if (current.isEmpty) current.add('history');
    } else {
      current.add(theme);
    }
    setState(() {
      _trip = _trip.copyWith(narrationThemes: current);
      _dirty = true;
    });
  }

  Future<void> _addStopInterest() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _StopInterestEditor(),
    );
    if (result == null) return;
    setState(() {
      _trip = _trip.copyWith(
        stopInterests: [..._trip.stopInterests, result],
      );
      _dirty = true;
    });
  }

  void _removeStopInterest(int index) {
    final list = List<Map<String, dynamic>>.from(_trip.stopInterests);
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    setState(() {
      _trip = _trip.copyWith(stopInterests: list);
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
              icon: const Icon(Icons.map_outlined),
              tooltip: 'View on map',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TripCanvasScreen(trip: _trip),
                ),
              ),
            ),
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
            _SectionLabel('What should the companion talk about?'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _narrationThemeChips
                  .map((meta) => FilterChip(
                        label: Text(meta.label),
                        selected: _trip.narrationThemes.contains(meta.key),
                        onSelected: (_) => _toggleNarrationTheme(meta.key),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            const _Hint(
              'Pick one or more. Default is History. The companion '
              'narrates during the drive, anchored to towns on the route.',
            ),
            const SizedBox(height: 24),
            _SectionLabel('Stop interests'),
            const SizedBox(height: 8),
            if (_trip.stopInterests.isEmpty)
              const _Hint(
                'Optional. Add categories you\'d pull off the highway for — '
                'each can include a free-text detail like "Mexican" or '
                '"live music venues".',
              )
            else
              Column(
                children: [
                  for (var i = 0; i < _trip.stopInterests.length; i++)
                    _StopInterestRow(
                      interest: _trip.stopInterests[i],
                      onRemove: () => _removeStopInterest(i),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addStopInterest,
              icon: const Icon(Icons.add),
              label: const Text('Add stop interest'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
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


// ---- Monologue v1 vibe controls --------------------------------------

class _ThemeMeta {
  final String key;
  final String label;
  const _ThemeMeta(this.key, this.label);
}

// Keep in sync with backend NarrationTheme literal in app/database.py.
const List<_ThemeMeta> _narrationThemeChips = [
  _ThemeMeta('history', 'History'),
  _ThemeMeta('landscape', 'Landscape & nature'),
  _ThemeMeta('food_culture', 'Food culture'),
  _ThemeMeta('quirky', 'Quirky / weird'),
];

// Keep in sync with backend StopCategory literal in app/database.py.
const List<_StopCategoryMeta> _stopCategoryChoices = [
  _StopCategoryMeta('food', 'Food', Icons.restaurant),
  _StopCategoryMeta('entertainment', 'Entertainment', Icons.music_note),
  _StopCategoryMeta('attractions', 'Attractions / sights', Icons.attractions),
  _StopCategoryMeta('shopping', 'Shopping', Icons.shopping_bag),
];

class _StopCategoryMeta {
  final String key;
  final String label;
  final IconData icon;
  const _StopCategoryMeta(this.key, this.label, this.icon);
}

_StopCategoryMeta _categoryMetaFor(String key) =>
    _stopCategoryChoices.firstWhere(
      (c) => c.key == key,
      orElse: () => _stopCategoryChoices.first,
    );


/// One row in the stop-interests list. Shows category icon + label,
/// the detail text, and a remove button.
class _StopInterestRow extends StatelessWidget {
  final Map<String, dynamic> interest;
  final VoidCallback onRemove;

  const _StopInterestRow({required this.interest, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final meta = _categoryMetaFor((interest['category'] ?? '') as String);
    final detail = (interest['detail'] ?? '') as String;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(meta.icon, size: 20, color: Colors.white70),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      )
                    else
                      const Text(
                        'Any',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Remove',
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Bottom sheet for adding a stop interest. Returns the new
/// `{category, detail}` map via `Navigator.pop`, or `null` if
/// the user cancels.
class _StopInterestEditor extends StatefulWidget {
  const _StopInterestEditor();

  @override
  State<_StopInterestEditor> createState() => _StopInterestEditorState();
}

class _StopInterestEditorState extends State<_StopInterestEditor> {
  String _category = 'food';
  final _detailCtrl = TextEditingController();

  @override
  void dispose() {
    _detailCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop({
      'category': _category,
      'detail': _detailCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      // Lift above the keyboard.
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add a stop interest',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          const Text(
            'Category',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _stopCategoryChoices
                .map((meta) => ChoiceChip(
                      avatar: Icon(meta.icon, size: 18),
                      label: Text(meta.label),
                      selected: _category == meta.key,
                      onSelected: (_) => setState(() => _category = meta.key),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _detailCtrl,
            decoration: const InputDecoration(
              labelText: 'Detail (optional)',
              hintText: 'e.g. Mexican, hole-in-the-wall',
              border: OutlineInputBorder(),
              helperText: 'Leave blank for "any stop in this category".',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
