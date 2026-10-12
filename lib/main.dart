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

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;
  static const _pages = [HomeScreen(), DashboardScreen(), BudgetScreen(), ProfileScreen()];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _i, children: _pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _i,
          onDestinationSelected: (i) => setState(() => _i = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Dashboard'),
            NavigationDestination(icon: Icon(Icons.track_changes_outlined), selectedIcon: Icon(Icons.track_changes), label: 'Budget'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ],
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
