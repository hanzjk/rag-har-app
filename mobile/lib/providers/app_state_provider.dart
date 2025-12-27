import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../services/websocket_service.dart' as ws;

class AppStateProvider extends ChangeNotifier {
  String _websocketUrl = AppConstants.defaultWebSocketUrl;
  ws.ConnectionState _connectionState = ws.ConnectionState.disconnected;
  bool _isDemoMode = false;

  String get websocketUrl => _websocketUrl;
  ws.ConnectionState get connectionState => _connectionState;
  bool get isDemoMode => _isDemoMode;

  AppStateProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _websocketUrl =
        prefs.getString(AppConstants.webSocketUrlKey) ?? AppConstants.defaultWebSocketUrl;
    _isDemoMode = prefs.getBool('demo_mode') ?? false;
    notifyListeners();
  }

  Future<void> setWebSocketUrl(String url) async {
    _websocketUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.webSocketUrlKey, url);
    notifyListeners();
  }

  void setConnectionState(ws.ConnectionState state) {
    _connectionState = state;
    notifyListeners();
  }

  Future<void> setDemoMode(bool enabled) async {
    _isDemoMode = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('demo_mode', enabled);
    notifyListeners();
  }
}
