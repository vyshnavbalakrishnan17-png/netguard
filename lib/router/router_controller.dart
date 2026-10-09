import '../models/models.dart';

class RouterException implements Exception {
  final String message; const RouterException(this.message);
  @override String toString() => message;
}

abstract class RouterController {
  static const macLimit = 16, urlLimit = 100;
  Future<void> connect(String ip);
  Future<void> login(String username, String password);
  Future<void> logout();
  Future<RouterStatus> getStatus();
  Future<List<Device>> getConnectedDevices();
  Future<List<MacRule>> getMacFilterRules();
  Future<void> addMacBlacklist(String mac);
  Future<void> removeMacBlacklist(String mac);
  Future<List<UrlRule>> getUrlFilterRules();
  Future<void> addUrlBlock(String domain);
  Future<void> removeUrlBlock(String domain);
  Future<void> enableMacFilter();
  Future<void> disableMacFilter();
  Future<void> enableUrlFilter();
  Future<void> disableUrlFilter();
}
