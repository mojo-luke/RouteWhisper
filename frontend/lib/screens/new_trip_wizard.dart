import 'dart:async';

import 'package:flutter/material.dart';

import '../models/route_preview.dart';
import '../models/trip.dart';
import '../models/vibe_options.dart';
import '../services/geocoding_service.dart';
import '../services/trip_preview_service.dart';
import '../services/trip_service.dart';
import '../widgets/trip_preview_reveal.dart';
import 'location_search_screen.dart';

/// Progressive-reveal trip creation: a 4-step wizard that starts
/// building the trip preview (real drive stats, a text rundown, and
/// curated hotspots along the route) the moment origin+destination are
/// known — well before the user has named the trip or picked a vibe —
/// so the later steps' natural data entry covers the generation time
/// instead of the user staring at a spinner.
///
/// Replaces the old single-page form. Submits to TripService.create
/// and returns the saved [Trip] via Navigator.pop, same contract as
/// before — MyTripsScreen decides where to land next.
class NewTripWizardScreen extends StatefulWidget {
  const NewTripWizardScreen({super.key});

  @override
  State<NewTripWizardScreen> createState() => _NewTripWizardScreenState();
}

class _NewTripWizardScreenState extends State<NewTripWizardScreen> {
  static const _stepCount = 4;
  static const _stepTitles = [
    'Where are you headed?',
    'Call it something',
    'What are you in the mood for?',
    "Here's your drive",
  ];

  final _pageController = PageController();
  final _nameCtrl = TextEditingController();
  int _step = 0;
  bool _nameTouchedByUser = false;
  bool _saving = false;

  GeocodeCandidate? _origin;
  GeocodeCandidate? _destination;
  String? _startDate;
  String? _endDate;
  String? _arrivalTime;
  int _dailyDriveCapHours = 6;
  String _mode = 'moderate';
  List<String> _narrationThemes = ['history'];

  RoutePreview? _preview;
  StreamSubscription<RoutePreview>? _previewSub;
  final Set<String> _selectedHotspotIds = {};
  final Map<String, PreviewHotspot> _selectedHotspots = {};

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _previewSub?.cancel();
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
    _maybeStartPreview();
  }

  /// Kicks off (or restarts) preview generation once both endpoints are
  /// known. Safe to call repeatedly — restarts the poll against a new
  /// route if the user goes back and changes an endpoint; the old
  /// route's cached doc is left alone server-side.
  void _maybeStartPreview() {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) return;

    _previewSub?.cancel();
    setState(() => _preview = null);

    unawaited(() async {
      final started = await TripPreviewService.start(
        origin: origin,
        destination: destination,
      );
      if (!mounted || started == null) return;
      setState(() => _preview = started);
      if (started.status == PreviewStatus.pending) {
        _previewSub = TripPreviewService.watch(started.polylineHash).listen(
          (update) {
            if (!mounted) return;
            setState(() => _preview = update);
          },
        );
      }
    }());
  }

  void _toggleHotspot(PreviewHotspot hotspot) {
    setState(() {
      if (_selectedHotspotIds.contains(hotspot.id)) {
        _selectedHotspotIds.remove(hotspot.id);
        _selectedHotspots.remove(hotspot.id);
      } else {
        _selectedHotspotIds.add(hotspot.id);
        _selectedHotspots[hotspot.id] = hotspot;
      }
    });
  }

  bool get _canContinueFromWhere => _origin != null && _destination != null;

  void _goNext() {
    if (_step == 0 && !_canContinueFromWhere) return;
    if (_step >= _stepCount - 1) return;
    setState(() => _step++);
    _pageController.animateToPage(
      _step,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _goBack() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step--);
    _pageController.animateToPage(
      _step,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

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
      narrationThemes: _narrationThemes,
      pins: _selectedHotspots.values.map((h) => h.toPin()).toList(),
      polyline: _preview?.polyline,
      distanceMiles: _preview?.distanceMiles,
      durationMinutes: _preview?.durationMinutes,
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

  void _toggleNarrationTheme(String theme) {
    final current = List<String>.from(_narrationThemes);
    if (current.contains(theme)) {
      current.remove(theme);
      if (current.isEmpty) current.add('history');
    } else {
      current.add(theme);
    }
    setState(() => _narrationThemes = current);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _saving ? null : _goBack,
        ),
        title: Text(_stepTitles[_step]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / _stepCount,
          ),
        ),
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildWhereStep(),
          _buildNameStep(),
          _buildVibeStep(),
          TripPreviewReveal(
            preview: _preview,
            preferredThemes: _narrationThemes,
            selectedHotspotIds: _selectedHotspotIds,
            onToggleHotspot: _toggleHotspot,
            onRetry: _maybeStartPreview,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _step == _stepCount - 1
              ? FilledButton.icon(
                  onPressed: _saving ? null : _submit,
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
                )
              : FilledButton(
                  onPressed:
                      (_step == 0 && !_canContinueFromWhere) ? null : _goNext,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Continue'),
                ),
        ),
      ),
    );
  }

  Widget _buildWhereStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
        if (!_canContinueFromWhere) ...[
          const SizedBox(height: 12),
          const Text(
            'Pick an origin and destination to continue.',
            style: TextStyle(color: Colors.white60, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildNameStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
          onClear:
              _startDate != null ? () => setState(() => _startDate = null) : null,
        ),
        _DateRow(
          label: 'End',
          value: _endDate,
          onPick: () => _pickDate(isStart: false),
          onClear: _endDate != null ? () => setState(() => _endDate = null) : null,
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
      ],
    );
  }

  Widget _buildVibeStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionLabel('What should the companion talk about?'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: narrationThemeChips
              .map((meta) => FilterChip(
                    label: Text(meta.label),
                    selected: _narrationThemes.contains(meta.key),
                    onSelected: (_) => _toggleNarrationTheme(meta.key),
                  ))
              .toList(),
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
                onChanged: (v) => setState(() => _dailyDriveCapHours = v.round()),
              ),
            ),
            SizedBox(
              width: 60,
              child: Text('$_dailyDriveCapHours hr', textAlign: TextAlign.right),
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
          onSelectionChanged: (selected) => setState(() => _mode = selected.first),
        ),
      ],
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
                    candidate!.name.isEmpty ? candidate!.displayLine : candidate!.name,
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
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                ],
              )
            : const Text('Search for a place', style: TextStyle(color: Colors.white54)),
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
        style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
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
            TextButton(onPressed: onClear, child: const Text('Clear')),
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
