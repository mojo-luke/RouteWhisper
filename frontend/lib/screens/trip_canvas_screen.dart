import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/trip.dart';
import '../models/trip_pin.dart';
import '../services/trip_service.dart';
import '../utils/polyline.dart' as poly;
import '../widgets/trip_canvas_timeline.dart';

const _uuid = Uuid();

/// Trip canvas: 3-panel interactive map for pre-trip stop planning.
///
/// Panel layout (top → bottom):
///   [TripCanvasTimeline]  — 64dp strip showing origin → stops → destination
///   [MapWidget]           — interactive Mapbox map (expanded)
///   [_NLInputBar]         — "Tell me what to change" text input (Slice 2)
///
/// User interactions:
///   - Tap map → name-a-stop bottom sheet → amber anchor pin added
///   - × on anchor chip → remove pin (5-second undo SnackBar per UX rule #4)
///   - ✓ on suggested chip → promote to anchor
///   - × on suggested chip → dismiss (5-second undo SnackBar)
///   - NL bar → type instruction → LLM parses → canvas updates
class TripCanvasScreen extends StatefulWidget {
  final Trip trip;
  const TripCanvasScreen({super.key, required this.trip});

  @override
  State<TripCanvasScreen> createState() => _TripCanvasScreenState();
}

class _TripCanvasScreenState extends State<TripCanvasScreen> {
  late Trip _trip;
  late List<TripPin> _pins;

  MapboxMap? _map;
  PolylineAnnotationManager? _lineManager;
  PointAnnotationManager? _pinManager;

  bool _saving = false;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _pins = List<TripPin>.from(_trip.pins);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  // ── Map lifecycle ──────────────────────────────────────────────────

  void _onMapCreated(MapboxMap map) {
    _map = map;
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    await _drawRoute();
    await _redrawPins();
  }

  Future<void> _drawRoute() async {
    final map = _map;
    final polyline = _trip.polyline;
    if (map == null || polyline == null || polyline.isEmpty) return;

    _lineManager ??= await map.annotations.createPolylineAnnotationManager();
    _lineManager!.deleteAll();

    final coords = poly.decodePolyline(polyline);
    if (coords.isEmpty) return;

    await _lineManager!.create(
      PolylineAnnotationOptions(
        geometry: LineString(
          coordinates: coords.map((c) => Position(c[1], c[0])).toList(),
        ),
        lineColor: 0xFF4FC3F7,
        lineWidth: 5.0,
        lineOpacity: 0.9,
      ),
    );

    // Fit camera to route bounds.
    var minLat = coords.first[0], maxLat = coords.first[0];
    var minLng = coords.first[1], maxLng = coords.first[1];
    for (final c in coords) {
      if (c[0] < minLat) minLat = c[0];
      if (c[0] > maxLat) maxLat = c[0];
      if (c[1] < minLng) minLng = c[1];
      if (c[1] > maxLng) maxLng = c[1];
    }
    final camera = await map.cameraForCoordinateBounds(
      CoordinateBounds(
        southwest: Point(coordinates: Position(minLng, minLat)),
        northeast: Point(coordinates: Position(maxLng, maxLat)),
        infiniteBounds: false,
      ),
      MbxEdgeInsets(top: 80, left: 60, bottom: 100, right: 60),
      null, null, null, null,
    );
    await map.flyTo(camera, MapAnimationOptions(duration: 900, startDelay: 0));
  }

  /// Redraws all pins: origin (green) + destination (red) + anchors (amber)
  /// + suggested (blue-grey).
  /// Deletes and recreates every time to keep rendering consistent with state.
  Future<void> _redrawPins() async {
    final map = _map;
    if (map == null) return;

    _pinManager ??= await map.annotations.createPointAnnotationManager();
    await _pinManager!.deleteAll();

    final options = <PointAnnotationOptions>[
      PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(_trip.originLng, _trip.originLat),
        ),
        textField: _trip.originName,
        textOffset: [0.0, -1.6],
        textSize: 12.0,
        textColor: 0xFFFFFFFF,
        textHaloColor: 0xFF000000,
        textHaloWidth: 1.5,
        iconColor: 0xFF66BB6A,
      ),
      PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(_trip.destinationLng, _trip.destinationLat),
        ),
        textField: _trip.destinationName,
        textOffset: [0.0, -1.6],
        textSize: 12.0,
        textColor: 0xFFFFFFFF,
        textHaloColor: 0xFF000000,
        textHaloWidth: 1.5,
        iconColor: 0xFFEF5350,
      ),
      for (final pin in _pins.where((p) => p.type == 'anchor'))
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(pin.lng, pin.lat)),
          textField: pin.name,
          textOffset: [0.0, -1.6],
          textSize: 12.0,
          textColor: 0xFFFFFFFF,
          textHaloColor: 0xFF000000,
          textHaloWidth: 1.5,
          iconColor: 0xFFFFA726, // amber
        ),
      for (final pin in _pins.where((p) => p.type == 'suggested'))
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(pin.lng, pin.lat)),
          textField: pin.name,
          textOffset: [0.0, -1.6],
          textSize: 12.0,
          textColor: 0xFFFFFFFF,
          textHaloColor: 0xFF000000,
          textHaloWidth: 1.5,
          iconColor: 0xFF78909C, // blue-grey
        ),
    ];

    await _pinManager!.createMulti(options);
  }

  // ── Map tap → add anchor pin ───────────────────────────────────────

  void _onMapTap(MapContentGestureContext context) {
    final lat = context.point.coordinates.lat.toDouble();
    final lng = context.point.coordinates.lng.toDouble();
    _showAddPinSheet(lat, lng);
  }

  Future<void> _showAddPinSheet(double lat, double lng) async {
    final stopNumber = _pins.where((p) => p.type == 'anchor').length + 1;
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddPinSheet(initialText: 'Stop $stopNumber'),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;

    final pin = TripPin(
      type: 'anchor',
      id: _uuid.v4(),
      name: name.trim(),
      lat: lat,
      lng: lng,
    );
    setState(() => _pins = [..._pins, pin]);
    await _redrawPins();
    _scheduleSave();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${pin.name} added'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () => _removePin(pin, showSnackBar: false),
          ),
        ),
      );
    }
  }

  // ── Remove pin ─────────────────────────────────────────────────────

  void _removePin(TripPin pin, {bool showSnackBar = true}) {
    final previous = List<TripPin>.from(_pins);
    setState(() => _pins = _pins.where((p) => p.id != pin.id).toList());
    _redrawPins();
    _scheduleSave();

    if (showSnackBar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${pin.name} removed'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () {
              setState(() => _pins = previous);
              _redrawPins();
              _scheduleSave();
            },
          ),
        ),
      );
    }
  }

  // ── Promote suggested pin to anchor ───────────────────────────────

  void _promotePin(TripPin pin) {
    final promoted = pin.copyWith(type: 'anchor');
    setState(() {
      _pins = [
        for (final p in _pins) if (p.id == pin.id) promoted else p,
      ];
    });
    _redrawPins();
    _scheduleSave();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${pin.name} added as a stop'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () {
              setState(() {
                _pins = [
                  for (final p in _pins) if (p.id == pin.id) pin else p,
                ];
              });
              _redrawPins();
              _scheduleSave();
            },
          ),
        ),
      );
    }
  }

  // ── NL canvas edit ─────────────────────────────────────────────────

  Future<void> _onNLSubmit(String text) async {
    final tripId = _trip.id;
    if (tripId == null) return;

    final result = await TripService.nlEdit(tripId, text);
    if (!mounted) return;

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final newPins = result.pins.map((raw) => TripPin.fromJson(raw)).toList();
    setState(() => _pins = newPins);
    await _redrawPins();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ── Save / navigation ─────────────────────────────────────────────

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    final updated = _trip.copyWith(pins: _pins);
    final saved = await TripService.update(updated);
    _saving = false;
    if (saved != null) {
      setState(() => _trip = saved);
    }
  }

  Future<void> _goBack() async {
    _saveDebounce?.cancel();
    // Flush any unsaved pin changes before leaving.
    final toReturn = _trip.copyWith(pins: _pins);
    if (_pins != _trip.pins) {
      await TripService.update(toReturn);
    }
    if (mounted) Navigator.of(context).pop(toReturn);
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, __) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _goBack),
          title: Text(
            _trip.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        ),
        body: _trip.polyline == null || _trip.polyline!.isEmpty
            ? _MissingPolylineHint(trip: _trip)
            : Column(
                children: [
                  TripCanvasTimeline(
                    trip: _trip,
                    pins: _pins,
                    onRemovePin: _removePin,
                    onPromotePin: _promotePin,
                  ),
                  Expanded(
                    child: MapWidget(
                      key: const ValueKey('trip-canvas-map'),
                      styleUri: MapboxStyles.OUTDOORS,
                      cameraOptions: CameraOptions(
                        center: Point(
                          coordinates: Position(
                            _trip.originLng,
                            _trip.originLat,
                          ),
                        ),
                        zoom: 11.0,
                      ),
                      onMapCreated: _onMapCreated,
                      onStyleLoadedListener: _onStyleLoaded,
                      onTapListener: _onMapTap,
                    ),
                  ),
                  _NLInputBar(onSubmit: _onNLSubmit),
                ],
              ),
      ),
    );
  }
}

// ── Add-pin bottom sheet ─────────────────────────────────────────────

class _AddPinSheet extends StatefulWidget {
  final String initialText;
  const _AddPinSheet({required this.initialText});

  @override
  State<_AddPinSheet> createState() => _AddPinSheetState();
}

class _AddPinSheetState extends State<_AddPinSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Name this stop',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g. Coffee in Truckee',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
          const SizedBox(height: 12),
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
                  onPressed: () => Navigator.of(context).pop(_ctrl.text),
                  child: const Text('Add stop'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── NL input bar ──────────────────────────────────────────────────────
//
// Collapsed (48dp): shows a dim hint row, tap to open keyboard.
// Expanded: text field + send button. Submit calls [onSubmit] and
// collapses the bar. Shows a spinner while the request is in flight.

class _NLInputBar extends StatefulWidget {
  final Future<void> Function(String text) onSubmit;

  const _NLInputBar({required this.onSubmit});

  @override
  State<_NLInputBar> createState() => _NLInputBarState();
}

class _NLInputBarState extends State<_NLInputBar> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _expanded = false;
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _expand() {
    setState(() => _expanded = true);
    _focusNode.requestFocus();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _loading = true);
    _focusNode.unfocus();
    try {
      await widget.onSubmit(text);
    } finally {
      if (mounted) {
        _ctrl.clear();
        setState(() {
          _loading = false;
          _expanded = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      color: Colors.black.withOpacity(0.85),
      padding: EdgeInsets.fromLTRB(16, 8, 8, 8 + bottom),
      child: _expanded
          ? Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focusNode,
                    enabled: !_loading,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'e.g. "Add a coffee stop in Truckee"',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: _loading
                      ? const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white54,
                            ),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send, size: 18),
                          color: Colors.white70,
                          padding: EdgeInsets.zero,
                          onPressed: _submit,
                        ),
                ),
              ],
            )
          : GestureDetector(
              onTap: _expand,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 32,
                child: Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline,
                      size: 18,
                      color: Colors.white38,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Tell me what to change…',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ── Missing-polyline fallback ────────────────────────────────────────

class _MissingPolylineHint extends StatelessWidget {
  final Trip trip;
  const _MissingPolylineHint({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map_outlined,
              size: 56,
              color: Colors.white.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'No route geometry yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'This trip from ${trip.originName} to '
              '${trip.destinationName} was created before the canvas '
              'was wired up. Edit and re-save it to generate the route.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
