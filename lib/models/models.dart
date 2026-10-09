class Device {
  final String name, ip, mac, manufacturer;
  final bool online, isThisPhone;
  final bool blocked;
  final DateTime firstSeen, lastSeen;
  const Device({required this.name, required this.ip, required this.mac, this.manufacturer = 'Unknown',
      this.online = true, this.blocked = false, this.isThisPhone = false, required this.firstSeen, required this.lastSeen});
  Device copyWith({bool? blocked, String? name}) => Device(name: name ?? this.name, ip: ip, mac: mac,
      manufacturer: manufacturer, online: online, blocked: blocked ?? this.blocked, isThisPhone: isThisPhone,
      firstSeen: firstSeen, lastSeen: lastSeen);
}

class MacRule { final String mac; final String type; const MacRule(this.mac, [this.type = 'blacklist']); }
class UrlRule { final String domain; const UrlRule(this.domain); }
class RouterStatus {
  final bool wifiUp, internetUp; final String ip, model;
  const RouterStatus({required this.wifiUp, required this.internetUp, required this.ip, required this.model});
}
class ActivityLog { final String type, text; final DateTime time; ActivityLog(this.type, this.text) : time = DateTime.now(); }
