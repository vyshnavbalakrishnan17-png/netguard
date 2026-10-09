import 'package:flutter_test/flutter_test.dart';
import 'package:netguard/core/oui_db.dart';
import 'package:netguard/providers/app_state.dart';
import 'package:netguard/router/mock_router_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('manufacturer lookup (OUI)', () {
    test('randomized (locally-administered) MACs are rejected', () {
      // Every octet pattern below has the RFC 1122 local bit set — the
      // household devices all use private/randomized MACs.
      expect(manufacturerFor('aa:bb:cc:dd:ee:77'), isNull);
      expect(manufacturerFor('0A:44:55:66:77:88'), isNull);
      expect(manufacturerFor('8a:01:02:03:04:05'), isNull);
      expect(manufacturerFor('aa-bb-cc-dd-ee-ff'), isNull);
      expect(manufacturerFor('02:11:22:33:44:55'), isNull);
    });

    test('globally-administered known prefixes resolve', () {
      expect(manufacturerFor('00:00:0c:11:22:33'), 'Cisco');
      expect(manufacturerFor('00000C'), 'Cisco');
      expect(ouiDb['00000C'], isNotNull);
    });

    test('junk and short input return null', () {
      expect(manufacturerFor(''), isNull);
      expect(manufacturerFor('zz'), isNull);
      expect(manufacturerFor('not a mac'), isNull);
    });
  });

  group('device naming', () {
    test('custom names apply, persist across restart, and can be removed',
        () async {
      SharedPreferences.setMockInitialValues({});

      final s = AppState(MockRouterController());
      await s.start();
      expect(s.devices, isNotEmpty);
      final mac = s.devices.first.mac;

      await s.renameDevice(mac, 'Kitchen TV');
      expect(s.devices.firstWhere((d) => d.mac == mac).name, 'Kitchen TV');

      // Simulate an app restart: a fresh state loads the same storage.
      final s2 = AppState(MockRouterController());
      await s2.start();
      expect(s2.devices.firstWhere((d) => d.mac == mac).name, 'Kitchen TV');
      expect(s2.customName(mac), 'Kitchen TV');

      // Removing the name falls back to the router/default naming.
      await s2.renameDevice(mac, '');
      expect(s2.customName(mac), isNull);
      expect(s2.devices.firstWhere((d) => d.mac == mac).name,
          isNot('Kitchen TV'));
    });
  });
}
