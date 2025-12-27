import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../services/websocket_service.dart' as ws;

class AppStateProvider extends ChangeNotifier {
  String _websocketUrl = AppConstants.defaultWebSocketUrl;
  ws.ConnectionState _connectionState = ws.ConnectionState.disconnected;

  String get websocketUrl => _websocketUrl;
  ws.ConnectionState get connectionState => _connectionState;

  AppStateProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _websocketUrl =
        prefs.getString(AppConstants.webSocketUrlKey) ?? AppConstants.defaultWebSocketUrl;
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
}
