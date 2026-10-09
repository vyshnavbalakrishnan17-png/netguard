import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

Widget panel(Widget child, {VoidCallback? onTap}) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: NG.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: NG.line)),
      child: Material(color: Colors.transparent, borderRadius: BorderRadius.circular(16),
          child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: Padding(padding: const EdgeInsets.all(16), child: child))),
    );

class StatusDot extends StatelessWidget {
  final String label; final Color color;
  const StatusDot(this.label, this.color, {super.key});
  @override
  Widget build(BuildContext c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 10, color: color), const SizedBox(width: 6), Text(label, style: TextStyle(color: color))]);
}

class StatCard extends StatelessWidget {
  final IconData icon; final String value, label; final Color color;
  const StatCard(this.icon, this.value, this.label, this.color, {super.key});
  @override
  Widget build(BuildContext c) => panel(Row(children: [
        Icon(icon, color: color, size: 30), const SizedBox(width: 16),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color))]));
}

Future<bool> confirm(BuildContext c, String title, String body, String action) async =>
    await showDialog<bool>(context: c, builder: (_) => AlertDialog(
          title: Text(title), content: Text(body),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action))])) ?? false;

void toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
