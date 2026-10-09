import '../models/models.dart';
import 'router_controller.dart';

/// PHASE 1 only: in-memory fake so the UI can be built. Not a real router.
class MockRouterController implements RouterController {
  final _now = DateTime.now();
  late final List<Device> _devices = [
    Device(name: 'My Phone', ip: '192.168.1.10', mac: 'AA:BB:CC:DD:EE:FF', manufacturer: 'Samsung', isThisPhone: true, firstSeen: _now.subtract(const Duration(days: 30)), lastSeen: _now),
    Device(name: 'Samsung TV', ip: '192.168.1.11', mac: '11:22:33:44:55:66', manufacturer: 'Samsung', firstSeen: _now.subtract(const Duration(days: 90)), lastSeen: _now),
    Device(name: 'Unknown Device', ip: '192.168.1.12', mac: 'AA:BB:11:22:33:44', online: false, firstSeen: _now.subtract(const Duration(days: 2)), lastSeen: _now.subtract(const Duration(hours: 5))),
  ];
  final _macs = <String>{'AA:BB:11:22:33:44'};
  final _urls = <String>['facebook.com', 'instagram.com'];
  @override Future<void> connect(String ip) async {}
  @override Future<void> login(String u, String p) async {
    if (u.isEmpty || p.isEmpty) throw const RouterException('Wrong credentials.');
  }
  @override Future<void> logout() async {}
  @override Future<RouterStatus> getStatus() async => const RouterStatus(wifiUp: true, internetUp: true, ip: '192.168.1.1', model: 'Netlink HG323 / IGD');
  @override Future<List<Device>> getConnectedDevices() async => _devices.map((d) => d.copyWith(blocked: _macs.contains(d.mac))).toList();
  @override Future<List<MacRule>> getMacFilterRules() async => _macs.map(MacRule.new).toList();
  @override Future<void> addMacBlacklist(String mac) async {
    if (_macs.length >= RouterController.macLimit) throw const RouterException('MAC filter limit reached. Remove an existing rule before adding another.');
    _macs.add(mac);
  }
  @override Future<void> removeMacBlacklist(String mac) async => _macs.remove(mac);
  @override Future<List<UrlRule>> getUrlFilterRules() async => _urls.map(UrlRule.new).toList();
  @override Future<void> addUrlBlock(String d) async {
    if (_urls.length >= RouterController.urlLimit) throw const RouterException('URL filter limit reached (100).');
    if (!_urls.contains(d)) _urls.add(d);
  }
  @override Future<void> removeUrlBlock(String d) async => _urls.remove(d);
  @override Future<void> enableMacFilter() async {}
  @override Future<void> disableMacFilter() async {}
  @override Future<void> enableUrlFilter() async {}
  @override Future<void> disableUrlFilter() async {}
}
