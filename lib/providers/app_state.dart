import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/validators.dart';
import '../models/models.dart';
import '../router/router_controller.dart';

class AppState extends ChangeNotifier {
  RouterController router;
  final Future<void> Function()? _onStart;
  AppState(this.router, {Future<void> Function()? onStart}) : _onStart = onStart;

  /// User-assigned device names, keyed by normalised MAC — the router
  /// never knows device names, so these are the source of truth once set.
  final Map<String, String> _deviceNames = {};

  static String _macKey(String mac) =>
      mac.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();

  /// The custom name set for [mac], if any (null when default naming).
  String? customName(String mac) => _deviceNames[_macKey(mac)];

  /// Load persisted names, connect in the background, then do the first
  /// refresh — in that order. Never throws: an unreachable router is
  /// reported through [error] so the UI can show a friendly banner.
  Future<void> start() async {
    await loadDeviceNames();
    if (_onStart != null) {
      try {
        await _onStart();
      } catch (_) {
        // refresh() below turns the failure into a readable error.
      }
    }
    await refresh();
  }

  /// Load persisted names (call once before the first refresh).
  Future<void> loadDeviceNames() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('device_names');
      if (raw != null) {
        _deviceNames
          ..clear()
          ..addAll(Map<String, String>.from(jsonDecode(raw) as Map));
      }
    } catch (_) {
      // Corrupt/absent storage → fall back to default names.
    }
  }

  /// Assign (or with an empty [name], remove) a device's display name.
  Future<void> renameDevice(String mac, String name) async {
    final key = _macKey(mac);
    if (name.trim().isEmpty) {
      _deviceNames.remove(key);
    } else {
      _deviceNames[key] = name.trim();
    }
    final p = await SharedPreferences.getInstance();
    await p.setString('device_names', jsonEncode(_deviceNames));
    await refresh();
  }

  /// Swap in a new controller (e.g. the real router after a successful
  /// connection test) and reload everything from it.
  Future<void> setRouter(RouterController r, {String? label}) async {
    router = r;
    if (label != null) _log('connect', 'Connected to router $label');
    await refresh();
  }
  RouterStatus? status;
  List<Device> devices = [];
  List<MacRule> macRules = [];
  List<UrlRule> urlRules = [];
  final logs = <ActivityLog>[];
  String? error;

  int get blockedDevices => devices.where((d) => d.blocked).length;

  void _log(String t, String s) { logs.insert(0, ActivityLog(t, s)); }

  Future<void> refresh() async {
    try {
      status = await router.getStatus();
      final raw = await router.getConnectedDevices();
      devices = raw.map((d) {
        final n = customName(d.mac);
        return (n != null && n.isNotEmpty) ? d.copyWith(name: n) : d;
      }).toList();
      macRules = await router.getMacFilterRules();
      urlRules = await router.getUrlFilterRules();
      // The router drops blocked clients from its client table — keep
      // them visible (as blocked) so they can always be unblocked.
      final known = {for (final d in devices) _macKey(d.mac)};
      final now = DateTime.now();
      for (final r in macRules) {
        if (r.type == 'blacklist' && !known.contains(_macKey(r.mac))) {
          devices.add(Device(
            name: customName(r.mac) ?? 'Blocked device',
            ip: '',
            mac: r.mac,
            blocked: true,
            online: false,
            firstSeen: now,
            lastSeen: now,
          ));
        }
      }
      error = null;
    } catch (e) {
      // Prefer the controller's specific message ("...same Wi-Fi network",
      // "did not respond in time", login problems) over a generic one.
      error = e is RouterException
          ? e.message
          : 'Unable to connect to the router. Make sure your phone is connected to the same Wi-Fi network.';
      _log('failure', 'Router connection failed');
    }
    notifyListeners();
  }

  /// Returns null on success, or a friendly error message.
  Future<String?> setBlocked(Device d, bool block) async {
    try {
      block ? await router.addMacBlacklist(d.mac) : await router.removeMacBlacklist(d.mac);
      _log(block ? 'block' : 'unblock', '${d.name} ${block ? 'blocked' : 'unblocked'}');
      await refresh();
      return null;
    } on RouterException catch (e) {
      _log('failure', 'Configuration failed: ${e.message}');
      notifyListeners();
      return e.message;
    }
  }

  Future<String?> addSite(String input) async {
    final d = normalizeDomain(input);
    if (d == null) return 'Enter a valid domain, e.g. youtube.com';
    if (urlRules.any((u) => u.domain == d)) return '$d is already blocked.';
    try {
      await router.addUrlBlock(d);
      _log('site', '$d added to blocked websites');
      await refresh();
      return null;
    } on RouterException catch (e) { return e.message; }
  }

  Future<void> removeSite(String d) async {
    await router.removeUrlBlock(d);
    _log('site', '$d removed from blocked websites');
    await refresh();
  }
}
