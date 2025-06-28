import 'package:flutter/material.dart';
import 'services/navigation_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RouteWhisper',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'RouteWhisper Navigation'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _navigationStatus = 'Ready to navigate';

  @override
  void initState() {
    super.initState();
  }

  void _showMap() async {
    await NavigationService.showMap();
    setState(() {
      _navigationStatus = 'Map opened in separate screen';
    });
  }

  void _startNavigation() async {
    setState(() {
      _navigationStatus = 'Starting navigation...';
    });

    String? error = await NavigationService.startNavigation(
      originLat: 37.7749,
      originLng: -122.4194,
      destLat: 34.0522,
      destLng: -118.2437,
    );

    if (error != null) {
      setState(() {
        _navigationStatus = error;
      });
    } else {
      setState(() {
        _navigationStatus = 'Navigation opened in map screen';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Navigation Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Icon(Icons.location_on, size: 80, color: Colors.blue),
                    const SizedBox(height: 20),
                    Text(
                      'RouteWhisper',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _navigationStatus,
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),

            // Control Buttons
            Column(
              children: [
                ElevatedButton.icon(
                  onPressed: _showMap,
                  icon: const Icon(Icons.map),
                  label: const Text('View Map'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(200, 50),
                  ),
                ),

                const SizedBox(height: 16),

                ElevatedButton.icon(
                  onPressed: _startNavigation,
                  icon: const Icon(Icons.navigation),
                  label: const Text('Start Navigation'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(200, 50),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),

            // Instructions
            Card(
              color: Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How to use:',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('• "View Map" - Opens the map in full screen'),
                    const Text(
                      '• "Start Navigation" - Begins turn-by-turn navigation',
                    ),
                    const Text('• Use device back button to return from map'),
                    const SizedBox(height: 8),
                    Text(
                      'Test Route: San Francisco → Los Angeles',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
