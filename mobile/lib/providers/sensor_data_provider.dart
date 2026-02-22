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
  StreamSubscription? _connectionStateSubscription;
  String? _currentActivityLabel;
  String _currentMessageType = 'sensor_data';

  // Window-based collection for manual continuation
  int _samplesInCurrentWindow = 0;
  RecognitionState _recognitionState = RecognitionState.idle;
  String? _latestPrediction;
  static const int _windowSize = 200; // 4 seconds at 50Hz
  int _countdown = 0;
  Timer? _countdownTimer;
  Timer? _autoContinueTimer;
  Timer? _keepAliveTimer; // Keep WebSocket alive during long predictions
  Timer? _predictionTimeoutTimer; // Timeout for prediction response
  bool _continuousMode = true; // Enable continuous predictions by default
  bool _fastInference = false; // Enable faster inference with simpler prompts
  static const Duration _predictionTimeout = Duration(seconds: 60); // Max wait for prediction

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
  bool get isWaitingForPrediction =>
      _recognitionState == RecognitionState.waitingForPrediction;
  bool get isPredictionReceived =>
      _recognitionState == RecognitionState.predictionReceived;
  bool get continuousMode => _continuousMode;
  bool get fastInference => _fastInference;

  Duration get collectionDuration {
    if (_collectionStartTime == null) return Duration.zero;
    return DateTime.now().difference(_collectionStartTime!);
  }

  SensorDataProvider({
    required dynamic sensorService,
    required WebSocketService websocketService,
  }) : _sensorService = sensorService,
       _websocketService = websocketService;

  void setActivityLabel(String? label) {
    _currentActivityLabel = label;
    notifyListeners();
  }

  void setContinuousMode(bool enabled) {
    _continuousMode = enabled;
    notifyListeners();
  }

  void setFastInference(bool enabled) {
    _fastInference = enabled;
    notifyListeners();
  }

  void startDataCollection() {
    _currentMessageType = 'collect_data';
    startCollection();
  }

  void startActivityRecognition() {
    _currentMessageType = 'predict_activity';
    _recognitionState = RecognitionState.idle;

    // Listen for connection state changes to handle disconnection
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = _websocketService.connectionStateStream.listen(
      (state) {
        print('🔌 Connection state changed to $state');
        if (state == ConnectionState.disconnected || state == ConnectionState.error) {
          _handleWebSocketDisconnect();
        } else if (state == ConnectionState.reconnecting) {
          // Pause collection during reconnection but don't reset state
          print('🔄 Connection reconnecting - pausing collection');
          _subscription?.cancel();
          _subscription = null;
          _sensorService.stopStreaming();
          _isCollecting = false;
          notifyListeners();
        } else if (state == ConnectionState.connected) {
          // Resume if we were collecting when connection dropped
          if (_recognitionState == RecognitionState.collecting && !_isCollecting) {
            print('🔄 Connection restored - resuming collection');
            startCollection();
          }
        }
      },
    );

    // Listen for predictions from server
    print('🎧 Setting up prediction listener...');
    _predictionSubscription = _websocketService.messageStream.listen(
      (message) {
        print(
          '📨 Raw WebSocket message received: ${message.substring(0, message.length > 100 ? 100 : message.length)}...',
        );
        try {
          final data = jsonDecode(message);
          print('📦 Parsed message type: ${data['type']}');

          if (data['type'] == 'activity_prediction') {
            final activity = data['activity'];
            print('📥 Received prediction: $activity');

            // IMMEDIATELY stop sensor collection when prediction arrives
            print('🛑 Stopping sensor collection (prediction received)');
            _subscription?.cancel();
            _subscription = null;
            _sensorService.stopStreaming();

            // Cancel timers - prediction received
            _keepAliveTimer?.cancel();
            _keepAliveTimer = null;
            _predictionTimeoutTimer?.cancel();
            _predictionTimeoutTimer = null;

            // Update state to show prediction received
            _latestPrediction = activity;
            _recognitionState = RecognitionState.predictionReceived;
            _isCollecting = false;

            notifyListeners();

            // If continuous mode is enabled, automatically start next window after 4 seconds
            if (_continuousMode) {
              print('🔄 Continuous mode: Starting next window in 4 seconds...');
              _autoContinueTimer?.cancel();
              _autoContinueTimer = Timer(const Duration(seconds: 4), () {
                if (_recognitionState == RecognitionState.predictionReceived) {
                  print('🔄 Auto-continuing to next window (no countdown)');
                  collectNextWindow();
                }
              });
            }
          }
        } catch (e) {
          print('❌ Error parsing prediction: $e');
          print('❌ Message was: $message');
        }
      },
      onError: (error) {
        print('❌ WebSocket stream error: $error');
        // Reset state on error to avoid being stuck
        _handleWebSocketDisconnect();
      },
      onDone: () {
        print('⚠️ WebSocket stream closed!');
        // Reset state when connection closes to avoid being stuck in waitingForPrediction
        _handleWebSocketDisconnect();
      },
    );

    // Start with 5-second countdown
    _startCollectionWithCountdown();
  }

  void _startCollectionWithCountdown() {
    print('⏱️ Starting 5-second countdown...');
    _recognitionState = RecognitionState.countdown;
    _countdown = 5;
    notifyListeners();

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _countdown--;
      notifyListeners();

      if (_countdown <= 0) {
        timer.cancel();
        _countdownTimer = null;
        print('🚀 Countdown complete, starting collection');
        collectNextWindow();
      }
    });
  }

  void resumeRecognition() {
    // Resume from idle state with countdown
    if (_recognitionState == RecognitionState.idle) {
      _startCollectionWithCountdown();
    }
  }

  void _handleWebSocketDisconnect() {
    // Only reset if we're in an active state (not already idle)
    if (_recognitionState != RecognitionState.idle) {
      print('🔌 WebSocket disconnected - resetting to idle state');
      _subscription?.cancel();
      _subscription = null;
      _sensorService.stopStreaming();
      _keepAliveTimer?.cancel();
      _keepAliveTimer = null;
      _predictionTimeoutTimer?.cancel();
      _predictionTimeoutTimer = null;
      _autoContinueTimer?.cancel();
      _autoContinueTimer = null;
      _countdownTimer?.cancel();
      _countdownTimer = null;
      _isCollecting = false;
      _samplesInCurrentWindow = 0;
      _recognitionState = RecognitionState.idle;
      notifyListeners();
    }
  }

  void collectNextWindow() {
    print('🔄 Starting next collection window');

    // Stop sensor service to clean up
    _subscription?.cancel();
    _subscription = null;
    _sensorService.stopStreaming(); // Clean up old timers and subscriptions
    _isCollecting = false;

    _samplesInCurrentWindow = 0;
    _latestPrediction = null;
    _recognitionState = RecognitionState.collecting;

    // Notify and start collection immediately (no countdown)
    notifyListeners();
    print('🚀 Starting data collection');
    startCollection();
  }

  void startCollection() {
    if (_isCollecting) return;

    _isCollecting = true;
    _packetsSent = 0;
    _collectionStartTime = DateTime.now();
    notifyListeners();

    _subscription = _sensorService.getSensorStream().listen((data) {
      // Always update latestData for chart display
      final labeledData = SensorData(
        timestamp: data.timestamp,
        accelerometer: data.accelerometer,
        gyroscope: data.gyroscope,
        activityLabel: _currentActivityLabel,
        messageType: _currentMessageType,
        fastInference: _fastInference,
      );
      _latestData = labeledData;

      // For activity recognition mode, check if window is complete
      if (_currentMessageType == 'predict_activity' &&
          _samplesInCurrentWindow >= _windowSize) {
        // Only transition to waiting state if not already waiting or received
        if (_recognitionState == RecognitionState.collecting) {
          print(
            '✅ Window complete ($_samplesInCurrentWindow samples). Waiting for prediction...',
          );
          _recognitionState = RecognitionState.waitingForPrediction;
          _isCollecting = false;

          // Start keep-alive timer to prevent connection timeout during long RAG predictions
          _keepAliveTimer?.cancel();
          _keepAliveTimer = Timer.periodic(const Duration(seconds: 3), (_) {
            if (_recognitionState == RecognitionState.waitingForPrediction) {
              print('💓 Keep-alive ping (waiting for prediction)');
              // Send a ping message to keep connection alive
              _websocketService.sendPing();
            }
          });

          // Start prediction timeout timer
          _predictionTimeoutTimer?.cancel();
          _predictionTimeoutTimer = Timer(_predictionTimeout, () {
            if (_recognitionState == RecognitionState.waitingForPrediction) {
              print('⏰ Prediction timeout - no response in ${_predictionTimeout.inSeconds}s');
              // Reset and allow retry
              _keepAliveTimer?.cancel();
              _keepAliveTimer = null;
              _recognitionState = RecognitionState.idle;
              _samplesInCurrentWindow = 0;
              notifyListeners();
            }
          });
        }
        // Don't send to server, just notify for chart updates
        notifyListeners();
        return;
      }

      // Send to server only during active collection
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
    print('🛑 Stopping collection...');
    _isCollecting = false;
    _subscription?.cancel();
    _subscription = null;
    _sensorService.stopStreaming(); // Clean up sensor service

    if (_predictionSubscription != null) {
      print('🔇 Cancelling prediction subscription');
      _predictionSubscription?.cancel();
      _predictionSubscription = null;
    }

    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    _countdownTimer?.cancel();
    _countdownTimer = null;
    _autoContinueTimer?.cancel();
    _autoContinueTimer = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _predictionTimeoutTimer?.cancel();
    _predictionTimeoutTimer = null;
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
    _connectionStateSubscription?.cancel();
    _countdownTimer?.cancel();
    _autoContinueTimer?.cancel();
    _keepAliveTimer?.cancel();
    _predictionTimeoutTimer?.cancel();
    _sensorService.dispose();
    super.dispose();
  }
}
