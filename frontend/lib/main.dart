import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/navigation_dashboard.dart';
import 'services/in_nav_surface_pusher.dart';
import 'services/navigation_service.dart';
import 'widgets/auth_gate.dart';
import 'widgets/poi_dashboard.dart';
import 'widgets/recommendation_overlay.dart';

// Global navigator key for navigation from services
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Supabase config — passed via --dart-define so secrets stay out of source.
// Get these from your Supabase project's Settings → API page.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// Mapbox pk. token for the Flutter-side MapWidget — also passed via
// --dart-define (see scripts/run.sh + .env.local). The native Navigation
// SDK reads its own copy from the gitignored
// android/app/src/main/res/values/mapbox_access_token.xml.
const _mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
    throw StateError(
      'Supabase config missing. Run with '
      '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
    );
  }
  if (_mapboxAccessToken.isEmpty) {
    throw StateError(
      'Mapbox token missing. Run with '
      '--dart-define=MAPBOX_ACCESS_TOKEN=pk... (or use scripts/run.sh).',
    );
  }
  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  // Initialize the Flutter-side Mapbox SDK for the trip-planning
  // canvas. Must run before any MapWidget is built. Native nav uses
  // its own SDK with the same token via an Android resource, so this
  // call doesn't affect anything in MapActivity.
  MapboxOptions.setAccessToken(_mapboxAccessToken);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialize navigation service (sets up controllers)
    NavigationService.initialize();
    // Mirror Flutter-side budget + recommendation state down to native.
    InNavSurfacePusher().attach();

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

        // Recommendation service polls during nav and exposes the next
        // suggestion to surface. Singleton on NavigationService so the
        // controller and any non-widget code can reach it.
        ChangeNotifierProvider.value(
          value: NavigationService.recommendations,
        ),

        // NarrationService — needed by MonologueCard and NarrationCard
        // on the dashboard.
        ChangeNotifierProvider.value(
          value: NavigationService.narration,
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
        // Wrap every route in an overlay that pushes a transparent
        // bottom-aligned recommendation card whenever a suggestion appears.
        builder: (context, child) => RecommendationOverlay(child: child),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
