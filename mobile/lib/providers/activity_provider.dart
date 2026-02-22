import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/activity_type.dart';
import '../services/websocket_service.dart';
import '../config/constants.dart';

const String _historyKey = 'activity_history';

class ActivityProvider extends ChangeNotifier {
  final WebSocketService _websocketService;

  ActivityType _currentActivity = ActivityType.unknown;
  final List<ActivityPrediction> _activityHistory = [];
  StreamSubscription<ActivityPrediction>? _subscription;
  bool _isInitialized = false;

  ActivityType get currentActivity => _currentActivity;
  List<ActivityPrediction> get activityHistory => List.unmodifiable(_activityHistory);
  WebSocketService get websocketService => _websocketService;
  bool get isListening => _subscription != null;

  // Callback to get sensor data when prediction arrives
  List<SensorSnapshot> Function()? _sensorDataCallback;

  ActivityProvider({required WebSocketService websocketService})
      : _websocketService = websocketService {
    _loadHistory();
  }

  // Set callback to capture sensor data when predictions arrive
  void setSensorDataCallback(List<SensorSnapshot> Function()? callback) {
    _sensorDataCallback = callback;
  }

  // Load history from shared_preferences
  Future<void> _loadHistory() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_historyKey);

      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _activityHistory.clear();
        _activityHistory.addAll(
          jsonList.map((json) => ActivityPrediction.fromJson(json)).toList(),
        );
        notifyListeners();
      }
    } catch (e) {
      print('Error loading activity history: $e');
    }

    _isInitialized = true;
  }

  // Save history to shared_preferences
  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _activityHistory.map((p) => p.toJson()).toList();
      await prefs.setString(_historyKey, jsonEncode(jsonList));
    } catch (e) {
      print('Error saving activity history: $e');
    }
  }

  void startListening() {
    print('🎬 ActivityProvider.startListening called');

    // Stop any existing subscription first
    if (_subscription != null) {
      print('⚠️ ActivityProvider: Cancelling existing subscription before starting new one');
      _subscription?.cancel();
      _subscription = null;
    }

    _currentActivity = ActivityType.unknown;
    notifyListeners();

    // Use real websocket service
    print('🎧 ActivityProvider: Starting to listen to activityStream...');
    _subscription = _websocketService.activityStream.listen((prediction) {
      print('🎉 ActivityProvider: Received prediction - ${prediction.activity.displayName}');
      _currentActivity = prediction.activity;

      // Capture sensor data if callback is set
      List<SensorSnapshot>? sensorData;
      if (_sensorDataCallback != null) {
        sensorData = _sensorDataCallback!();
      }

      // Create prediction with sensor data
      final predictionWithSensor = ActivityPrediction(
        activity: prediction.activity,
        timestamp: prediction.timestamp,
        reasoning: prediction.reasoning,
        fastInference: prediction.fastInference,
        sensorData: sensorData,
      );

      _activityHistory.insert(0, predictionWithSensor);

      if (_activityHistory.length > AppConstants.maxActivityHistory) {
        _activityHistory.removeLast();
      }

      _saveHistory(); // Persist to storage
      print('📢 ActivityProvider: Notifying listeners (activity: ${_currentActivity.displayName})');
      notifyListeners();
    });
    print('✅ ActivityProvider: Subscription set up');
  }

  void stopListening() {
    print('🛑 ActivityProvider.stopListening called');
    _subscription?.cancel();
    _subscription = null;

    _currentActivity = ActivityType.unknown;
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _activityHistory.clear();

    // Clear from storage
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
    } catch (e) {
      print('Error clearing activity history: $e');
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
