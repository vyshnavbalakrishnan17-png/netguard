import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../providers/app_state.dart';
import '../router/router_controller.dart';
import '../widgets/common.dart';

/// Presets are shortcuts that add the listed domains one by one.
/// They do NOT block every domain a service uses.
const presets = {
  'Social Media': ['facebook.com', 'instagram.com', 'x.com'],
  'Streaming': ['youtube.com', 'netflix.com'],
  'Gaming': ['roblox.com', 'steampowered.com'],
};

class WebsitesScreen extends StatelessWidget {
  const WebsitesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Website Restrictions')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _add(context), icon: const Icon(Icons.add), label: const Text('ADD WEBSITE')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Blocked websites  ${s.urlRules.length} / ${RouterController.urlLimit}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        if (s.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(s.error!,
                style: const TextStyle(color: NG.orange, fontSize: 13)),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Router limitation (verified by testing): only old-style HTTP websites can be blocked on this router. Modern HTTPS sites (YouTube, Instagram, WhatsApp) cannot be filtered.',
            style: TextStyle(color: NG.orange, fontSize: 12, height: 1.4),
          ),
        ),
        const SizedBox(height: 12),
        for (final u in s.urlRules) panel(Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(u.domain, style: const TextStyle(fontSize: 16)), const StatusDot('BLOCKED', NG.red)])),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
            if (await confirm(context, 'Remove website restriction?', u.domain, 'Remove')) s.removeSite(u.domain);
          })])),
        const SizedBox(height: 8),
        const Text('Categories', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const Text('Adds the listed domains to the router URL filter. Does not cover every domain a service uses.', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        for (final e in presets.entries) panel(Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(e.key), Text(e.value.join(', '), style: const TextStyle(color: Colors.white54, fontSize: 12))])),
          TextButton(onPressed: () async {
            if (!await confirm(context, 'Block ${e.key}?', e.value.join('\n'), 'Block')) return;
            for (final d in e.value) { await s.addSite(d); }
          }, child: const Text('BLOCK ALL'))])),
        const SizedBox(height: 70),
      ]),
    );
  }

  Future<void> _add(BuildContext c) async {
    final ctl = TextEditingController();
    final s = c.read<AppState>();
    final input = await showDialog<String>(context: c, builder: (_) => AlertDialog(
          title: const Text('Add Website'),
          content: TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(labelText: 'Website', hintText: 'youtube.com')),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('BLOCK WEBSITE'))]));
    if (input == null) return;
    final err = await s.addSite(input);
    if (c.mounted && err != null) toast(c, err);
  }
}
