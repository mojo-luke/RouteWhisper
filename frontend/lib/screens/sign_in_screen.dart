import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import '../services/auth_service.dart';

/// Sign-in surface: Google, plus a plain email/password form (sign in or
/// create an account) for anyone who'd rather not go through Google OAuth.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();

  bool _busy = false;
  bool _isSignUp = false;
  String? _error;
  String? _info;

  // Non-null once sign-up succeeds but needs email confirmation — swaps
  // the form for a "enter the code we emailed you" step. We use a
  // 6-digit code rather than the confirmation link: this is a
  // mobile-only app with no web frontend to catch the link's default
  // `http://localhost:3000#access_token=...` redirect, and no deep-link
  // URL scheme registered either.
  String? _pendingVerificationEmail;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await AuthService.instance.signInWithGoogle();
      // Auth-gate widget on top of MaterialApp listens to authStateChanges
      // and swaps to the dashboard automatically — no manual navigation.
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitEmailPassword() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter both an email and a password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_isSignUp) {
        final response =
            await AuthService.instance.signUpWithPassword(email, password);
        if (!mounted) return;
        if (response.session == null) {
          // Project has "Confirm email" on — no session until they enter
          // the code Supabase just emailed them.
          setState(() => _pendingVerificationEmail = email);
        }
        // If a session did come back, AuthGate picks it up automatically.
      } else {
        await AuthService.instance.signInWithPassword(email, password);
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitVerificationCode() async {
    final email = _pendingVerificationEmail;
    if (email == null) return;
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code from your email.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await AuthService.instance.verifySignupCode(email, code);
      // Success flips the auth state; AuthGate swaps to the dashboard.
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Verification failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendVerificationCode() async {
    final email = _pendingVerificationEmail;
    if (email == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await AuthService.instance.resendSignupCode(email);
      if (!mounted) return;
      setState(() => _info = 'Sent a new code to $email.');
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not resend code: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInForTesting() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await AuthService.instance.signInForTesting();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Test sign-in failed: ${e.message}. Run '
          'backend/scripts/manage_test_user.py create first.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Test sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'RouteWhisper',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _pendingVerificationEmail == null
                      ? 'Sign in to plan smarter trips.'
                      : 'Enter the code we sent to $_pendingVerificationEmail.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 48),
                if (_pendingVerificationEmail != null)
                  ..._buildVerificationStep()
                else
                  ..._buildSignInForm(),
                if (_info != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _info!,
                    style: const TextStyle(color: Colors.lightBlueAccent),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ],
                // Debug-only alternate front door for manual/scripted
                // on-device testing, so verifying a flow doesn't require a
                // real Google account. Signs into the fixture user created
                // by backend/scripts/manage_test_user.py via a normal
                // Supabase password grant — same AuthGate session path as
                // Google sign-in, not a bypass. Compiled out of release
                // builds entirely.
                if (kDebugMode && _pendingVerificationEmail == null) ...[
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: _busy ? null : _signInForTesting,
                    child: const Text('Sign in with test account (debug)'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSignInForm() {
    return [
      FilledButton.icon(
        onPressed: _busy ? null : _signInWithGoogle,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.login),
        label: const Text('Continue with Google'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
        ),
      ),
      const SizedBox(height: 24),
      const Row(
        children: [
          Expanded(child: Divider(color: Colors.white24)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('or', style: TextStyle(color: Colors.white54)),
          ),
          Expanded(child: Divider(color: Colors.white24)),
        ],
      ),
      const SizedBox(height: 24),
      TextField(
        controller: _emailController,
        enabled: !_busy,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Email',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _passwordController,
        enabled: !_busy,
        obscureText: true,
        onSubmitted: (_) => _submitEmailPassword(),
        decoration: const InputDecoration(
          labelText: 'Password',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : _submitEmailPassword,
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
        ),
        child: Text(_isSignUp ? 'Create account' : 'Sign in'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _isSignUp = !_isSignUp;
                  _error = null;
                  _info = null;
                }),
        child: Text(
          _isSignUp
              ? 'Already have an account? Sign in'
              : "Don't have an account? Create one",
        ),
      ),
    ];
  }

  List<Widget> _buildVerificationStep() {
    return [
      TextField(
        controller: _codeController,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, letterSpacing: 8),
        onSubmitted: (_) => _submitVerificationCode(),
        decoration: const InputDecoration(
          labelText: 'Verification code',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : _submitVerificationCode,
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
        ),
        child: const Text('Verify'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _busy ? null : _resendVerificationCode,
        child: const Text("Didn't get it? Resend code"),
      ),
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _pendingVerificationEmail = null;
                  _codeController.clear();
                  _error = null;
                  _info = null;
                }),
        child: const Text('Back to sign in'),
      ),
    ];
  }
}
