import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/security.dart';
import '../theme/app_theme.dart';

/// Covers the whole app (every screen and dialog) with a lock screen when it
/// opens signed in, and again when it comes back after more than
/// [Security.lockAfter] in the background. The app underneath keeps its
/// state (an upload in progress carries on). Used in MaterialApp.builder.
class AppLock extends StatefulWidget {
  final Widget child;
  const AppLock({super.key, required this.child});

  @override
  State<AppLock> createState() => _AppLockState();
}

class _AppLockState extends State<AppLock> with WidgetsBindingObserver {
  late bool _locked = security.lockEnabled && _signedIn;

  static bool get _signedIn => backendConfigured && Supabase.instance.client.auth.currentSession != null;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The fingerprint / PIN prompt itself pauses the app; ignore that.
    if (security.authenticating) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      security.markActive();
      final away = left == null ? Duration.zero : DateTime.now().difference(left);
      if (!_locked && security.lockEnabled && _signedIn && away >= Security.lockAfter) {
        setState(() => _locked = true);
        _unlock();
      }
    }
  }

  Future<void> _unlock() async {
    if (await security.unlock() && mounted) setState(() => _locked = false);
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
    if (mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        // Offstage keeps the app's state but doesn't draw it behind the lock.
        Offstage(offstage: _locked, child: TickerMode(enabled: !_locked, child: widget.child)),
        if (_locked) Positioned.fill(child: _LockScreen(onUnlock: _unlock, onSignOut: _signOut)),
      ]);
}

class _LockScreen extends StatelessWidget {
  final VoidCallback onUnlock;
  final VoidCallback onSignOut;
  const _LockScreen({required this.onUnlock, required this.onSignOut});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(children: [
              const Spacer(),
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
                child: const Icon(Icons.lock_rounded, color: Colors.white, size: 38),
              ),
              const SizedBox(height: 20),
              const Text('bbt is locked',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 6),
              const Text('Use your fingerprint, face or phone PIN to continue.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
              const Spacer(),
              FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Unlock'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: onSignOut,
                child: const Text('Sign out instead'),
              ),
            ]),
          ),
        ),
      );
}
