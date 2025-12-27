import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/activity_type.dart';
import '../services/websocket_service.dart';
import '../config/constants.dart';

class ActivityProvider extends ChangeNotifier {
  final WebSocketService _websocketService;

  ActivityType _currentActivity = ActivityType.unknown;
  final List<ActivityPrediction> _activityHistory = [];
  StreamSubscription<ActivityPrediction>? _subscription;

  ActivityType get currentActivity => _currentActivity;
  List<ActivityPrediction> get activityHistory => List.unmodifiable(_activityHistory);
  WebSocketService get websocketService => _websocketService;

  ActivityProvider({required WebSocketService websocketService})
      : _websocketService = websocketService;

  void startListening() {
    _subscription = _websocketService.activityStream.listen((prediction) {
      _currentActivity = prediction.activity;

      _activityHistory.insert(0, prediction);

      if (_activityHistory.length > AppConstants.maxActivityHistory) {
        _activityHistory.removeLast();
      }

      notifyListeners();
    });
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _currentActivity = ActivityType.unknown;
    notifyListeners();
  }

  void clearHistory() {
    _activityHistory.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
