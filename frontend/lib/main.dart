import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'screens/analytics_screen.dart';
import 'screens/attack_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sign_screen.dart';
import 'screens/threat_log_screen.dart';
import 'screens/verify_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/quantum_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  runApp(const QuantumShieldApp());
}

class QuantumShieldApp extends StatefulWidget {
  const QuantumShieldApp({super.key});

  @override
  State<QuantumShieldApp> createState() => _QuantumShieldAppState();
}

class _QuantumShieldAppState extends State<QuantumShieldApp> {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    _state.refreshHealth();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: _state,
      child: MaterialApp(
        title: 'Quantum Shield',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const HomeShell(),
      ),
    );
  }
}

/// Responsive shell: navigation rail on wide screens, bottom bar on phones.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = <({IconData icon, String label})>[
    (icon: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.draw, label: 'Sign'),
    (icon: Icons.verified_user, label: 'Verify'),
    (icon: Icons.bug_report, label: 'Attacks'),
    (icon: Icons.list_alt, label: 'Threat log'),
    (icon: Icons.insights, label: 'Analytics'),
    (icon: Icons.settings, label: 'Settings'),
  ];

  Widget _screen(int index) => switch (index) {
        0 => DashboardScreen(onNavigate: (i) => setState(() => _index = i)),
        1 => const SignScreen(),
        2 => const VerifyScreen(),
        3 => const AttackScreen(),
        4 => const ThreatLogScreen(),
        5 => const AnalyticsScreen(),
        _ => const SettingsScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final state = AppState.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final body = QuantumBackground(
      child: SafeArea(
        child: Column(
          children: [
            _AppBar(
              title: _destinations[_index].label,
              online: state.backendOnline,
              onSettings: () => setState(() => _index = 6),
            ),
            Expanded(
              child: KeyedSubtree(key: ValueKey(_index), child: _screen(_index)),
            ),
          ],
        ),
      ),
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                      icon: Icon(d.icon), label: Text(d.label)),
              ],
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        // Settings (index 6) is reached from the app bar icon, so keep the bar
        // selection within its own destination range.
        selectedIndex: _index >= 6 ? 0 : _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations.take(6))
            NavigationDestination(icon: Icon(d.icon), label: d.label),
        ],
      ),
    );
  }
}

class _AppBar extends StatelessWidget {
  const _AppBar({required this.title, required this.online, required this.onSettings});

  final String title;
  final bool online;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          const Icon(Icons.shield_moon, color: AppTheme.accentCyan),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (online ? AppTheme.success : AppTheme.danger)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(online ? Icons.cloud_done : Icons.cloud_off,
                    size: 16, color: online ? AppTheme.success : AppTheme.danger),
                const SizedBox(width: 6),
                Text(online ? 'Backend online' : 'Offline',
                    style: TextStyle(
                        fontSize: 12,
                        color: online ? AppTheme.success : AppTheme.danger)),
              ],
            ),
          ),
          IconButton(onPressed: onSettings, icon: const Icon(Icons.settings)),
        ],
      ),
    );
  }
}
