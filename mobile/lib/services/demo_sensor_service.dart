import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/sensor_data.dart';
import '../models/activity_type.dart';
import '../config/constants.dart';

class DemoSensorService {
  StreamController<SensorData>? _sensorDataController;
  Timer? _samplingTimer;
  final int samplingRateHz;

  ActivityType _currentActivity = ActivityType.walking;
  int _sampleCount = 0;
  final Random _random = Random();

  DemoSensorService({this.samplingRateHz = AppConstants.defaultSamplingRateHz});

  void setActivity(ActivityType activity) {
    _currentActivity = activity;
  }

  Stream<SensorData> getSensorStream() {
    _sensorDataController = StreamController<SensorData>.broadcast();

    final intervalMs = (1000 / samplingRateHz).round();
    _samplingTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) {
        final sensorData = _generateSensorData();
        _sensorDataController?.add(sensorData);
        _sampleCount++;
      },
    );

    return _sensorDataController!.stream;
  }

  SensorData _generateSensorData() {
    final time = _sampleCount / samplingRateHz;

    // Generate sensor data based on activity type
    final AccelerometerEvent accel;
    final GyroscopeEvent gyro;
    final MagnetometerEvent mag;

    switch (_currentActivity) {
      case ActivityType.walking:
        accel = _generateWalkingAccelerometer(time);
        gyro = _generateWalkingGyroscope(time);
        mag = _generateMagnetometer(time, 0.1);
        break;
      case ActivityType.running:
        accel = _generateRunningAccelerometer(time);
        gyro = _generateRunningGyroscope(time);
        mag = _generateMagnetometer(time, 0.2);
        break;
      case ActivityType.sitting:
        accel = _generateSittingAccelerometer(time);
        gyro = _generateSittingGyroscope(time);
        mag = _generateMagnetometer(time, 0.05);
        break;
      case ActivityType.standing:
        accel = _generateStandingAccelerometer(time);
        gyro = _generateStandingGyroscope(time);
        mag = _generateMagnetometer(time, 0.08);
        break;
      case ActivityType.unknown:
        accel = _generateStandingAccelerometer(time);
        gyro = _generateStandingGyroscope(time);
        mag = _generateMagnetometer(time, 0.05);
        break;
    }

    return SensorData.fromSensorEvents(
      accelerometerEvent: accel,
      gyroscopeEvent: gyro,
      magnetometerEvent: mag,
    );
  }

  // Walking: 2 Hz gait cycle, moderate amplitude
  AccelerometerEvent _generateWalkingAccelerometer(double time) {
    final frequency = 2.0; // 2 Hz walking frequency
    final amplitude = 2.5;

    return AccelerometerEvent(
      _noise(0.3) + sin(2 * pi * frequency * time) * amplitude,
      9.81 + sin(2 * pi * frequency * time + pi / 2) * amplitude * 1.5,
      _noise(0.3) + cos(2 * pi * frequency * time) * amplitude * 0.8,
      DateTime.now(),
    );
  }

  GyroscopeEvent _generateWalkingGyroscope(double time) {
    final frequency = 2.0;

    return GyroscopeEvent(
      _noise(0.05) + sin(2 * pi * frequency * time) * 0.3,
      _noise(0.05) + cos(2 * pi * frequency * time) * 0.2,
      _noise(0.05) + sin(2 * pi * frequency * time + pi / 4) * 0.1,
      DateTime.now(),
    );
  }

  // Running: 3 Hz gait cycle, higher amplitude
  AccelerometerEvent _generateRunningAccelerometer(double time) {
    final frequency = 3.0; // 3 Hz running frequency
    final amplitude = 4.5;

    return AccelerometerEvent(
      _noise(0.5) + sin(2 * pi * frequency * time) * amplitude,
      9.81 + sin(2 * pi * frequency * time + pi / 2) * amplitude * 2.0,
      _noise(0.5) + cos(2 * pi * frequency * time) * amplitude * 1.2,
      DateTime.now(),
    );
  }

  GyroscopeEvent _generateRunningGyroscope(double time) {
    final frequency = 3.0;

    return GyroscopeEvent(
      _noise(0.1) + sin(2 * pi * frequency * time) * 0.5,
      _noise(0.1) + cos(2 * pi * frequency * time) * 0.4,
      _noise(0.1) + sin(2 * pi * frequency * time + pi / 4) * 0.2,
      DateTime.now(),
    );
  }

  // Sitting: minimal movement, mostly gravity
  AccelerometerEvent _generateSittingAccelerometer(double time) {
    return AccelerometerEvent(
      _noise(0.1),
      9.81 + _noise(0.1),
      _noise(0.1),
      DateTime.now(),
    );
  }

  GyroscopeEvent _generateSittingGyroscope(double time) {
    return GyroscopeEvent(
      _noise(0.02),
      _noise(0.02),
      _noise(0.02),
      DateTime.now(),
    );
  }

  // Standing: very minimal movement
  AccelerometerEvent _generateStandingAccelerometer(double time) {
    final microMovement = sin(2 * pi * 0.5 * time) * 0.2; // 0.5 Hz breathing/swaying

    return AccelerometerEvent(
      _noise(0.15) + microMovement,
      9.81 + _noise(0.15),
      _noise(0.15),
      DateTime.now(),
    );
  }

  GyroscopeEvent _generateStandingGyroscope(double time) {
    return GyroscopeEvent(
      _noise(0.03),
      _noise(0.03),
      _noise(0.03),
      DateTime.now(),
    );
  }

  // Magnetometer: relatively stable with small variations
  MagnetometerEvent _generateMagnetometer(double time, double variance) {
    return MagnetometerEvent(
      25.0 + _noise(variance),
      -15.0 + _noise(variance),
      40.0 + _noise(variance),
      DateTime.now(),
    );
  }

  // Generate random noise
  double _noise(double amplitude) {
    return (_random.nextDouble() - 0.5) * 2 * amplitude;
  }

  void dispose() {
    _samplingTimer?.cancel();
    _sensorDataController?.close();
  }
}
