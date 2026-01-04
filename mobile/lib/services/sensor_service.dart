import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/sensor_data.dart';
import '../config/constants.dart';

class SensorService {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamController<SensorData>? _sensorDataController;

  AccelerometerEvent? _latestAccelerometer;
  GyroscopeEvent? _latestGyroscope;
  MagnetometerEvent? _latestMagnetometer;

  Timer? _samplingTimer;
  final int samplingRateHz;
  bool _isStreaming = false;

  SensorService({
    this.samplingRateHz = AppConstants.defaultSamplingRateHz,
  });

  Stream<SensorData> getSensorStream() {
    // Clean up any existing stream first to prevent multiple timers
    if (_isStreaming) {
      stopStreaming();
    }

    _sensorDataController = StreamController<SensorData>.broadcast();
    _isStreaming = true;

    print('========================================');
    print('Starting real sensor data collection at ${samplingRateHz}Hz');
    print('========================================');

    // Subscribe to real sensor streams
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      _latestAccelerometer = event;
    });

    _gyroscopeSubscription = gyroscopeEventStream().listen((event) {
      _latestGyroscope = event;
    });

    _magnetometerSubscription = magnetometerEventStream().listen((event) {
      _latestMagnetometer = event;
    });

    // Sample at specified rate
    final intervalMs = (1000 / samplingRateHz).round();
    _samplingTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) {
        if (_latestAccelerometer != null &&
            _latestGyroscope != null &&
            _latestMagnetometer != null) {
          final sensorData = SensorData.fromSensorEvents(
            accelerometerEvent: _latestAccelerometer!,
            gyroscopeEvent: _latestGyroscope!,
            magnetometerEvent: _latestMagnetometer!,
          );
          _sensorDataController?.add(sensorData);
        }
      },
    );

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
    _magnetometerSubscription?.cancel();
    _magnetometerSubscription = null;
    _sensorDataController?.close();
    _sensorDataController = null;
    _isStreaming = false;
  }

  void dispose() {
    stopStreaming();
  }
}
