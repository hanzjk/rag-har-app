import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/activity_type.dart';
import '../services/websocket_service.dart';
import '../services/demo_service.dart';
import '../config/constants.dart';

class ActivityProvider extends ChangeNotifier {
  final WebSocketService _websocketService;
  final DemoService _demoService = DemoService();

  ActivityType _currentActivity = ActivityType.unknown;
  final List<ActivityPrediction> _activityHistory = [];
  StreamSubscription<ActivityPrediction>? _subscription;
  bool _isDemoMode = false;

  ActivityType get currentActivity => _currentActivity;
  List<ActivityPrediction> get activityHistory => List.unmodifiable(_activityHistory);
  WebSocketService get websocketService => _websocketService;
  DemoService get demoService => _demoService;
  bool get isListening => _subscription != null;

  ActivityProvider({required WebSocketService websocketService})
      : _websocketService = websocketService;

  void startListening({bool demoMode = false}) {
    print('🎬 ActivityProvider.startListening called (demoMode: $demoMode)');

    // Stop any existing subscription first
    if (_subscription != null) {
      print('⚠️ ActivityProvider: Cancelling existing subscription before starting new one');
      _subscription?.cancel();
      _subscription = null;
    }

    _isDemoMode = demoMode;

    // Clear previous history when starting new session
    _activityHistory.clear();
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

  void clearHistory() {
    _activityHistory.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _demoService.dispose();
    super.dispose();
  }
}
