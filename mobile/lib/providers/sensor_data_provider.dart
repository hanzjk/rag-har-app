import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/sensor_data.dart';
import '../services/websocket_service.dart';

enum RecognitionState {
  idle,
  countdown,
  collecting,
  waitingForPrediction,
  predictionReceived,
}

class SensorDataProvider extends ChangeNotifier {
  final dynamic _sensorService;
  final WebSocketService _websocketService;

  SensorData? _latestData;
  bool _isCollecting = false;
  int _packetsSent = 0;
  DateTime? _collectionStartTime;
  StreamSubscription<SensorData>? _subscription;
  StreamSubscription? _predictionSubscription;
  StreamSubscription<int>? _demoCollectionSubscription;
  String? _currentActivityLabel;
  String _currentMessageType = 'sensor_data';
  bool _isDemoMode = false;

  // Window-based collection for manual continuation
  int _samplesInCurrentWindow = 0;
  RecognitionState _recognitionState = RecognitionState.idle;
  String? _latestPrediction;
  static const int _windowSize = 200; // 4 seconds at 50Hz
  int _countdown = 0;
  Timer? _countdownTimer;

  SensorData? get latestData => _latestData;
  bool get isCollecting => _isCollecting;
  int get packetsSent => _packetsSent;
  DateTime? get collectionStartTime => _collectionStartTime;
  dynamic get sensorService => _sensorService;
  WebSocketService get websocketService => _websocketService;
  String? get currentActivityLabel => _currentActivityLabel;
  int get samplesInCurrentWindow => _samplesInCurrentWindow;
  RecognitionState get recognitionState => _recognitionState;
  String? get latestPrediction => _latestPrediction;
  int get windowSize => _windowSize;
  int get countdown => _countdown;

  // Convenience getters for UI
  bool get isWaitingForPrediction => _recognitionState == RecognitionState.waitingForPrediction;
  bool get isPredictionReceived => _recognitionState == RecognitionState.predictionReceived;

  Duration get collectionDuration {
    if (_collectionStartTime == null) return Duration.zero;
    return DateTime.now().difference(_collectionStartTime!);
  }

  SensorDataProvider({
    required dynamic sensorService,
    required WebSocketService websocketService,
  })  : _sensorService = sensorService,
        _websocketService = websocketService;

  void setActivityLabel(String? label) {
    _currentActivityLabel = label;
    notifyListeners();
  }

  void startDataCollection() {
    _currentMessageType = 'collect_data';
    startCollection();
  }

  void startActivityRecognition() {
    _currentMessageType = 'predict_activity';
    _recognitionState = RecognitionState.idle;

    // Listen for predictions from server
    _predictionSubscription = _websocketService.messageStream.listen((message) {
      try {
        final data = jsonDecode(message);

        if (data['type'] == 'activity_prediction') {
          final activity = data['activity'];
          print('📥 Received prediction: $activity');

          // Update state to show prediction received
          _latestPrediction = activity;
          _recognitionState = RecognitionState.predictionReceived;
          _isCollecting = false;

          notifyListeners();
        }
      } catch (e) {
        print('Error parsing prediction: $e');
      }
    });

    collectNextWindow();
  }

  void collectNextWindow() {
    print('🔄 Starting countdown before collection');

    // IMPORTANT: Stop sensor service to prevent data collection during countdown
    _subscription?.cancel();
    _subscription = null;
    _sensorService.stopStreaming(); // Clean up old timers and subscriptions
    _isCollecting = false;

    _samplesInCurrentWindow = 0;
    _latestPrediction = null;
    _countdown = 3;
    _recognitionState = RecognitionState.countdown;

    // Notify immediately so UI shows countdown
    notifyListeners();

    // Start countdown timer (3, 2, 1, GO!)
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        _countdown--;
        print('⏱️ Countdown: $_countdown');
        notifyListeners();
      } else {
        // Countdown finished, start collection
        timer.cancel();
        _countdownTimer = null;
        _recognitionState = RecognitionState.collecting;
        print('🚀 GO! Starting data collection');
        notifyListeners();
        startCollection();
      }
    });
  }

  void startCollection() {
    if (_isCollecting) return;

    _isCollecting = true;
    _packetsSent = 0;
    _collectionStartTime = DateTime.now();
    notifyListeners();

    _subscription = _sensorService.getSensorStream().listen((data) {
      // For activity recognition mode, stop after window size
      if (_currentMessageType == 'predict_activity' &&
          _samplesInCurrentWindow >= _windowSize) {
        // Only transition to waiting state if not already waiting or received
        if (_recognitionState == RecognitionState.collecting) {
          print('✅ Window complete ($_samplesInCurrentWindow samples). Waiting for prediction...');
          _recognitionState = RecognitionState.waitingForPrediction;
          _isCollecting = false;
          notifyListeners();
        }
        // Don't process more data once window is complete
        return;
      }

      // Create new SensorData with activity label and message type
      final labeledData = SensorData(
        timestamp: data.timestamp,
        accelerometer: data.accelerometer,
        gyroscope: data.gyroscope,
        magnetometer: data.magnetometer,
        activityLabel: _currentActivityLabel,
        messageType: _currentMessageType,
      );

      _latestData = labeledData;
      _websocketService.sendSensorData(labeledData);
      _packetsSent++;

      if (_currentMessageType == 'predict_activity') {
        _samplesInCurrentWindow++;
        print('📊 Sample ${_samplesInCurrentWindow}/$_windowSize sent');
      }

      notifyListeners();
    });
  }

  void stopCollection() {
    _isCollecting = false;
    _subscription?.cancel();
    _subscription = null;
    _sensorService.stopStreaming(); // Clean up sensor service
    _predictionSubscription?.cancel();
    _predictionSubscription = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _collectionStartTime = null;
    _samplesInCurrentWindow = 0;
    _countdown = 0;
    _recognitionState = RecognitionState.idle;
    _latestPrediction = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _predictionSubscription?.cancel();
    _countdownTimer?.cancel();
    _sensorService.dispose();
    super.dispose();
  }
}
