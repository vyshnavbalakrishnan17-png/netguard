import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../providers/app_state.dart';
import '../router/router_controller.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatelessWidget {
  final void Function(int) goTo;
  const DashboardScreen({super.key, required this.goTo});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final connecting = s.status == null && s.error == null;
    final ok = s.status != null && s.error == null;
    return Scaffold(
      appBar: AppBar(title: const Row(children: [Icon(Icons.shield, color: NG.blue), SizedBox(width: 8), Text('NETGUARD', style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.bold))])),
      body: RefreshIndicator(onRefresh: s.refresh, child: ListView(padding: const EdgeInsets.all(16), children: [
        panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Wi-Fi Status', style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 6),
          StatusDot(connecting ? 'Connecting…' : (ok ? 'Connected' : 'Disconnected'),
              connecting ? NG.orange : (ok ? NG.green : NG.red)),
          const SizedBox(height: 12),
          Text('Router  ${s.status?.ip ?? '192.168.1.1'}'),
          Text('Internet  ${s.status?.internetUp == true ? 'Online' : 'Unknown'}'),
          if (s.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.error!, style: const TextStyle(color: NG.orange))),
        ])),
        StatCard(Icons.devices, '${s.devices.length}', 'Connected Devices', NG.green),
        StatCard(Icons.block, '${s.blockedDevices}', 'Blocked Devices', NG.red),
        StatCard(Icons.language, '${s.urlRules.length} / ${RouterController.urlLimit}', 'Blocked Websites', NG.orange),
        StatCard(Icons.rule, '${s.macRules.length} / ${RouterController.macLimit}', 'MAC filter rules', NG.blue),
        Row(children: [
          Expanded(child: FilledButton(onPressed: () => goTo(1), child: const Text('DEVICES'))), const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: () => goTo(2), child: const Text('WEBSITE BLOCKING')))]),
      ])),
    );
  }
}
