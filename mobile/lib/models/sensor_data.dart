import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math' as math;

class SensorData {
  final DateTime timestamp;
  final SensorReading accelerometer;
  final SensorReading gyroscope;
  final String? activityLabel;
  final String messageType;
  final String? subjectId;
  final bool fastInference;

  SensorData({
    required this.timestamp,
    required this.accelerometer,
    required this.gyroscope,
    this.activityLabel,
    this.messageType = 'sensor_data',
    this.subjectId = 'subject0',
    this.fastInference = false,
  });

  factory SensorData.fromSensorEvents({
    required AccelerometerEvent accelerometerEvent,
    required GyroscopeEvent gyroscopeEvent,
  }) {
    return SensorData(
      timestamp: DateTime.now(),
      accelerometer: SensorReading(
        x: accelerometerEvent.x,
        y: accelerometerEvent.y,
        z: accelerometerEvent.z,
      ),
      gyroscope: SensorReading(
        x: gyroscopeEvent.x,
        y: gyroscopeEvent.y,
        z: gyroscopeEvent.z,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    final json = {
      'type': messageType,
      'timestamp': timestamp.toIso8601String(),
      'data': {
        'accelerometer': accelerometer.toJson(),
        'gyroscope': gyroscope.toJson(),
      },
    };

    if (activityLabel != null) {
      json['activity'] = activityLabel!;
    }

    if (subjectId != null) {
      json['subject_id'] = subjectId!;
    }

    if (fastInference) {
      json['fast_inference'] = true;
    }

    return json;
  }
}

class SensorReading {
  final double x;
  final double y;
  final double z;

  SensorReading({required this.x, required this.y, required this.z});

  /// Calculate magnitude (orientation-independent measure)
  double get magnitude => _calculateMagnitude(x, y, z);

  static double _calculateMagnitude(double x, double y, double z) {
    return math.sqrt(x * x + y * y + z * z);
  }

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'z': z,
    'magnitude': magnitude,
  };
}
