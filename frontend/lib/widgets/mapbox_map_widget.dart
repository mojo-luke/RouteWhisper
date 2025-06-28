import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class MapboxMapWidget extends StatefulWidget {
  final Function(MapboxMapController)? onMapCreated;
  final Function()? onLocationEnabled;

  const MapboxMapWidget({Key? key, this.onMapCreated, this.onLocationEnabled})
    : super(key: key);

  @override
  State<MapboxMapWidget> createState() => _MapboxMapWidgetState();
}

class _MapboxMapWidgetState extends State<MapboxMapWidget> {
  MapboxMapController? controller;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: 'mapbox_map',
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
        },
      );
    }

    return Text('Maps only supported on Android currently');
  }

  void _onPlatformViewCreated(int id) {
    controller = MapboxMapController._(id);
    controller!._channel.setMethodCallHandler(_handleMethodCall);
    widget.onMapCreated?.call(controller!);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onMapReady':
        // Map is ready, we can interact with it
        print('Map is ready');
        break;
      case 'onLocationEnabled':
        widget.onLocationEnabled?.call();
        break;
    }
  }
}

class MapboxMapController {
  final MethodChannel _channel;

  MapboxMapController._(int id) : _channel = MethodChannel('mapbox_map_$id');

  Future<void> enableLocation() async {
    try {
      await _channel.invokeMethod('enableLocation');
    } on PlatformException catch (e) {
      print("Failed to enable location: ${e.message}");
    }
  }

  Future<void> moveCamera({
    required double lat,
    required double lng,
    double zoom = 12.0,
  }) async {
    try {
      await _channel.invokeMethod('moveCamera', {
        'lat': lat,
        'lng': lng,
        'zoom': zoom,
      });
    } on PlatformException catch (e) {
      print("Failed to move camera: ${e.message}");
    }
  }
}
