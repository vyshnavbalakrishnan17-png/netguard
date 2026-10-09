import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/app_theme.dart';
import '../providers/app_state.dart';
import '../router/netlink_hg323_controller.dart';
import '../widgets/common.dart';

class RouterSetupScreen extends StatefulWidget {
  const RouterSetupScreen({super.key});
  @override
  State<RouterSetupScreen> createState() => _S();
}

class _S extends State<RouterSetupScreen> {
  final ip = TextEditingController(text: '192.168.1.1'),
      user = TextEditingController(text: 'admin'),
      pass = TextEditingController();
  bool busy = false;
  String? error, success;

  Future<void> _connect() async {
    setState(() { busy = true; error = null; success = null; });
    final c = NetlinkHG323Controller(username: user.text, password: pass.text);
    try {
      await c.connect(ip.text);
      if (!mounted) return;
      final status = await c.getStatus();
      if (!mounted) return;
      // Persist so the app starts on this router from now on.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('router_ip', ip.text.trim());
      await prefs.setString('router_user', user.text);
      await prefs.setString('router_pass', pass.text);
      if (!mounted) return;
      await context.read<AppState>().setRouter(c, label: ip.text);
      if (!mounted) return;
      setState(() => success =
          '${status.model} @ ${status.ip} — Wi-Fi ${status.wifiUp ? "on" : "off"}, internet ${status.internetUp ? "up" : "down"}');
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Connect Router')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            controller: ip,
            decoration: const InputDecoration(
                labelText: 'Router IP',
                hintText: '192.168.1.1')),
        const SizedBox(height: 12),
        TextField(
            controller: user,
            decoration: const InputDecoration(labelText: 'Username (optional)')),
        const SizedBox(height: 12),
        TextField(
            controller: pass,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Password (optional)',
                helperText: 'Router admin password — stays on this phone only')),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: busy ? null : _connect,
            child: busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('TEST CONNECTION')),
        if (error != null) ...[
          const SizedBox(height: 16),
          panel(StatusDot(error!, NG.red)),
        ],
        if (success != null) ...[
          const SizedBox(height: 16),
          panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const StatusDot('Router Connected', NG.green),
            const SizedBox(height: 6),
            Text(success!),
          ])),
        ],
      ]));
}
