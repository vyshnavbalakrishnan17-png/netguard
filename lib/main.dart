import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'providers/app_state.dart';
import 'router/mock_router_controller.dart';
import 'router/netlink_hg323_controller.dart';
import 'router/router_controller.dart';
import 'screens/activity_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/devices_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/websites_screen.dart';

/// Starts on the real router when credentials were saved in Connect Router;
/// otherwise boots the Phase 1 demo (mock) controller.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final ip = prefs.getString('router_ip');
  final user = prefs.getString('router_user');
  final pass = prefs.getString('router_pass');

  // The router connection runs in the BACKGROUND (via AppState.start) —
  // blocking here would show a blank screen whenever the phone is away
  // from home WiFi.
  RouterController router;
  Future<void> Function()? onStart;
  if (ip != null && user != null && pass != null) {
    final real = NetlinkHG323Controller(username: user, password: pass);
    router = real;
    onStart = () => real.connect(ip);
  } else {
    router = MockRouterController();
  }

  runApp(ChangeNotifierProvider(
      create: (_) => AppState(router, onStart: onStart)..start(),
      child: const NetGuardApp()));
}

class NetGuardApp extends StatelessWidget {
  const NetGuardApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'NetGuard', debugShowCheckedModeBanner: false, theme: ngTheme(), home: const Shell());
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override State<Shell> createState() => _ShellState();
}
class _ShellState extends State<Shell> {
  int i = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: i, children: [
          DashboardScreen(goTo: (n) => setState(() => i = n)),
          const DevicesScreen(), const WebsitesScreen(), const ActivityScreen(), const SettingsScreen()]),
        bottomNavigationBar: NavigationBar(selectedIndex: i, onDestinationSelected: (n) => setState(() => i = n), destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.devices), label: 'Devices'),
          NavigationDestination(icon: Icon(Icons.language), label: 'Websites'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings')]),
      );
}
