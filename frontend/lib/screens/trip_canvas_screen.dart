import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../models/trip.dart';
import '../utils/polyline.dart' as poly;

/// Slice C v1: the trip-planning canvas.
///
/// What ships in this slice:
///   - Full-screen Mapbox map (Flutter SDK, separate from the
///     native Navigation SDK used in MapActivity for live driving)
///   - Renders the trip's encoded polyline as a route line
///   - Origin + destination pins
///   - Camera fits the route bounds on initial load
///
/// What does NOT ship yet (per the trip-planning brief slice
/// breakdown):
///   - Four pin types (anchor / suggested / lodging / wing-it)
///   - Day-strip timeline at the top
///   - Natural-language textbox at the bottom
///   - Long-press route segment for wing-it
///
/// Those layer in over the next slices. This v1 establishes that
/// the visual canvas works at all, the polyline is correct, and
/// camera/pin rendering hangs together.
class TripCanvasScreen extends StatefulWidget {
  final Trip trip;
  const TripCanvasScreen({super.key, required this.trip});

  @override
  State<TripCanvasScreen> createState() => _TripCanvasScreenState();
}

class _TripCanvasScreenState extends State<TripCanvasScreen> {
  MapboxMap? _map;
  PolylineAnnotationManager? _lineManager;
  PointAnnotationManager? _pinManager;

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    return Scaffold(
      appBar: AppBar(
        title: Text(trip.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: trip.polyline == null || trip.polyline!.isEmpty
          ? _MissingPolylineHint(trip: trip)
          : MapWidget(
              key: const ValueKey('trip-canvas-map'),
              styleUri: MapboxStyles.OUTDOORS,
              // Camera will get re-fit to the polyline bounds after
              // the style loads; start near the origin so the first
              // frame isn't a default world view.
              cameraOptions: CameraOptions(
                center: Point(coordinates: Position(
                  trip.originLng, trip.originLat,
                )),
                zoom: 11.0,
              ),
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: (_) => _drawTrip(),
            ),
    );
  }

  void _onMapCreated(MapboxMap map) {
    _map = map;
  }

  Future<void> _drawTrip() async {
    final map = _map;
    final trip = widget.trip;
    if (map == null || trip.polyline == null) return;

    // Reset any previous annotations (hot-reload, screen revisit).
    _lineManager?.deleteAll();
    _pinManager?.deleteAll();

    _lineManager ??= await map.annotations.createPolylineAnnotationManager();
    _pinManager ??= await map.annotations.createPointAnnotationManager();

    final coords = poly.decodePolyline(trip.polyline!);
    if (coords.isEmpty) return;

    // Draw the route as a single polyline. Mapbox expects
    // (lng, lat) order for Position.
    await _lineManager!.create(
      PolylineAnnotationOptions(
        geometry: LineString(
          coordinates: coords.map((c) => Position(c[1], c[0])).toList(),
        ),
        lineColor: 0xFF4FC3F7, // sky/teal — matches narration markers
        lineWidth: 5.0,
        lineOpacity: 0.9,
      ),
    );

    // Origin + destination pins. Iconography is intentionally
    // minimal — slice D will add typed pins (anchor / lodging /
    // suggested / wing-it).
    await _pinManager!.createMulti([
      PointAnnotationOptions(
        geometry: Point(coordinates: Position(trip.originLng, trip.originLat)),
        textField: trip.originName,
        textOffset: [0.0, -1.6],
        textSize: 12.0,
        textColor: 0xFFFFFFFF,
        textHaloColor: 0xFF000000,
        textHaloWidth: 1.5,
        iconColor: 0xFF66BB6A, // green: origin
      ),
      PointAnnotationOptions(
        geometry: Point(coordinates: Position(
          trip.destinationLng, trip.destinationLat,
        )),
        textField: trip.destinationName,
        textOffset: [0.0, -1.6],
        textSize: 12.0,
        textColor: 0xFFFFFFFF,
        textHaloColor: 0xFF000000,
        textHaloWidth: 1.5,
        iconColor: 0xFFEF5350, // red: destination
      ),
    ]);

    // Fit camera to the bounds of the route. Compute min/max manually
    // (cheaper than rebuilding via a CoordinateBoundsZoom API call).
    var minLat = coords.first[0];
    var maxLat = coords.first[0];
    var minLng = coords.first[1];
    var maxLng = coords.first[1];
    for (final c in coords) {
      if (c[0] < minLat) minLat = c[0];
      if (c[0] > maxLat) maxLat = c[0];
      if (c[1] < minLng) minLng = c[1];
      if (c[1] > maxLng) maxLng = c[1];
    }
    final cameraForBounds = await map.cameraForCoordinateBounds(
      CoordinateBounds(
        southwest: Point(coordinates: Position(minLng, minLat)),
        northeast: Point(coordinates: Position(maxLng, maxLat)),
        infiniteBounds: false,
      ),
      MbxEdgeInsets(top: 80, left: 60, bottom: 80, right: 60),
      null,
      null,
      null,
      null,
    );
    await map.flyTo(
      cameraForBounds,
      MapAnimationOptions(duration: 900, startDelay: 0),
    );
  }
}

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
              'was wired up. Edit it (origin or destination) and the '
              'server will compute the polyline on save.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
