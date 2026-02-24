import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/sensor_data.dart';
import '../services/websocket_service.dart';

enum RecognitionState {
  idle,
  countdown,
  collecting,  // Continuous collection - predictions arrive asynchronously
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

  // Window-based collection for continuous mode
  int _samplesInCurrentWindow = 0;
  RecognitionState _recognitionState = RecognitionState.idle;
  String? _latestPrediction;
  static const int _windowSize = 200; // 4 seconds at 50Hz
  int _countdown = 0;
  Timer? _countdownTimer;
  Timer? _keepAliveTimer; // Keep WebSocket alive during long predictions
  bool _continuousMode = true; // Enable continuous predictions by default
  bool _fastInference = false; // Enable faster inference with simpler prompts

  // Continuous collection with parallel predictions
  int _currentWindowNumber = 0; // Increments each time a window completes
  int _highestDisplayedWindow = -1; // Track highest displayed to skip stale
  int _pendingPredictions = 0; // Track how many predictions are pending
  StreamSubscription? _windowAckSubscription;
  DateTime? _currentWindowStartTime; // When current window started collecting
  final List<DateTime> _windowStartTimeQueue = []; // FIFO queue of window start times

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
  bool get isWaitingForPrediction => _pendingPredictions > 0;
  bool get isPredictionReceived => _latestPrediction != null;
  bool get continuousMode => _continuousMode;
  bool get fastInference => _fastInference;
  int get pendingPredictions => _pendingPredictions;
  int get currentWindowNumber => _currentWindowNumber;

  // Get and remove the oldest window start time (FIFO - for prediction timestamps)
  // This should be called when a prediction arrives to get the correct corresponding time
  DateTime? consumeOldestWindowStartTime() {
    if (_windowStartTimeQueue.isEmpty) return null;
    return _windowStartTimeQueue.removeAt(0);
  }

  // Peek at the oldest window start time without removing (for display purposes)
  DateTime? getLastCompletedWindowStartTime() {
    if (_windowStartTimeQueue.isEmpty) return null;
    return _windowStartTimeQueue.first;
  }

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
    _currentWindowNumber = 0;
    _highestDisplayedWindow = -1;
    _pendingPredictions = 0;

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

    // Listen for window acknowledgments (continuous collection)
    _windowAckSubscription?.cancel();
    _windowAckSubscription = _websocketService.windowAckStream.listen(
      (ack) {
        print('📬 Window ${ack.windowId} acknowledged by server');
        // Acknowledgment received - window is being processed
      },
    );

    // Listen for predictions from server (may arrive out of order)
    print('🎧 Setting up prediction listener...');
    _predictionSubscription = _websocketService.messageStream.listen(
      (message) {
        try {
          final data = jsonDecode(message);

          if (data['type'] == 'activity_prediction') {
            final activity = data['activity'];
            final windowId = data['window_id'] as String?;

            // Decrement pending count
            if (_pendingPredictions > 0) {
              _pendingPredictions--;
            }

            // Extract window number from windowId (format: "abc12345")
            // For now, just display latest prediction (skip stale ones based on tracking)
            print('📥 Received prediction: $activity (window: $windowId, pending: $_pendingPredictions)');

            // Always show the latest prediction (skip stale check for simplicity)
            _latestPrediction = activity;
            notifyListeners();
          }
        } catch (e) {
          print('❌ Error parsing prediction: $e');
        }
      },
      onError: (error) {
        print('❌ WebSocket stream error: $error');
        _handleWebSocketDisconnect();
      },
      onDone: () {
        print('⚠️ WebSocket stream closed!');
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
      _countdownTimer?.cancel();
      _countdownTimer = null;
      _isCollecting = false;
      _samplesInCurrentWindow = 0;
      _currentWindowNumber = 0;
      _pendingPredictions = 0;
      _highestDisplayedWindow = -1;
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

    // Start keep-alive timer for long predictions
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_pendingPredictions > 0) {
        print('💓 Keep-alive ping ($_pendingPredictions predictions pending)');
        _websocketService.sendPing();
      }
    });

    _subscription = _sensorService.getSensorStream().listen((data) {
      // Track when window starts (BEFORE creating SensorData so first sample has the time)
      if (_currentMessageType == 'predict_activity' && _samplesInCurrentWindow == 0) {
        _currentWindowStartTime = DateTime.now();
      }

      // Always update latestData for chart display
      final labeledData = SensorData(
        timestamp: data.timestamp,
        accelerometer: data.accelerometer,
        gyroscope: data.gyroscope,
        activityLabel: _currentActivityLabel,
        messageType: _currentMessageType,
        fastInference: _fastInference,
        collectionStartTime: _currentWindowStartTime,
      );
      _latestData = labeledData;

      // Send to server (continuous - don't stop)
      _websocketService.sendSensorData(labeledData);
      _packetsSent++;

      if (_currentMessageType == 'predict_activity') {
        _samplesInCurrentWindow++;

        // Check if window is complete
        if (_samplesInCurrentWindow >= _windowSize) {
          // Window complete - increment counter and reset for next window
          _currentWindowNumber++;
          _pendingPredictions++;

          // Store window start time in FIFO queue (will be consumed when prediction arrives)
          if (_currentWindowStartTime != null) {
            _windowStartTimeQueue.add(_currentWindowStartTime!);
          }

          print(
            '✅ Window $_currentWindowNumber complete ($_samplesInCurrentWindow samples). '
            'Started at: $_currentWindowStartTime. Queue size: ${_windowStartTimeQueue.length}. Continuing collection (pending: $_pendingPredictions)',
          );
          _samplesInCurrentWindow = 0;  // Reset for next window
          _currentWindowStartTime = null;  // Reset for next window
          // Don't stop - continue collecting!
        }
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

    _windowAckSubscription?.cancel();
    _windowAckSubscription = null;

    _countdownTimer?.cancel();
    _countdownTimer = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _collectionStartTime = null;
    _samplesInCurrentWindow = 0;
    _currentWindowNumber = 0;
    _pendingPredictions = 0;
    _highestDisplayedWindow = -1;
    _countdown = 0;
    _recognitionState = RecognitionState.idle;
    _latestPrediction = null;
    _currentWindowStartTime = null;
    _windowStartTimeQueue.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _predictionSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _windowAckSubscription?.cancel();
    _countdownTimer?.cancel();
    _keepAliveTimer?.cancel();
    _sensorService.dispose();
    super.dispose();
  }
}
