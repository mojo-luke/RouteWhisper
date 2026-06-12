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
///   [_NLPlaceholder]      — 48dp "Tell me what to change" bar (Slice 2)
///
/// User interactions in Slice 1:
///   - Tap map → name-a-stop bottom sheet → amber anchor pin added
///   - × on timeline chip → remove pin (5-second undo SnackBar per UX rule #4)
///   - Pins auto-saved to backend via PUT /trips/{id}
///   - Pops updated Trip on back-nav so TripDetailScreen stays in sync
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

  /// Redraws all pins: origin (green) + destination (red) + anchors (amber).
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
          geometry: Point(
            coordinates: Position(pin.lng, pin.lat),
          ),
          textField: pin.name,
          textOffset: [0.0, -1.6],
          textSize: 12.0,
          textColor: 0xFFFFFFFF,
          textHaloColor: 0xFF000000,
          textHaloWidth: 1.5,
          iconColor: 0xFFFFA726, // amber
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
    final ctrl = TextEditingController(text: 'Stop $stopNumber');
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddPinSheet(ctrl: ctrl),
    );
    ctrl.dispose();
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
                  const _NLPlaceholder(),
                ],
              ),
      ),
    );
  }
}

// ── Add-pin bottom sheet ─────────────────────────────────────────────

class _AddPinSheet extends StatelessWidget {
  final TextEditingController ctrl;
  const _AddPinSheet({required this.ctrl});

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
            controller: ctrl,
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
                  onPressed: () => Navigator.of(context).pop(ctrl.text),
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

// ── NL placeholder (wired in Slice 2) ───────────────────────────────

class _NLPlaceholder extends StatelessWidget {
  const _NLPlaceholder();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Natural-language editing coming soon'),
          duration: Duration(seconds: 2),
        ),
      ),
      child: Container(
        height: 48,
        color: Colors.black.withOpacity(0.75),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.white38),
            const SizedBox(width: 10),
            Text(
              'Tell me what to change…',
              style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 14),
            ),
          ],
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
