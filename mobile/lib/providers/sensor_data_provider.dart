import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/sensor_data.dart';
import '../services/websocket_service.dart';

class SensorDataProvider extends ChangeNotifier {
  final dynamic _sensorService;
  final WebSocketService _websocketService;

  SensorData? _latestData;
  bool _isCollecting = false;
  int _packetsSent = 0;
  DateTime? _collectionStartTime;
  StreamSubscription<SensorData>? _subscription;
  String? _currentActivityLabel;
  String _currentMessageType = 'sensor_data';

  SensorData? get latestData => _latestData;
  bool get isCollecting => _isCollecting;
  int get packetsSent => _packetsSent;
  DateTime? get collectionStartTime => _collectionStartTime;
  dynamic get sensorService => _sensorService;
  WebSocketService get websocketService => _websocketService;
  String? get currentActivityLabel => _currentActivityLabel;

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
    startCollection();
  }

  void startCollection() {
    if (_isCollecting) return;

    _isCollecting = true;
    _packetsSent = 0;
    _collectionStartTime = DateTime.now();
    notifyListeners();

    _subscription = _sensorService.getSensorStream().listen((data) {
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
      notifyListeners();
    });
  }

  void stopCollection() {
    if (!_isCollecting) return;

    _isCollecting = false;
    _subscription?.cancel();
    _subscription = null;
    _collectionStartTime = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _sensorService.dispose();
    super.dispose();
  }
}
