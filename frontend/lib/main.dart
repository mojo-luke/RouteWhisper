import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/navigation_dashboard.dart';
import 'services/navigation_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialize navigation service (sets up controllers)
    NavigationService.initialize();

    return MultiProvider(
      providers: [
        // Provide WaypointManager to entire app
        ChangeNotifierProvider.value(
          value: NavigationService.waypointManager,
        ),

        // Provide NavigationController to entire app
        ChangeNotifierProvider.value(
          value: NavigationService.controller,
        ),
      ],
      child: MaterialApp(
        title: 'RouteWhisper',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const NavigationDashboard(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
