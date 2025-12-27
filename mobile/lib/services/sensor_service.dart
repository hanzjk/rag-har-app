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

  SensorService({this.samplingRateHz = AppConstants.defaultSamplingRateHz});

  Stream<SensorData> getSensorStream() {
    _sensorDataController = StreamController<SensorData>.broadcast();

    _accelerometerSubscription =
        accelerometerEventStream().listen((event) {
      _latestAccelerometer = event;
    });

    _gyroscopeSubscription = gyroscopeEventStream().listen((event) {
      _latestGyroscope = event;
    });

    _magnetometerSubscription = magnetometerEventStream().listen((event) {
      _latestMagnetometer = event;
    });

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

  void dispose() {
    _samplingTimer?.cancel();
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _sensorDataController?.close();
  }
}
