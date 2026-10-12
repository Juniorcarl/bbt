import 'package:flutter/material.dart';
import 'screens/budget_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'theme/app_theme.dart';

void main() => runApp(const BbtApp());

class BbtApp extends StatelessWidget {
  const BbtApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'bbt',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Shell(),
      );
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
