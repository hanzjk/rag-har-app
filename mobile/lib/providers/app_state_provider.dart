import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../services/websocket_service.dart' as ws;

class AppStateProvider extends ChangeNotifier {
  String _websocketUrl = AppConstants.defaultWebSocketUrl;
  ws.ConnectionState _connectionState = ws.ConnectionState.disconnected;
  bool _activityRecognitionEnabled = false; // Disabled by default
  bool _motionCaptureEnabled = false;

  String get websocketUrl => _websocketUrl;
  ws.ConnectionState get connectionState => _connectionState;
  bool get activityRecognitionEnabled => _activityRecognitionEnabled;
  bool get motionCaptureEnabled => _motionCaptureEnabled;

  AppStateProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _websocketUrl =
        prefs.getString(AppConstants.webSocketUrlKey) ?? AppConstants.defaultWebSocketUrl;
    _activityRecognitionEnabled = prefs.getBool('activity_recognition_enabled') ?? false;
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

  Future<void> setActivityRecognitionEnabled(bool enabled) async {
    _activityRecognitionEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('activity_recognition_enabled', enabled);
    notifyListeners();
  }

  void setMotionCaptureEnabled(bool enabled) {
    _motionCaptureEnabled = enabled;
    notifyListeners();
  }
}
