import 'package:sensors_plus/sensors_plus.dart';

class SensorData {
  final DateTime timestamp;
  final SensorReading accelerometer;
  final SensorReading gyroscope;
  final SensorReading magnetometer;
  final String? activityLabel;
  final String messageType;
  final String? subjectId;

  SensorData({
    required this.timestamp,
    required this.accelerometer,
    required this.gyroscope,
    required this.magnetometer,
    this.activityLabel,
    this.messageType = 'sensor_data',
    this.subjectId = 'subject0',
  });

  factory SensorData.fromSensorEvents({
    required AccelerometerEvent accelerometerEvent,
    required GyroscopeEvent gyroscopeEvent,
    required MagnetometerEvent magnetometerEvent,
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
      magnetometer: SensorReading(
        x: magnetometerEvent.x,
        y: magnetometerEvent.y,
        z: magnetometerEvent.z,
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
        'magnetometer': magnetometer.toJson(),
      }
    };

    if (activityLabel != null) {
      json['activity'] = activityLabel!;
    }

    if (subjectId != null) {
      json['subject_id'] = subjectId!;
    }

    return json;
  }
}

class SensorReading {
  final double x;
  final double y;
  final double z;

  SensorReading({
    required this.x,
    required this.y,
    required this.z,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'z': z,
      };
}
