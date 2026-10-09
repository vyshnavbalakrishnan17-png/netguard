import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../router/router_controller.dart';
import '../widgets/common.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});
  @override State<DevicesScreen> createState() => _S();
}
class _S extends State<DevicesScreen> {
  String q = '', f = 'All';
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = s.devices.where((d) =>
        (f == 'All' || (f == 'Blocked') == d.blocked) &&
        '${d.name}${d.ip}${d.mac}${d.manufacturer}'.toLowerCase().contains(q.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Connected Devices')),
      body: RefreshIndicator(onRefresh: s.refresh, child: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(onChanged: (v) => setState(() => q = v), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Search devices', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
        if (s.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child:
                Text(s.error!, style: const TextStyle(color: NG.orange, fontSize: 13)),
          ),
        const SizedBox(height: 12),
        SegmentedButton<String>(segments: [for (final x in ['All', 'Allowed', 'Blocked']) ButtonSegment(value: x, label: Text(x))], selected: {f}, onSelectionChanged: (v) => setState(() => f = v.first)),
        const SizedBox(height: 8),
        Text('MAC filter limit: ${RouterController.macLimit} rules  •  Used: ${s.macRules.length} / ${RouterController.macLimit}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            'Router limitation (verified by testing): this router saves block rules but does not actually enforce them — blocked devices keep their internet access.',
            style: TextStyle(color: NG.orange, fontSize: 12, height: 1.4),
          ),
        ),
        for (final d in list) DeviceCard(d),
      ])),
    );
  }
}

class DeviceCard extends StatelessWidget {
  final Device d; const DeviceCard(this.d, {super.key});
  @override
  Widget build(BuildContext context) => panel(
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text([
              if (d.manufacturer != 'Unknown') d.manufacturer,
              if (d.ip.isNotEmpty) d.ip,
            ].join('  •  '), style: const TextStyle(color: Colors.white70)),
            Text(d.mac, style: const TextStyle(color: Colors.white54, fontFamily: 'monospace')),
            const SizedBox(height: 6),
            StatusDot(d.blocked ? 'Blocked' : 'Allowed', d.blocked ? NG.red : NG.green),
          ])),
          IconButton(
            tooltip: 'Rename device',
            onPressed: () => renameDialog(context, d),
            icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.white54),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          OutlinedButton(onPressed: () => blockFlow(context, d), child: Text(d.blocked ? 'UNBLOCK' : 'BLOCK')),
        ]),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeviceDetails(d.mac))),
      );
}

/// Ask for a display name for [d] and persist it (keyed by MAC). The
/// router never knows device names — this is how they become readable.
Future<void> renameDialog(BuildContext c, Device d) async {
  final s = c.read<AppState>();
  final ctl = TextEditingController(text: d.name);
  var remove = false;
  final hasCustom = s.customName(d.mac) != null;
  await showDialog<void>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: const Text('Name this device'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLength: 30,
        decoration: const InputDecoration(
            hintText: 'e.g. Amma’s phone, Living room TV', counterText: ''),
      ),
      actions: [
        if (hasCustom)
          TextButton(
              onPressed: () { remove = true; Navigator.pop(ctx); },
              child: const Text('Remove name')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Save')),
      ],
    ),
  );
  if (!c.mounted) return;
  if (remove) {
    await s.renameDevice(d.mac, '');
    return;
  }
  final t = ctl.text.trim();
  if (t.isNotEmpty && t != d.name) await s.renameDevice(d.mac, t);
}

Future<void> blockFlow(BuildContext c, Device d) async {
  final s = c.read<AppState>();
  final block = !d.blocked;
  if (block) {
    if (d.isThisPhone && !await confirm(c, 'This is your device', 'You are about to block the device you are using. You may lose access to the router admin page.', 'Continue')) return;
    if (!c.mounted) return;
    if (!await confirm(c, 'Block this device?', 'This device will lose network access.\n\nSome devices use a private/randomized MAC address. The router may therefore see a different MAC address than expected.', 'Block')) return;
  } else if (!await confirm(c, 'Allow this device again?', d.name, 'Allow')) { return; }
  final err = await s.setBlocked(d, block);
  if (c.mounted) toast(c, err ?? (block ? 'Device blocked successfully.' : 'Device allowed.'));
}

class DeviceDetails extends StatelessWidget {
  final String mac; const DeviceDetails(this.mac, {super.key});
  @override
  Widget build(BuildContext context) {
    final matches = context.watch<AppState>().devices.where((x) => x.mac == mac);
    if (matches.isEmpty) {
      // Device dropped off the network while its page was open.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }
    final d = matches.first;
    String t(DateTime x) => '${x.day}/${x.month}/${x.year} ${x.hour}:${x.minute.toString().padLeft(2, '0')}';
    Widget row(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [SizedBox(width: 110, child: Text(k, style: const TextStyle(color: Colors.white54))), Expanded(child: Text(v))]));
    return Scaffold(appBar: AppBar(title: Text(d.name)), body: ListView(padding: const EdgeInsets.all(16), children: [
      panel(Column(children: [row('IP', d.ip), row('MAC', d.mac), row('Manufacturer', d.manufacturer), row('Status', d.blocked ? 'Blocked' : 'Allowed'), row('First seen', t(d.firstSeen)), row('Last seen', t(d.lastSeen))])),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: () => renameDialog(context, d),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('RENAME DEVICE'),
      ),
      const SizedBox(height: 10),
      FilledButton(style: FilledButton.styleFrom(backgroundColor: d.blocked ? NG.green : NG.red), onPressed: () => blockFlow(context, d), child: Text(d.blocked ? 'UNBLOCK DEVICE' : 'BLOCK DEVICE')),
    ]));
  }
}
