final _mac = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$');
bool isValidMac(String s) => _mac.hasMatch(s.trim());
String normalizeMac(String s) => s.trim().toUpperCase().replaceAll('-', ':');

/// Returns bare domain (e.g. "facebook.com") or null if invalid.
String? normalizeDomain(String input) {
  var s = input.trim().toLowerCase();
  s = s.replaceFirst(RegExp(r'^[a-z]+://'), '');
  s = s.split(RegExp(r'[/?#]')).first;
  if (s.startsWith('www.')) s = s.substring(4);
  final ok = RegExp(r'^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$');
  return ok.hasMatch(s) ? s : null;
}
