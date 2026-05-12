import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps `Supabase.instance` for the app's auth needs.
///
/// Why this layer exists: the rest of the app shouldn't import
/// `supabase_flutter` directly — that lets us mock auth in tests and swap
/// providers later without touching every screen. Keep this thin.
///
/// Sign-in is Google-only on day one (per the foundation plan). Apple +
/// email come later. The flow uses native Google Sign-In via the
/// `google_sign_in` plugin to get an ID + access token, then hands them to
/// Supabase via `signInWithIdToken` — this avoids the OAuth redirect dance
/// and keeps the user in-app.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// The currently signed-in user, or null if signed out.
  User? get currentUser => _client.auth.currentUser;

  /// The current session (carries the JWT used for backend calls), or null.
  Session? get currentSession => _client.auth.currentSession;

  /// Stream of auth state changes — power UI gates / redraws off this.
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  bool _googleSignInInitialized = false;

  /// Sign in with Google. Returns the resulting session, or throws.
  ///
  /// Requires:
  /// - Google Cloud OAuth client (Web + Android) created and linked in
  ///   Supabase Auth providers.
  /// - `--dart-define=GOOGLE_WEB_CLIENT_ID=...` passed at build time.
  /// - Android SHA-1 fingerprint registered with the Android OAuth client.
  Future<AuthResponse> signInWithGoogle() async {
    const webClientId =
        String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: '');
    if (webClientId.isEmpty) {
      throw StateError(
        'GOOGLE_WEB_CLIENT_ID is not set. Pass it via '
        '--dart-define=GOOGLE_WEB_CLIENT_ID=<your-web-client-id> at build/run.',
      );
    }

    if (!_googleSignInInitialized) {
      await GoogleSignIn.instance.initialize(serverClientId: webClientId);
      _googleSignInInitialized = true;
    }

    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google did not return an ID token.');
    }

    return _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      // Best-effort: Supabase sign-out is the source of truth. Logging
      // out of the Google plugin too is hygienic but not load-bearing.
      debugPrint('Google sign-out warning: $e');
    }
  }

  /// Bearer token to send on backend requests. Returns null when signed out.
  String? get accessToken => currentSession?.accessToken;

  /// Try to refresh the current Supabase session. Returns true on success.
  ///
  /// On failure (network blip, refresh token expired, anything thrown),
  /// signs the user out so the AuthGate routes them to the sign-in
  /// screen. Without this, the app would keep hitting 401s silently —
  /// worse UX than asking the user to re-auth.
  Future<bool> tryRefresh() async {
    try {
      final response = await _client.auth.refreshSession();
      return response.session != null;
    } catch (e) {
      debugPrint('Session refresh failed: $e. Signing out.');
      try {
        await signOut();
      } catch (_) {
        // signOut already best-effort; don't let cleanup throw.
      }
      return false;
    }
  }
}
