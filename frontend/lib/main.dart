import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/navigation_dashboard.dart';
import 'services/navigation_service.dart';
import 'widgets/auth_gate.dart';
import 'widgets/poi_dashboard.dart';

// Global navigator key for navigation from services
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Supabase config — passed via --dart-define so secrets stay out of source.
// Get these from your Supabase project's Settings → API page.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
    throw StateError(
      'Supabase config missing. Run with '
      '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
    );
  }
  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
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
        navigatorKey: navigatorKey,
        title: 'RouteWhisper',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        // Configure routes for different screens. Root is gated behind auth;
        // /poi-discovery is reachable directly because it's pushed from the
        // already-authenticated dashboard, not as a deep link.
        initialRoute: '/',
        routes: {
          '/': (context) => const AuthGate(signedIn: NavigationDashboard()),
          '/poi-discovery': (context) => const POIDashboard(),
        },
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
