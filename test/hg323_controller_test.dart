import 'package:flutter_test/flutter_test.dart';
import 'package:netguard/router/netlink_hg323_controller.dart';
import 'package:netguard/router/router_controller.dart';

/// Fixtures below are verbatim fragments captured from the user's
/// Netlink HG323R (Boa/0.93.15) during reverse engineering.
void main() {
  const macListHtml = '''
var cgi = new Object();
var rules = new Array();
with(rules){push(new it_nr("0", new it("devname", ""), new it("mac", "aa-bb-cc-dd-ee-99")));
push(new it_nr("1", new it("devname", "TV"), new it("mac", "aa-bb-cc-dd-ee-88")));
cgi.macFilterEnble = true;
cgi.excludeMode = false;
}
<input type='hidden' name='csrftoken' value='26dc63dc0db4c3758bad2c77d31ba64e' />
''';

  const ethernetHtml = '''
var clts = new Array();
clts.push(new it_nr("0", new it("devname", ""), new it("macAddr", "aa:bb:cc:dd:ee:77"), new it("ipAddr", "192.168.1.5"), new it("liveTime", "86211")));
clts.push(new it_nr("1", new it("devname", "PC"), new it("macAddr", "aa:bb:cc:dd:ee:66"), new it("ipAddr", "192.168.1.3"), new it("liveTime", "83480")));
''';

  const wanHtml = '''
links.push(new it_nr("0", new it("servName", "1_TR069_INTERNET_R_VID_240"), new it("protocol", "PPPoE"), new it("ipAddr", "203.0.113.10"), new it("strStatus", "up"), new it("MacAddr", "02:aa:bb:cc:dd:ee")));
links.push(new it_nr("1", new it("servName", "2_VOICE_R_VID_1831"), new it("strStatus", "down")));
''';

  group('parseRows', () {
    test('bare rules pushes (with(rules){...})', () {
      final rows = NetlinkHG323Controller.parseRows(macListHtml, 'rules');
      expect(rows, hasLength(2));
      expect(rows[0]['mac'], 'aa-bb-cc-dd-ee-99');
      expect(rows[0]['name'], '0');
      expect(rows[0]['devname'], '');
      expect(rows[1]['mac'], 'aa-bb-cc-dd-ee-88');
      expect(rows[1]['devname'], 'TV');
      expect(rows[1]['name'], '1');
    });

    test('named array clts (connected devices)', () {
      final rows = NetlinkHG323Controller.parseRows(ethernetHtml, 'clts');
      expect(rows, hasLength(2));
      expect(rows[0]['macAddr'], 'aa:bb:cc:dd:ee:77');
      expect(rows[0]['ipAddr'], '192.168.1.5');
      expect(rows[0]['liveTime'], '86211');
      expect(rows[1]['ipAddr'], '192.168.1.3');
    });

    test('named array links (WAN connections)', () {
      final rows = NetlinkHG323Controller.parseRows(wanHtml, 'links');
      expect(rows, hasLength(2));
      expect(rows[0]['servName'], '1_TR069_INTERNET_R_VID_240');
      expect(rows[0]['strStatus'], 'up');
      expect(rows[1]['strStatus'], 'down');
    });

    test('empty input yields no rows', () {
      expect(NetlinkHG323Controller.parseRows('<html></html>', 'rules'), isEmpty);
    });
  });

  group('cgiFlag', () {
    test('reads boolean flags', () {
      expect(NetlinkHG323Controller.cgiFlag(macListHtml, 'macFilterEnble'), isTrue);
      expect(NetlinkHG323Controller.cgiFlag(macListHtml, 'excludeMode'), isFalse);
    });
  });

  group('csrf token extraction', () {
    test('single-quoted hidden field', () {
      final t = RegExp(r"""name=['"]csrftoken['"]\s+value=['"]([0-9a-fA-F]+)['"]""")
          .firstMatch(macListHtml)!
          .group(1);
      expect(t, '26dc63dc0db4c3758bad2c77d31ba64e');
    });
  });

  group('macBcdata (bencode delete payload)', () {
    test('matches the payload the router web UI sent, byte for byte', () {
      // Captured live: POST /boaform/admin/formRteMacFilter action=rm with
      // bcdata=ld4:name1:07:devname0:3:mac17:aa-bb-cc-dd-ee-99ed4:name1:1...
      final rules = NetlinkHG323Controller.parseRows(macListHtml, 'rules');
      final bc = NetlinkHG323Controller.macBcdata([rules[0]]);
      expect(bc, 'ld4:name1:07:devname0:3:mac17:aa-bb-cc-dd-ee-99ee');
    });

    test('two rules concatenated inside one list', () {
      final rules = NetlinkHG323Controller.parseRows(macListHtml, 'rules');
      final bc = NetlinkHG323Controller.macBcdata(rules);
      expect(bc,
          'ld4:name1:07:devname0:3:mac17:aa-bb-cc-dd-ee-99e'
          'd4:name1:17:devname2:TV3:mac17:aa-bb-cc-dd-ee-88e'
          'e');
    });
  });

  group('urlBcdata', () {
    test('index payload matches captured sji_idxencode output', () {
      expect(NetlinkHG323Controller.urlBcdata(0), 'ld3:idxi0eee');
      expect(NetlinkHG323Controller.urlBcdata(7), 'ld3:idxi7eee');
    });
  });

  group('login page handling', () {
    const loginPage = """
<HTML><HEAD><TITLE>ONT</TITLE></HEAD>
<SCRIPT>
function CreateCode()
{
	document.getElementById('check_code').value='ngs5i';
}
</SCRIPT>
<form action=/boaform/admin/formLogin_en method=POST name="cmlogin">
<input type='hidden' name='csrftoken' value='465e9e9f6813f0ece78072e79e02021f' />
</form></HTML>
""";

    test('isLoginPage recognises the login wall', () {
      expect(NetlinkHG323Controller.isLoginPage(loginPage), isTrue);
      expect(NetlinkHG323Controller.isLoginPage(macListHtml), isFalse);
    });

    test('captcha is read from the server-generated CreateCode block', () {
      expect(NetlinkHG323Controller.loginCaptcha(loginPage), 'ngs5i');
    });

    test('failed-login error pages map to friendly messages', () {
      expect(NetlinkHG323Controller.loginError('<h4>ERROR: Bad password!</h4>'),
          'Wrong router password.');
      expect(NetlinkHG323Controller.loginError('<h4>ERROR: Bad UserName!</h4>'),
          'Wrong router username.');
      expect(NetlinkHG323Controller.loginError('<h4>ERROR: timeout</h4>'),
          'Router login failed: timeout');
      // One-login-slot lock messages (must beat the 'user' keyword).
      expect(
          NetlinkHG323Controller.loginError(
              '<h4>ERROR: Another user have logined in using this account!only one user can login using this account at the same time!</h4>'),
          startsWith('Another device is signed in'));
      expect(
          NetlinkHG323Controller.loginError(
              '<h4>ERROR: You have logined! please logout at first and then login!</h4>'),
          'Already signed in on this device — tap connect again.');
    });

    test('csrf token also parses from the login page', () {
      expect(
          RegExp(r"""name=['"]csrftoken['"]\s+value=['"]([0-9a-fA-F]+)['"]""")
              .firstMatch(loginPage)!
              .group(1),
          '465e9e9f6813f0ece78072e79e02021f');
    });
  });

  group('MAC normalization', () {
    test('colon, dash and bare hex all normalize to router dash format', () {
      expect(NetlinkHG323Controller.dashMac('AA:BB:CC:DD:EE:FF'), 'aa-bb-cc-dd-ee-ff');
      expect(NetlinkHG323Controller.dashMac('aa-bb-cc-dd-ee-ff'), 'aa-bb-cc-dd-ee-ff');
      expect(NetlinkHG323Controller.dashMac('AABBCCDDEEFF'), 'aa-bb-cc-dd-ee-ff');
    });
    test('invalid MAC throws RouterException', () {
      expect(() => NetlinkHG323Controller.dashMac('not-a-mac'),
          throwsA(isA<RouterException>()));
    });
  });
}
