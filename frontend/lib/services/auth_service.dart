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

  /// Email/password sign-up. Depending on the Supabase project's "Confirm
  /// email" setting, the returned response may come back with no session
  /// (check `response.session == null`) — the user has to click the
  /// confirmation link emailed to them before [signInWithPassword] works.
  Future<AuthResponse> signUpWithPassword(String email, String password) {
    return _client.auth.signUp(email: email, password: password);
  }

  /// Email/password sign-in. Real, user-facing auth — not the testing
  /// helper below. Same AuthGate session path as Google sign-in.
  Future<AuthResponse> signInWithPassword(String email, String password) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Completes sign-up with the 6-digit code Supabase emailed after
  /// [signUpWithPassword]. We use the code (OTP) flow rather than the
  /// magic-link flow — this is a mobile-only app with no web frontend
  /// to catch the link's default `http://localhost:3000#access_token=...`
  /// redirect, and no deep-link URL scheme registered either. Requires
  /// the Supabase project's "Confirm signup" email template to include
  /// `{{ .Token }}` (it only has the link by default).
  Future<AuthResponse> verifySignupCode(String email, String code) {
    return _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.signup,
    );
  }

  /// Re-sends the signup confirmation code, in case the first one
  /// expired or the email got lost.
  Future<void> resendSignupCode(String email) {
    return _client.auth.resend(email: email, type: OtpType.signup);
  }

  /// Fixture credentials for on-device/manual testing only. Must match
  /// TEST_EMAIL/TEST_PASSWORD in backend/scripts/manage_test_user.py,
  /// which creates/deletes this user via Supabase's Admin API. Signing in
  /// with these still goes through a real Supabase password grant and a
  /// real AuthGate session — this isn't a UI bypass, just an alternate
  /// front door that only exists in debug builds (see [signInForTesting]).
  static const testFixtureEmail = 'routewhisper-test-fixture@example.com';
  static const testFixturePassword = 'RW-test-fixture-2026!Zq9';

  /// Signs in as the fixture test account created by
  /// backend/scripts/manage_test_user.py. Only ever called from a
  /// kDebugMode-gated button (see SignInScreen) — asserts here too so a
  /// stray release-mode call fails loudly instead of silently working.
  Future<AuthResponse> signInForTesting() async {
    assert(kDebugMode, 'signInForTesting must never run in release builds.');
    return signInWithPassword(testFixtureEmail, testFixturePassword);
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
