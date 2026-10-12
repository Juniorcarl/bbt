import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';

enum _Mode { signIn, signUp, forgot, verifySignup, resetCode }

/// Sign in, sign up, email confirmation code and password reset.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _info;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _go(_Mode m) => setState(() {
        _mode = m;
        _error = null;
        _info = null;
        _code.clear();
        if (m == _Mode.resetCode) _password.clear();
      });

  Future<void> _run(Future<void> Function() action) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = _friendly(e.message));
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't reach the server. Check your internet connection.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _emailText => _email.text.trim().toLowerCase();

  Future<void> _signIn() => _run(() async {
        await _auth.signInWithPassword(email: _emailText, password: _password.text);
        // AuthGate takes over when the session arrives.
      });

  Future<void> _signUp() => _run(() async {
        final res = await _auth.signUp(
          email: _emailText,
          password: _password.text,
          data: {'full_name': _name.text.trim()},
        );
        if (res.session == null) {
          // Email confirmation is switched on in Supabase: ask for the code.
          _go(_Mode.verifySignup);
          setState(() => _info = 'We sent a 6-digit code to $_emailText. Enter it to finish signing up.');
        }
      });

  Future<void> _verifySignup() => _run(() async {
        await _auth.verifyOTP(type: OtpType.signup, email: _emailText, token: _code.text.trim());
      });

  Future<void> _sendReset() => _run(() async {
        await _auth.resetPasswordForEmail(_emailText);
        _go(_Mode.resetCode);
        setState(() => _info = 'If $_emailText has an account, we sent it a 6-digit code.');
      });

  Future<void> _resetWithCode() => _run(() async {
        await _auth.verifyOTP(type: OtpType.recovery, email: _emailText, token: _code.text.trim());
        await _auth.updateUser(UserAttributes(password: _password.text));
        // Now signed in with the new password; AuthGate takes over.
      });

  String _friendly(String m) {
    final l = m.toLowerCase();
    if (l.contains('invalid login')) return 'Wrong email or password.';
    if (l.contains('already registered') || l.contains('already exists')) {
      return 'An account with this email already exists. Sign in instead.';
    }
    if (l.contains('email not confirmed')) return 'Please confirm your email first.';
    if (l.contains('expired') || (l.contains('invalid') && l.contains('otp'))) return 'That code is wrong or has expired.';
    if (l.contains('rate limit')) return 'Too many attempts. Wait a minute and try again.';
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = switch (_mode) {
      _Mode.signIn => ('Welcome back', 'Sign in to see where your money goes.'),
      _Mode.signUp => ('Create your account', 'Upload a bank statement and see your spending in seconds.'),
      _Mode.forgot => ('Reset password', "Enter your email and we'll send you a code."),
      _Mode.verifySignup => ('Confirm your email', ''),
      _Mode.resetCode => ('Choose a new password', ''),
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('bbt.',
                        style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    const SizedBox(height: 28),
                    Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(subtitle, style: const TextStyle(color: AppColors.muted)),
                    ],
                    const SizedBox(height: 24),
                    if (_info != null) _Banner(_info!, error: false),
                    if (_error != null) _Banner(_error!, error: true),
                    ..._fields(),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _primaryAction,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : Text(_primaryLabel),
                    ),
                    const SizedBox(height: 12),
                    ..._links(),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _primaryLabel => switch (_mode) {
        _Mode.signIn => 'Sign in',
        _Mode.signUp => 'Create account',
        _Mode.forgot => 'Send code',
        _Mode.verifySignup => 'Confirm',
        _Mode.resetCode => 'Save new password',
      };

  VoidCallback get _primaryAction => switch (_mode) {
        _Mode.signIn => _signIn,
        _Mode.signUp => _signUp,
        _Mode.forgot => _sendReset,
        _Mode.verifySignup => _verifySignup,
        _Mode.resetCode => _resetWithCode,
      };

  List<Widget> _fields() {
    final email = TextFormField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
      validator: (v) {
        final t = (v ?? '').trim();
        if (t.isEmpty) return 'Enter your email';
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) return 'That email doesn\'t look right';
        return null;
      },
    );
    final password = TextFormField(
      controller: _password,
      obscureText: !_showPassword,
      autofillHints: [_mode == _Mode.signIn ? AutofillHints.password : AutofillHints.newPassword],
      decoration: InputDecoration(
        labelText: _mode == _Mode.resetCode ? 'New password' : 'Password',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: () => setState(() => _showPassword = !_showPassword),
        ),
      ),
      onFieldSubmitted: (_) => _primaryAction(),
      validator: (v) {
        if ((v ?? '').isEmpty) return 'Enter a password';
        if (_mode != _Mode.signIn && v!.length < 8) return 'Use at least 8 characters';
        return null;
      },
    );
    final code = TextFormField(
      controller: _code,
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      maxLength: 8,
      decoration: const InputDecoration(labelText: 'Code from the email', prefixIcon: Icon(Icons.pin_outlined)),
      validator: (v) => (v ?? '').trim().length < 6 ? 'Enter the code from the email' : null,
    );
    const gap = SizedBox(height: 14);

    return switch (_mode) {
      _Mode.signIn => [email, gap, password],
      _Mode.signUp => [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
          ),
          gap,
          email,
          gap,
          password,
        ],
      _Mode.forgot => [email],
      _Mode.verifySignup => [code],
      _Mode.resetCode => [code, gap, password],
    };
  }

  List<Widget> _links() => switch (_mode) {
        _Mode.signIn => [
            TextButton(onPressed: () => _go(_Mode.forgot), child: const Text('Forgot password?')),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('New to bbt?'),
              TextButton(onPressed: () => _go(_Mode.signUp), child: const Text('Create an account')),
            ]),
          ],
        _Mode.signUp => [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Already have an account?'),
              TextButton(onPressed: () => _go(_Mode.signIn), child: const Text('Sign in')),
            ]),
          ],
        _ => [TextButton(onPressed: () => _go(_Mode.signIn), child: const Text('Back to sign in'))],
      };
}

class _Banner extends StatelessWidget {
  final String text;
  final bool error;
  const _Banner(this.text, {required this.error});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: error ? const Color(0xFFFDECEA) : const Color(0xFFEAF4FC),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(error ? Icons.error_outline : Icons.info_outline,
              color: error ? const Color(0xFFD0573F) : AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: AppColors.ink))),
        ]),
      );
}
