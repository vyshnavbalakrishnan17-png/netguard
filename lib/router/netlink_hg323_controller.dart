import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/oui_db.dart';
import '../models/models.dart';
import 'router_controller.dart';

/// Real controller for the Netlink HG323R GPON ONT web API.
///
/// Protocol (verified live against the router at 192.168.1.1):
///  * Pages sit behind a login wall: a device is authenticated per IP
///    (no cookies). [_get] auto-logs-in once with the stored credentials
///    when it sees the login form, and handles the router's
///    one-login-per-account lock via [loginError].
///  * Every page embeds a fresh `csrftoken` hidden field that must be
///    echoed back (form-urlencoded) in each POST.
///  * POSTs answer `301 Moved` back to the form's submit-url on success.
///  * Page data is server-rendered JS rows:
///    `clts.push(new it_nr("0", new it("key", "value"), ...));`
///    and rule lists appear as bare `push(new it_nr(...))` inside
///    `var rules = new Array(); with(rules){ ... }`.
///  * Delete payloads are bencode: MAC rules carry full dicts
///    (`d4:name1:07:devname0:3:mac17:...e`), URL rules carry indexes
///    (`ld3:idxi0eee` = delete rule 0).
class NetlinkHG323Controller implements RouterController {
  NetlinkHG323Controller({this.username = '', this.password = ''});

  String username, password;

  String _base = '';
  final http.Client _client = http.Client();

  static const _timeout = Duration(seconds: 8);

  static const _macListPage = '/secu_macfilter_src_en.asp';
  static const _macForm = '/boaform/admin/formRteMacFilter';
  static const _urlListPage = '/secu_urlfilter_cfg_en.asp';
  static const _urlForm = '/boaform/admin/formURL';

  // ---------------------------------------------------------------- helpers

  String _url(String path) => '$_base$path';

  String _friendly(Object e) => e is TimeoutException
      ? 'The router did not respond in time.'
      : 'Could not reach the router. Check that this phone is on the same Wi-Fi network.';

  Future<String> _get(String path, {bool retried = false}) async {
    try {
      // http follows redirects: an unauthenticated request lands on the
      // login page with HTTP 200, so detect it by content.
      final r = await _client.get(Uri.parse(_url(path))).timeout(_timeout);
      // The ONT serves GBK bytes with no charset header; decode per-byte
      // (latin-1 semantics) so decoding can never throw — everything we
      // parse (tokens, MACs, IPs, JS structure) is pure ASCII.
      final body = String.fromCharCodes(r.bodyBytes);
      if (isLoginPage(body)) {
        if (retried) {
          throw RouterException('Login failed. Check the admin username and password.');
        }
        await login(username, password);
        return await _get(path, retried: true);
      }
      if (r.statusCode != 200) {
        throw RouterException('Router returned HTTP ${r.statusCode} on $path');
      }
      return body;
    } on RouterException {
      rethrow;
    } catch (e) {
      throw RouterException(_friendly(e));
    }
  }

  Future<void> _post(String path, Map<String, String> fields,
      {bool retried = false}) async {
    try {
      final req = http.Request('POST', Uri.parse(_url(path)))
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/x-www-form-urlencoded'
        ..bodyFields = fields;
      final resp = await _client.send(req).timeout(_timeout);
      await resp.stream.drain<void>();
      final code = resp.statusCode;
      final loc = resp.headers['location'] ?? '';
      // Session expired mid-flight: the router redirects the POST to login.
      if (loc.contains('login')) {
        if (retried) {
          throw RouterException('Login failed. Check the admin username and password.');
        }
        await login(username, password);
        return await _post(path, fields, retried: true);
      }
      // Success = 301 back to submit-url (or a direct 200/302).
      if (code == 200 || code == 301 || code == 302) return;
      throw RouterException('The router rejected the request (HTTP $code).');
    } on RouterException {
      rethrow;
    } catch (e) {
      throw RouterException(_friendly(e));
    }
  }

  /// True when [html] is the ONT's login form rather than the page we asked
  /// for (the server serves it with HTTP 200 after following the redirect).
  static bool isLoginPage(String html) => html.contains('formLogin_en');

  /// The "verification code" is generated server-side into the login page
  /// (`CreateCode(){...value='ngs5i'}`) — read it back from the HTML.
  static String? loginCaptcha(String html) =>
      RegExp(r"""CreateCode\(\)[\s\S]*?value=['"]([0-9a-z]+)['"]""")
          .firstMatch(html)
          ?.group(1);

  /// Extracts the human-readable reason from the `ERROR: ...` page the
  /// ONT returns on a failed login.
  static String loginError(String html) {
    final m = RegExp(r'ERROR:\s*([^<\r\n]+)').firstMatch(html);
    final raw = (m?.group(1) ?? 'unknown error').trim();
    final l = raw.toLowerCase();
    // Check the two one-login-slot messages before the short keywords —
    // "Another user have logined..." also contains the word "user".
    if (l.contains('another user')) {
      return 'Another device is signed in to the router right now. '
          'Log it out there (router page → Logout), then retry.';
    }
    if (l.contains('logined')) {
      return 'Already signed in on this device — tap connect again.';
    }
    if (l.contains('password')) return 'Wrong router password.';
    if (l.contains('user')) return 'Wrong router username.';
    if (l.contains('code')) return 'Wrong verification code.';
    return 'Router login failed: $raw';
  }

  /// True when a protected page loads without hitting the login wall.
  Future<bool> _hasAccess() async {
    try {
      final r = await _client
          .get(Uri.parse('$_base/status_device_basic_info_en.asp'))
          .timeout(_timeout);
      return r.statusCode == 200 &&
          !isLoginPage(String.fromCharCodes(r.bodyBytes));
    } catch (_) {
      return false;
    }
  }

  static String _token(String html) {
    final m = RegExp(r"""name=['"]csrftoken['"]\s+value=['"]([0-9a-fA-F]+)['"]""")
        .firstMatch(html);
    if (m == null) {
      throw RouterException('Router page format not recognised (no security token).');
    }
    return m.group(1)!;
  }

  /// Parses server-rendered `push(new it_nr("i", new it("k", "v"), ...))`
  /// rows. [array] is the JS array name ('clts', 'links'), or 'rules' for
  /// the bare pushes inside `with(rules){ ... }`.
  ///
  /// The `it_nr` first argument is the row's `name` (the router's rule
  /// index); everything after it is a list of `new it(key, value)` pairs.
  static List<Map<String, String>> parseRows(String html, String array) {
    final prefix = array == 'rules'
        ? r'(?:^|[^.\w])push\('
        : '${RegExp.escape(array)}\\.push\\(';
    final row = RegExp('$prefix' r'new it_nr\("([^"]*)",(.*?)\)\);', dotAll: true);
    final pair = RegExp(r'new it\("(\w+)",\s*("[^"]*"|-?[\d.]+|true|false)\)');
    final out = <Map<String, String>>[];
    for (final m in row.allMatches(html)) {
      final map = <String, String>{'name': m.group(1)!};
      for (final p in pair.allMatches(m.group(2)!)) {
        var v = p.group(2)!;
        if (v.startsWith('"')) v = v.substring(1, v.length - 1);
        map[p.group(1)!] = v;
      }
      out.add(map);
    }
    return out;
  }

  /// Reads a `cgi.flag = true|false;` value rendered into the page script.
  static bool cgiFlag(String html, String name) {
    final m = RegExp('cgi\\.$name\\s*=\\s*(\\w+)').firstMatch(html);
    return m?.group(1)?.toLowerCase() == 'true';
  }

  /// 'AA:BB:CC:DD:EE:99' / 'aa-bb-..' -> 'aa-bb-cc-dd-ee-ff' (router format).
  static String dashMac(String mac) {
    final hex = canonMac(mac);
    if (hex.length != 12) throw RouterException('Invalid MAC address: $mac');
    return List.generate(6, (i) => hex.substring(i * 2, i * 2 + 2)).join('-');
  }

  /// Any MAC format -> 12 hex chars, for comparison.
  static String canonMac(String mac) =>
      mac.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');

  static bool _sameMac(String a, String b) =>
      a.isNotEmpty && b.isNotEmpty && canonMac(a) == canonMac(b);

  static String _benc(String k, String v) => '${k.length}:$k${v.length}:$v';

  /// bencode payload the web UI posts for `action=rm` on the MAC filter:
  /// `l` + one dict per selected rule {name, devname, mac} + `e`.
  static String macBcdata(List<Map<String, String>> rules) {
    final b = StringBuffer('l');
    for (final r in rules) {
      b
        ..write('d')
        ..write(_benc('name', r['name'] ?? '0'))
        ..write(_benc('devname', r['devname'] ?? ''))
        ..write(_benc('mac', r['mac'] ?? ''))
        ..write('e');
    }
    b.write('e');
    return b.toString();
  }

  /// bencode payload for `action=rm` on the URL filter (index based).
  static String urlBcdata(int index) => 'ld3:idxi${index}eee';

  // ------------------------------------------------------------ connection

  @override
  Future<void> connect(String ip) async {
    var host = ip.trim().replaceFirst(RegExp(r'^https?://'), '');
    host = host.replaceAll(RegExp(r'/.*$'), '');
    if (host.isEmpty) throw RouterException('Enter the router IP address.');
    _base = 'http://$host';
    // Probe a real page. _get only triggers login when the ONT shows its
    // login wall — if this device already has a live session (the ONT
    // tracks login per IP, e.g. from a browser), no login is needed and
    // the account-wide one-login slot is left alone.
    await _get('/status_device_basic_info_en.asp');
  }

  /// Logs into the ONT web UI. The router keeps sessions per IP address
  /// (no cookies): once this device logs in, subsequent requests from the
  /// same IP are authenticated until the session expires.
  ///
  /// Flow: GET the login page (for CSRF token + server-generated
  /// verification code) → POST credentials → expect `302 → /`.
  @override
  Future<void> login(String username, String password) async {
    this.username = username;
    this.password = password;
    if (_base.isEmpty) {
      throw RouterException('Connect to the router before logging in.');
    }
    if (username.isEmpty || password.isEmpty) {
      throw RouterException(
          'This router requires a login. Enter the admin username and password.');
    }
    // Already authenticated on this device? (e.g. logged in via a
    // browser — the ONT treats the whole IP as signed in.) Skip.
    if (await _hasAccess()) return;
    try {
      final page = await _client
          .get(Uri.parse('$_base/admin/login_en.asp'))
          .timeout(_timeout);
      final html = String.fromCharCodes(page.bodyBytes);
      if (page.statusCode != 200) {
        throw RouterException(
            'Router returned HTTP ${page.statusCode} on the login page.');
      }
      final token = _token(html);
      final captcha = loginCaptcha(html);
      final req = http.Request('POST', Uri.parse('$_base/boaform/admin/formLogin_en'))
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/x-www-form-urlencoded'
        ..bodyFields = {
          'username': username,
          'psd': password,
          if (captcha != null) 'verification_code': captcha,
          'csrftoken': token,
        };
      final resp = await _client.send(req).timeout(_timeout);
      final body = String.fromCharCodes(await resp.stream.toBytes());
      if (body.contains('ERROR:')) {
        // "You have logined!" can mean this very device is already signed
        // in — verify before failing.
        if (await _hasAccess()) return;
        throw RouterException(loginError(body));
      }
      // Success = 302 to the home page (or a 200 landing page).
      if (resp.statusCode == 302 ||
          resp.statusCode == 301 ||
          resp.statusCode == 200) {
        return;
      }
      throw RouterException('Router login failed (HTTP ${resp.statusCode}).');
    } on RouterException {
      rethrow;
    } catch (e) {
      throw RouterException(_friendly(e));
    }
  }

  @override
  Future<void> logout() async {}

  // ---------------------------------------------------------------- status

  @override
  Future<RouterStatus> getStatus() async {
    final conn = await _get('/status_net_connet_info_en.asp');
    final internet = _internetUp(parseRows(conn, 'links'));

    final wlan = await _get('/status_wlan_info_11n_en.asp');
    final wifi = _wifiUp(wlan);

    final basic = await _get('/status_device_basic_info_en.asp');
    final title =
        RegExp(r'<TITLE>([^<]+)</TITLE>', caseSensitive: false)
            .firstMatch(basic)
            ?.group(1)
            ?.trim();

    final model = (title == null || title.isEmpty || title.toUpperCase() == 'ONT')
        ? 'Netlink HG323R'
        : 'Netlink $title';

    return RouterStatus(
      wifiUp: wifi,
      internetUp: internet,
      ip: _base.replaceFirst('http://', ''),
      model: model,
    );
  }

  /// True when the WAN service named *INTERNET* reports `strStatus: "up"`
  /// (falls back to any WAN link being up if no INTERNET service exists).
  static bool _internetUp(List<Map<String, String>> links) {
    if (links.isEmpty) return false;
    final wan = links.where(
        (l) => (l['servName'] ?? '').toUpperCase().contains('INTERNET'));
    final pool = wan.isNotEmpty ? wan : links;
    return pool.any((l) => (l['strStatus'] ?? '').toLowerCase() == 'up');
  }

  /// `wlanDisabled[0] = 0` means the radio is on.
  static bool _wifiUp(String html) {
    final m = RegExp(r'wlanDisabled\[0\]\s*=\s*(\w+)').firstMatch(html);
    if (m == null) return true; // page variant without the flag
    final v = m.group(1)!.toLowerCase();
    return v == '0' || v == 'false';
  }

  // --------------------------------------------------------------- devices

  @override
  Future<List<Device>> getConnectedDevices() async {
    final eth = await _get('/status_ethernet_info_en.asp');
    final rows = parseRows(eth, 'clts');
    final rules = await _fetchMacRules(); // to mark blocked devices
    final selfIps = await _localIpv4s(); // so we can label our own device
    final now = DateTime.now();

    return rows.map((r) {
      final ip = r['ipAddr'] ?? '';
      final mac = r['macAddr'] ?? '';
      final lease = int.tryParse(r['liveTime'] ?? '') ?? 0;
      // liveTime = seconds left of the (typically 24 h) DHCP lease,
      // so device age = 86400 - remaining.
      final age = 86400 - lease.clamp(0, 86400);
      final name = (r['devname'] ?? '').trim();
      final lastOctet = ip.isEmpty ? '?' : ip.split('.').last;
      final isSelf = ip.isNotEmpty && selfIps.contains(ip);
      return Device(
        name: name.isEmpty
            ? (isSelf ? 'This phone' : 'Device $lastOctet')
            : name,
        ip: ip,
        mac: mac,
        manufacturer: manufacturerFor(mac) ?? 'Unknown',
        isThisPhone: isSelf,
        online: true,
        blocked: rules.any((m) => _sameMac(m['mac'] ?? '', mac)),
        firstSeen: now.subtract(Duration(seconds: age)),
        lastSeen: now,
      );
    }).toList();
  }

  /// IPv4 addresses assigned to this device (to recognise our own entry
  /// in the router's client list — Android hides the real MAC, but the
  /// IP is enough).
  Future<Set<String>> _localIpv4s() async {
    try {
      final out = <String>{};
      for (final i
          in await NetworkInterface.list(includeLoopback: false, includeLinkLocal: false)) {
        for (final a in i.addresses) {
          if (a.type == InternetAddressType.IPv4) out.add(a.address);
        }
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  // ----------------------------------------------------------- MAC filter

  Future<_MacState> _fetchMacState() async {
    final html = await _get(_macListPage);
    return _MacState(
      token: _token(html),
      enabled: cgiFlag(html, 'macFilterEnble'),
      whitelist: cgiFlag(html, 'excludeMode'),
      rules: parseRows(html, 'rules'),
    );
  }

  Future<List<Map<String, String>>> _fetchMacRules() async =>
      (await _fetchMacState()).rules;

  @override
  Future<List<MacRule>> getMacFilterRules() async {
    final s = await _fetchMacState();
    final type = s.whitelist ? 'whitelist' : 'blacklist';
    return s.rules
        .where((r) => (r['mac'] ?? '').isNotEmpty)
        .map((r) => MacRule(r['mac']!, type))
        .toList();
  }

  @override
  Future<void> addMacBlacklist(String mac) async {
    var s = await _fetchMacState();
    if (s.rules.any((r) => _sameMac(r['mac'] ?? '', mac))) return; // already
    if (!s.enabled) {
      // Rules can only be managed while the filter is on.
      await _post(_macForm, {
        'macFilterEnble': 'on',
        'excludeMode': s.whitelist ? 'on' : 'off',
        'action': 'sw',
        'bcdata': 'le',
        'submit-url': _macListPage,
        'csrftoken': s.token,
      });
      s = await _fetchMacState();
    }
    await _post(_macForm, {
      'mac': dashMac(mac),
      'devname': '',
      'action': 'ad',
      'submit-url': _macListPage,
      'csrftoken': s.token,
    });
    final after = await _fetchMacState();
    if (!after.rules.any((r) => _sameMac(r['mac'] ?? '', mac))) {
      throw RouterException(
          'The router did not accept the rule — it may have reached its 16-rule limit.');
    }
  }

  @override
  Future<void> removeMacBlacklist(String mac) async {
    final s = await _fetchMacState();
    final hits =
        s.rules.where((r) => _sameMac(r['mac'] ?? '', mac)).toList();
    if (hits.isEmpty) return;
    await _post(_macForm, {
      'macFilterEnble': s.enabled ? 'on' : 'off',
      'excludeMode': s.whitelist ? 'on' : 'off',
      'action': 'rm',
      'bcdata': macBcdata(hits),
      'submit-url': _macListPage,
      'csrftoken': s.token,
    });
    final after = await _fetchMacState();
    if (after.rules.any((r) => _sameMac(r['mac'] ?? '', mac))) {
      throw RouterException('The router did not remove the rule.');
    }
  }

  @override
  Future<void> enableMacFilter() => _setMacEnabled(true);

  @override
  Future<void> disableMacFilter() => _setMacEnabled(false);

  Future<void> _setMacEnabled(bool on) async {
    final s = await _fetchMacState();
    if (s.enabled == on) return;
    await _post(_macForm, {
      'macFilterEnble': on ? 'on' : 'off',
      'excludeMode': s.whitelist ? 'on' : 'off',
      'action': 'sw',
      'bcdata': 'le',
      'submit-url': _macListPage,
      'csrftoken': s.token,
    });
    final after = await _fetchMacState();
    if (after.enabled != on) {
      throw RouterException('The router did not change the MAC filter state.');
    }
  }

  // ----------------------------------------------------------- URL filter

  Future<_UrlState> _fetchUrlState() async {
    final html = await _get(_urlListPage);
    return _UrlState(
      token: _token(html),
      enabled: cgiFlag(html, 'urlfilterEnble'),
      whitelist: cgiFlag(html, 'urlFilterMode'),
      rules: parseRows(html, 'rules'),
    );
  }

  @override
  Future<List<UrlRule>> getUrlFilterRules() async {
    final s = await _fetchUrlState();
    return s.rules
        .where((r) => (r['url'] ?? '').isNotEmpty)
        .map((r) => UrlRule(r['url']!))
        .toList();
  }

  @override
  Future<void> addUrlBlock(String domain) async {
    var s = await _fetchUrlState();
    if (s.rules.any((r) =>
        (r['url'] ?? '').toLowerCase() ==
        domain.toLowerCase().replaceAll(RegExp(r'^www\.'), ''))) {
      return; // already blocked
    }
    if (!s.enabled) {
      await _post(_urlForm, {
        'urlfilterEnble': 'on',
        'urlFilterMode': s.whitelist ? 'on' : 'off',
        'action': 'sw',
        'bcdata': 'le',
        'submit-url': _urlListPage,
        'csrftoken': s.token,
      });
      s = await _fetchUrlState();
    }
    await _post(_urlForm, {
      'url': domain,
      'action': 'ad',
      'submit-url': _urlListPage,
      'csrftoken': s.token,
    });
    final after = await _fetchUrlState();
    if (!after.rules.any(
        (r) => (r['url'] ?? '').toLowerCase() == domain.toLowerCase())) {
      throw RouterException(
          'The router did not accept the website — it may have reached its rule limit.');
    }
  }

  @override
  Future<void> removeUrlBlock(String domain) async {
    final s = await _fetchUrlState();
    final idx = s.rules.indexWhere(
        (r) => (r['url'] ?? '').toLowerCase() == domain.toLowerCase());
    if (idx < 0) return;
    await _post(_urlForm, {
      'urlfilterEnble': s.enabled ? 'on' : 'off',
      'urlFilterMode': s.whitelist ? 'on' : 'off',
      'action': 'rm',
      'bcdata': urlBcdata(idx),
      'submit-url': _urlListPage,
      'csrftoken': s.token,
    });
    final after = await _fetchUrlState();
    if (after.rules
        .any((r) => (r['url'] ?? '').toLowerCase() == domain.toLowerCase())) {
      throw RouterException('The router did not remove the website rule.');
    }
  }

  @override
  Future<void> enableUrlFilter() => _setUrlEnabled(true);

  @override
  Future<void> disableUrlFilter() => _setUrlEnabled(false);

  Future<void> _setUrlEnabled(bool on) async {
    final s = await _fetchUrlState();
    if (s.enabled == on) return;
    await _post(_urlForm, {
      'urlfilterEnble': on ? 'on' : 'off',
      'urlFilterMode': s.whitelist ? 'on' : 'off',
      'action': 'sw',
      'bcdata': 'le',
      'submit-url': _urlListPage,
      'csrftoken': s.token,
    });
    final after = await _fetchUrlState();
    if (after.enabled != on) {
      throw RouterException('The router did not change the URL filter state.');
    }
  }
}

class _MacState {
  final String token;
  final bool enabled, whitelist;
  final List<Map<String, String>> rules;
  const _MacState(
      {required this.token,
      required this.enabled,
      required this.whitelist,
      required this.rules});
}

class _UrlState {
  final String token;
  final bool enabled, whitelist;
  final List<Map<String, String>> rules;
  const _UrlState(
      {required this.token,
      required this.enabled,
      required this.whitelist,
      required this.rules});
}
