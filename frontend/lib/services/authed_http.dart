import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// Wraps an HTTP request closure with one 401-refresh-retry.
///
/// Why this exists: Supabase access tokens expire (~1 hour) and the
/// supabase_flutter auto-refresh can silently fail (network blip, app
/// backgrounded too long). Without this helper, every authed call hits
/// the backend with `Authorization: Bearer <stale>` → 401 → the service
/// returns null → the user sees "Failed to save" with no actionable
/// next step.
///
/// Flow:
///   1. Run the request closure.
///   2. If status != 401, return the response.
///   3. Try [AuthService.tryRefresh]. On failure, the AuthService has
///      already signed the user out so AuthGate routes to sign-in.
///   4. On refresh success, re-run the closure (which rebuilds the
///      Authorization header with the new token) and return that.
///
/// The closure is re-invocable on purpose — callers must build their
/// headers freshly inside it so the retry picks up the rotated token.
class AuthedHttp {
  /// Send [request] and retry once on 401 after attempting a session
  /// refresh. Returns the final response (which may still be a 401 if
  /// refresh also failed).
  static Future<http.Response> send(
    Future<http.Response> Function() request,
  ) async {
    final response = await request();
    if (response.statusCode != 401) return response;
    final refreshed = await AuthService.instance.tryRefresh();
    if (!refreshed) return response;
    return request();
  }
}
