import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/geocoding_service.dart';
import '../services/trip_service.dart';
import 'location_search_screen.dart';

/// Slice B: collects the minimum needed to create a trip (origin,
/// destination) plus optional date range, arrival time, daily drive
/// cap, and time-budget mode. Submits to TripService.create and returns
/// the saved [Trip] via Navigator.pop so MyTripsScreen can push the
/// detail screen on top.
///
/// One scroll page, not a multi-step flow — required fields are small
/// enough that staging would be friction without payoff. The trip
/// detail screen handles further edits once the trip exists.
class NewTripWizardScreen extends StatefulWidget {
  const NewTripWizardScreen({super.key});

  @override
  State<NewTripWizardScreen> createState() => _NewTripWizardScreenState();
}

class _NewTripWizardScreenState extends State<NewTripWizardScreen> {
  final _nameCtrl = TextEditingController();
  GeocodeCandidate? _origin;
  GeocodeCandidate? _destination;
  String? _startDate;
  String? _endDate;
  String? _arrivalTime;
  int _dailyDriveCapHours = 6;
  String _mode = 'moderate';
  bool _saving = false;
  bool _nameTouchedByUser = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String _autoName() {
    if (_origin != null && _destination != null) {
      return '${_origin!.name} → ${_destination!.name}';
    }
    return '';
  }

  void _maybeAutoFillName() {
    if (_nameTouchedByUser) return;
    final auto = _autoName();
    if (auto.isEmpty) return;
    _nameCtrl.text = auto;
  }

  Future<void> _pickLocation({required bool isOrigin}) async {
    final picked = await Navigator.of(context).push<GeocodeCandidate>(
      MaterialPageRoute(
        builder: (_) => LocationSearchScreen(
          title: isOrigin ? 'Origin' : 'Destination',
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isOrigin) {
        _origin = picked;
      } else {
        _destination = picked;
      }
      _maybeAutoFillName();
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_parseIsoDate(_startDate) ?? DateTime.now())
        : (_parseIsoDate(_endDate) ??
            _parseIsoDate(_startDate) ??
            DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = _formatIsoDate(picked);
        // End-before-start guard: clear end if it precedes the new start.
        final end = _parseIsoDate(_endDate);
        if (end != null && end.isBefore(picked)) _endDate = null;
      } else {
        _endDate = _formatIsoDate(picked);
      }
    });
  }

  Future<void> _pickArrivalTime() async {
    final initial =
        _parseHM(_arrivalTime) ?? const TimeOfDay(hour: 17, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      _arrivalTime =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    });
  }

  bool get _canSubmit =>
      _origin != null && _destination != null && !_saving;

  Future<void> _submit() async {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) return;

    setState(() => _saving = true);
    final name = _nameCtrl.text.trim().isEmpty ? _autoName() : _nameCtrl.text.trim();
    final draft = Trip(
      name: name,
      originName: origin.name.isEmpty ? origin.displayLine : origin.name,
      originLat: origin.lat,
      originLng: origin.lng,
      destinationName: destination.name.isEmpty
          ? destination.displayLine
          : destination.name,
      destinationLat: destination.lat,
      destinationLng: destination.lng,
      startDate: _startDate,
      endDate: _endDate,
      arrivalTime: _arrivalTime,
      dailyDriveCapHours: _dailyDriveCapHours,
      timeBudgetMode: _mode,
    );
    final saved = await TripService.create(draft);
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to create trip')),
      );
      return;
    }
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New trip')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionLabel('Where'),
          _LocationField(
            label: 'From',
            icon: Icons.my_location,
            candidate: _origin,
            onTap: () => _pickLocation(isOrigin: true),
          ),
          const SizedBox(height: 12),
          _LocationField(
            label: 'To',
            icon: Icons.flag_outlined,
            candidate: _destination,
            onTap: () => _pickLocation(isOrigin: false),
          ),
          const SizedBox(height: 24),
          _SectionLabel('Name'),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              hintText: 'Auto-fills from origin → destination',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _nameTouchedByUser = true,
          ),
          const SizedBox(height: 24),
          _SectionLabel('When (optional)'),
          _DateRow(
            label: 'Start',
            value: _startDate,
            onPick: () => _pickDate(isStart: true),
            onClear: _startDate != null
                ? () => setState(() => _startDate = null)
                : null,
          ),
          _DateRow(
            label: 'End',
            value: _endDate,
            onPick: () => _pickDate(isStart: false),
            onClear: _endDate != null
                ? () => setState(() => _endDate = null)
                : null,
          ),
          const SizedBox(height: 16),
          _SectionLabel('Arrive by (optional)'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.access_time),
                  label: Text(_arrivalTime ?? 'No constraint'),
                  onPressed: _pickArrivalTime,
                ),
              ),
              if (_arrivalTime != null)
                TextButton(
                  onPressed: () => setState(() => _arrivalTime = null),
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
                  value: _dailyDriveCapHours.toDouble(),
                  min: 2,
                  max: 12,
                  divisions: 10,
                  label: '$_dailyDriveCapHours hr',
                  onChanged: (v) =>
                      setState(() => _dailyDriveCapHours = v.round()),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '$_dailyDriveCapHours hr',
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
            selected: {_mode},
            onSelectionChanged: (selected) =>
                setState(() => _mode = selected.first),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _canSubmit ? _submit : null,
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
            label: const Text('Create trip'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          if (_origin == null || _destination == null) ...[
            const SizedBox(height: 12),
            const Text(
              'Pick an origin and destination to continue.',
              style: TextStyle(color: Colors.white60, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _LocationField extends StatelessWidget {
  final String label;
  final IconData icon;
  final GeocodeCandidate? candidate;
  final VoidCallback onTap;

  const _LocationField({
    required this.label,
    required this.icon,
    required this.candidate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = candidate != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.chevron_right),
        ),
        child: hasValue
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    candidate!.name.isEmpty
                        ? candidate!.displayLine
                        : candidate!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (candidate!.fullAddress != null &&
                      candidate!.fullAddress!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        candidate!.fullAddress!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              )
            : const Text(
                'Search for a place',
                style: TextStyle(color: Colors.white54),
              ),
      ),
    );
  }
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
          SizedBox(width: 60, child: Text(label)),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(value ?? 'Pick'),
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
