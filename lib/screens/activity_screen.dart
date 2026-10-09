import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../providers/app_state.dart';
import '../widgets/common.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final logs = context.watch<AppState>().logs;
    return Scaffold(appBar: AppBar(title: const Text('Activity')), body: logs.isEmpty
        ? const Center(child: Text('No activity yet', style: TextStyle(color: Colors.white54)))
        : ListView(padding: const EdgeInsets.all(16), children: [for (final l in logs) panel(Row(children: [
            Icon(l.type == 'failure' ? Icons.error_outline : l.type == 'block' ? Icons.block : Icons.history, color: l.type == 'failure' ? NG.orange : NG.blue),
            const SizedBox(width: 12),
            Expanded(child: Text(l.text)),
            Text('${l.time.hour}:${l.time.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: Colors.white54))]))]));
  }
}
