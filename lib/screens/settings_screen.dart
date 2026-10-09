import 'package:flutter/material.dart';
import '../widgets/common.dart';
import 'router_setup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    Widget tile(IconData i, String t, [String? sub, VoidCallback? onTap]) => panel(Row(children: [Icon(i), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t), if (sub != null) Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 12))]))]), onTap: onTap);
    return Scaffold(appBar: AppBar(title: const Text('Settings')), body: ListView(padding: const EdgeInsets.all(16), children: [
      tile(Icons.router, 'Router settings', '192.168.1.1  •  Connect / reconnect / logout', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RouterSetupScreen()))),
      tile(Icons.pin, 'Change application PIN', 'Coming in security phase'),
      tile(Icons.fingerprint, 'Biometric authentication', 'Coming in security phase'),
      tile(Icons.timer, 'Auto-lock & refresh interval', 'Coming soon'),
      tile(Icons.dark_mode, 'Appearance', 'Dark (light / system coming soon)'),
      tile(Icons.info_outline, 'About', 'NetGuard 0.1.0 — controls your Netlink HG323R'),
    ]));
  }
}
