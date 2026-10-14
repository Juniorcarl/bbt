import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/spending_store.dart';
import 'screens/auth_screen.dart';
import 'screens/budget_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'services/backend.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (backendConfigured) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
    store.backend = Backend();
  }
  runApp(const BbtApp());
}

class BbtApp extends StatelessWidget {
  const BbtApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'bbt',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: backendConfigured ? const AuthGate() : const _NotConfigured(),
      );
}

/// Shows the sign-in screen or the app, depending on whether someone is signed in.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _sub;
  Session? _session;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    final auth = Supabase.instance.client.auth;
    _session = auth.currentSession;
    _onSession(_session, AuthChangeEvent.initialSession);
    _sub = auth.onAuthStateChange.listen((s) {
      setState(() => _session = s.session);
      _onSession(s.session, s.event);
    });
  }

  void _onSession(Session? session, AuthChangeEvent event) {
    final uid = session?.user.id;
    if (uid == null) {
      if (_loadedFor != null) store.clear();
      _loadedFor = null;
      return;
    }
    if (uid != _loadedFor) {
      _loadedFor = uid;
      store.loadForUser();
      if (event == AuthChangeEvent.signedIn) Backend().log('signed_in');
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _session == null ? const AuthScreen() : const Shell();
}

class Shell extends StatelessWidget {
  const Shell({super.key});

  static const _pages = [HomeScreen(), DashboardScreen(), BudgetScreen(), ProfileScreen()];
  static const _icons = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Dashboard'),
    (Icons.track_changes_outlined, Icons.track_changes_rounded, 'Budget'),
    (Icons.person_outline, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: appTab,
        builder: (context, i, _) => Scaffold(
          extendBody: true,
          body: IndexedStack(index: i, children: _pages),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                for (var t = 0; t < _icons.length; t++)
                  Semantics(
                    label: _icons[t].$3,
                    selected: t == i,
                    button: true,
                    child: InkResponse(
                      onTap: () => appTab.value = t,
                      radius: 28,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: t == i ? AppColors.ink : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(t == i ? _icons[t].$2 : _icons[t].$1,
                            color: t == i ? Colors.white : AppColors.muted),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
}

/// Shown only if lib/config.dart hasn't been filled in.
class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'bbt is not connected to its database yet.\n\n'
                'Add your Supabase project URL and publishable key in lib/config.dart, then rebuild.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: AppColors.ink),
              ),
            ),
          ),
        ),
      );
}
