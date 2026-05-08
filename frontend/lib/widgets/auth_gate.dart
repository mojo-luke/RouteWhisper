import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/sign_in_screen.dart';

/// Auth gate that swaps between [signedIn] and a sign-in screen based on
/// Supabase auth state. Place above the rest of the app so any sign-out
/// (token refresh failure, manual sign-out) routes back to sign-in
/// without each screen having to handle it.
class AuthGate extends StatelessWidget {
  final Widget signedIn;

  const AuthGate({super.key, required this.signedIn});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // While the stream warms up, fall back to the cached session so we
        // don't flash the sign-in screen on app launch for already-signed-in
        // users.
        final session = snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;
        if (session == null) {
          return const SignInScreen();
        }
        return signedIn;
      },
    );
  }
}
