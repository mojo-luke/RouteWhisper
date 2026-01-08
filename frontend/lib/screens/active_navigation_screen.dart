import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ActiveNavigationScreen - Launches native Android navigation
///
/// This screen immediately launches the native Mapbox Navigation SDK
/// which provides full-featured turn-by-turn navigation including:
/// - GPS signal enhancement with dead reckoning
/// - Automatic rerouting with traffic/incident avoidance
/// - Voice guidance
/// - Route line rendering
/// - Navigation camera controls
///
/// The native navigation runs in a separate Android Activity and returns
/// to this Flutter screen when navigation is complete or cancelled.
class ActiveNavigationScreen extends StatefulWidget {
  final double originLat;
  final double originLng;
  final double destLat;
  final double destLng;

  const ActiveNavigationScreen({
    Key? key,
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
  }) : super(key: key);

  @override
  State<ActiveNavigationScreen> createState() => _ActiveNavigationScreenState();
}

class _ActiveNavigationScreenState extends State<ActiveNavigationScreen> {
  static const platform = MethodChannel('routewhisper.com/navigation');

  String _status = 'Starting navigation...';
  bool _isLaunching = true;

  @override
  void initState() {
    super.initState();
    _launchNativeNavigation();
  }

  Future<void> _launchNativeNavigation() async {
    try {
      // Launch native navigation activity
      await platform.invokeMethod('startNavigation', {
        'originLat': widget.originLat,
        'originLng': widget.originLng,
        'destLat': widget.destLat,
        'destLng': widget.destLng,
      });

      setState(() {
        _status = 'Navigation launched';
        _isLaunching = false;
      });

      // Pop back to previous screen after native navigation is launched
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _status = 'Failed to launch navigation: $e';
        _isLaunching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RouteWhisper Navigation'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLaunching)
              const CircularProgressIndicator()
            else
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
            const SizedBox(height: 24),
            Text(
              _status,
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            if (!_isLaunching) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
