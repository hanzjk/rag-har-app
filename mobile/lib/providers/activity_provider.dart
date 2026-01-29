import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/activity_type.dart';
import '../services/websocket_service.dart';
import '../services/demo_service.dart';
import '../config/constants.dart';

const String _historyKey = 'activity_history';

class ActivityProvider extends ChangeNotifier {
  final WebSocketService _websocketService;
  final DemoService _demoService = DemoService();

  ActivityType _currentActivity = ActivityType.unknown;
  final List<ActivityPrediction> _activityHistory = [];
  StreamSubscription<ActivityPrediction>? _subscription;
  bool _isDemoMode = false;
  bool _isInitialized = false;

  ActivityType get currentActivity => _currentActivity;
  List<ActivityPrediction> get activityHistory => List.unmodifiable(_activityHistory);
  WebSocketService get websocketService => _websocketService;
  DemoService get demoService => _demoService;
  bool get isListening => _subscription != null;

  ActivityProvider({required WebSocketService websocketService})
      : _websocketService = websocketService {
    _loadHistory();
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

  void startListening({bool demoMode = false}) {
    print('🎬 ActivityProvider.startListening called (demoMode: $demoMode)');

    // Stop any existing subscription first
    if (_subscription != null) {
      print('⚠️ ActivityProvider: Cancelling existing subscription before starting new one');
      _subscription?.cancel();
      _subscription = null;
    }

    _isDemoMode = demoMode;
    _currentActivity = ActivityType.unknown;
    notifyListeners();

    if (demoMode) {
      // Use demo service
      _demoService.startMockPredictions();
      _subscription = _demoService.predictionStream.listen((prediction) {
        _currentActivity = prediction.activity;

        _activityHistory.insert(0, prediction);

        if (_activityHistory.length > AppConstants.maxActivityHistory) {
          _activityHistory.removeLast();
        }

        _saveHistory(); // Persist to storage
        notifyListeners();
      });
    } else {
      // Use real websocket service
      print('🎧 ActivityProvider: Starting to listen to activityStream...');
      _subscription = _websocketService.activityStream.listen((prediction) {
        print('🎉 ActivityProvider: Received prediction - ${prediction.activity.displayName}');
        _currentActivity = prediction.activity;

        _activityHistory.insert(0, prediction);

        if (_activityHistory.length > AppConstants.maxActivityHistory) {
          _activityHistory.removeLast();
        }

        _saveHistory(); // Persist to storage
        print('📢 ActivityProvider: Notifying listeners (activity: ${_currentActivity.displayName})');
        notifyListeners();
      });
      print('✅ ActivityProvider: Subscription set up');
    }
  }

  void stopListening() {
    print('🛑 ActivityProvider.stopListening called');
    _subscription?.cancel();
    _subscription = null;

    if (_isDemoMode) {
      _demoService.stopMockPredictions();
    }

    _currentActivity = ActivityType.unknown;
    _isDemoMode = false;
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
    _demoService.dispose();
    super.dispose();
  }
}
