import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/sensor_data.dart';
import '../config/constants.dart';
import 'orientation_normalizer.dart';

class SensorService {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamController<SensorData>? _sensorDataController;

  AccelerometerEvent? _latestAccelerometer;
  GyroscopeEvent? _latestGyroscope;

  Timer? _samplingTimer;
  final int samplingRateHz;
  bool _isStreaming = false;

  // Orientation normalization
  final OrientationNormalizer _normalizer = OrientationNormalizer();
  bool _normalizeOrientation;

  SensorService({
    this.samplingRateHz = AppConstants.defaultSamplingRateHz,
    bool normalizeOrientation = true,
  }) : _normalizeOrientation = normalizeOrientation;

  Stream<SensorData> getSensorStream() {
    // Clean up any existing stream first to prevent multiple timers
    if (_isStreaming) {
      stopStreaming();
    }

    _sensorDataController = StreamController<SensorData>.broadcast();
    _isStreaming = true;

    // Reset normalizer for new session
    _normalizer.reset();

    print('========================================');
    print('Starting real sensor data collection at ${samplingRateHz}Hz');
    print(
      'Orientation normalization: ${_normalizeOrientation ? "ENABLED" : "DISABLED"}',
    );
    print('========================================');

    // Subscribe to real sensor streams
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      _latestAccelerometer = event;
    });

    _gyroscopeSubscription = gyroscopeEventStream().listen((event) {
      _latestGyroscope = event;
    });

    // Sample at specified rate
    final intervalMs = (1000 / samplingRateHz).round();
    _samplingTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (_latestAccelerometer != null && _latestGyroscope != null) {
        var sensorData = SensorData.fromSensorEvents(
          accelerometerEvent: _latestAccelerometer!,
          gyroscopeEvent: _latestGyroscope!,
        );

        // Apply orientation normalization if enabled
        if (_normalizeOrientation) {
          sensorData = _normalizer.normalize(sensorData);
        }

        _sensorDataController?.add(sensorData);
      }
    });

    return _sensorDataController!.stream;
  }

  void stopStreaming() {
    print('Stopping sensor streaming...');
    _samplingTimer?.cancel();
    _samplingTimer = null;
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _gyroscopeSubscription?.cancel();
    _gyroscopeSubscription = null;
    _sensorDataController?.close();
    _sensorDataController = null;
    _isStreaming = false;
    _normalizer.reset();
  }

  /// Enable or disable orientation normalization
  void setNormalization(bool enabled) {
    _normalizeOrientation = enabled;
    if (enabled) {
      _normalizer.reset();
    }
  }

  /// Check if normalization is enabled
  bool get isNormalizationEnabled => _normalizeOrientation;

  void dispose() {
    stopStreaming();
  }
}
