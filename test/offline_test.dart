import 'package:flutter_test/flutter_test.dart';
import 'package:netguard/models/models.dart';
import 'package:netguard/providers/app_state.dart';
import 'package:netguard/router/mock_router_controller.dart';
import 'package:netguard/router/router_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simulates the phone being away from home WiFi: every router call fails
/// the way the real controller fails (SocketException wrapped in a
/// RouterException with the friendly "same Wi-Fi network" message).
class _OfflineRouter extends MockRouterController {
  int connectCalls = 0;

  @override
  Future<void> connect(String ip) async {
    connectCalls++;
    throw const RouterException(
        'Could not reach the router. Check that this phone is on the same Wi-Fi network.');
  }

  @override
  Future<RouterStatus> getStatus() async {
    throw const RouterException(
        'Could not reach the router. Check that this phone is on the same Wi-Fi network.');
  }
}

/// Records the order of startup steps so we can prove the router is
/// connected before the first data refresh.
class _RecordingRouter extends MockRouterController {
  final order = <String>[];

  @override
  Future<void> connect(String ip) async => order.add('connect');

  @override
  Future<RouterStatus> getStatus() async {
    order.add('status');
    return super.getStatus();
  }
}

void main() {
  test('start() survives an offline router without hanging or throwing',
      () async {
    SharedPreferences.setMockInitialValues(
        {'router_ip': '192.168.1.1', 'router_user': 'admin', 'router_pass': 'x'});
    final r = _OfflineRouter();
    final s = AppState(r, onStart: () => r.connect('192.168.1.1'));

    await s.start(); // must complete promptly and not rethrow

    expect(r.connectCalls, 1);
    expect(s.error, contains('same Wi-Fi'));
    expect(s.status, isNull);
    expect(s.devices, isEmpty); // no stale pretend data
  });

  test('startup connects to the router before the first refresh',
      () async {
    SharedPreferences.setMockInitialValues({});
    final r = _RecordingRouter();
    final s = AppState(r, onStart: () => r.connect('192.168.1.1'));

    await s.start();

    expect(r.order, ['connect', 'status']);
    expect(s.error, isNull);
    expect(s.status, isNotNull);
  });

  test('offline error does not destroy already-loaded device names',
      () async {
    SharedPreferences.setMockInitialValues({});
    final ok = MockRouterController();
    final s = AppState(ok);
    await s.start();
    final mac = s.devices.first.mac;
    await s.renameDevice(mac, 'Kitchen TV');

    // Network drops: replace with an unreachable router.
    s.router = _OfflineRouter();
    await s.refresh();

    expect(s.error, isNotNull);
    // Devices keep the last known (renamed) data while offline.
    expect(s.devices.firstWhere((d) => d.mac == mac).name, 'Kitchen TV');
  });
}
