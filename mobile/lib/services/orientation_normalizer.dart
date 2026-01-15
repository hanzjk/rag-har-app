import 'dart:math' as math;
import '../models/sensor_data.dart';

/// Normalizes sensor data to world frame (orientation-independent)
/// Uses gravity vector to rotate device coordinates to world coordinates
///
/// World frame convention:
/// - Z-axis: Points UP (opposite to gravity)
/// - X-axis: Horizontal, device's original X projected onto horizontal plane
/// - Y-axis: Horizontal, completes right-hand coordinate system
class OrientationNormalizer {
  // Low-pass filter constant for gravity estimation
  static const double _alpha = 0.8;

  // Gravity estimate in device coordinates
  double _gravityX = 0.0;
  double _gravityY = 0.0;
  double _gravityZ = 9.81;

  bool _isInitialized = false;

  /// Normalize sensor data to world frame
  /// Returns a new SensorData object with world-frame coordinates
  SensorData normalize(SensorData raw) {
    // Update gravity estimate using low-pass filter
    if (!_isInitialized) {
      _gravityX = raw.accelerometer.x;
      _gravityY = raw.accelerometer.y;
      _gravityZ = raw.accelerometer.z;
      _isInitialized = true;
    } else {
      _gravityX = _alpha * _gravityX + (1 - _alpha) * raw.accelerometer.x;
      _gravityY = _alpha * _gravityY + (1 - _alpha) * raw.accelerometer.y;
      _gravityZ = _alpha * _gravityZ + (1 - _alpha) * raw.accelerometer.z;
    }

    // Compute rotation matrix from device frame to world frame
    final rotationMatrix = _computeRotationMatrix();

    // Rotate accelerometer to world frame
    final accelWorld = _rotateVector(
      raw.accelerometer.x,
      raw.accelerometer.y,
      raw.accelerometer.z,
      rotationMatrix,
    );

    // Rotate gyroscope to world frame
    final gyroWorld = _rotateVector(
      raw.gyroscope.x,
      raw.gyroscope.y,
      raw.gyroscope.z,
      rotationMatrix,
    );

    return SensorData(
      timestamp: raw.timestamp,
      accelerometer: SensorReading(
        x: accelWorld[0],
        y: accelWorld[1],
        z: accelWorld[2],
      ),
      gyroscope: SensorReading(
        x: gyroWorld[0],
        y: gyroWorld[1],
        z: gyroWorld[2],
      ),
      activityLabel: raw.activityLabel,
      messageType: raw.messageType,
      subjectId: raw.subjectId,
    );
  }

  /// Compute rotation matrix that transforms device coordinates to world coordinates
  /// World Z-axis points UP (opposite to gravity)
  List<List<double>> _computeRotationMatrix() {
    // Normalize gravity vector
    final gMag = math.sqrt(
      _gravityX * _gravityX + _gravityY * _gravityY + _gravityZ * _gravityZ,
    );

    if (gMag < 0.1) {
      // Near-zero gravity (free fall) - return identity matrix
      return [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
      ];
    }

    // Normalized gravity (points DOWN in device frame)
    final gx = _gravityX / gMag;
    final gy = _gravityY / gMag;
    final gz = _gravityZ / gMag;

    // World Z-axis in device coordinates (points UP, opposite to gravity)
    final zx = -gx;
    final zy = -gy;
    final zz = -gz;

    // Choose a reference vector for X-axis
    // Use device X-axis [1,0,0] and project onto horizontal plane
    // X_world = X_device - (X_device · Z_world) * Z_world
    double xx = 1.0 - zx * zx;
    double xy = -zx * zy;
    double xz = -zx * zz;

    // Normalize X-axis
    double xMag = math.sqrt(xx * xx + xy * xy + xz * xz);

    if (xMag < 0.001) {
      // Device X-axis is parallel to gravity, use device Y-axis instead
      xx = -zy * zx;
      xy = 1.0 - zy * zy;
      xz = -zy * zz;
      xMag = math.sqrt(xx * xx + xy * xy + xz * xz);
    }

    xx /= xMag;
    xy /= xMag;
    xz /= xMag;

    // Y-axis = Z × X (cross product for right-handed system)
    final yx = zy * xz - zz * xy;
    final yy = zz * xx - zx * xz;
    final yz = zx * xy - zy * xx;

    // Rotation matrix: rows are world axes expressed in device coordinates
    // To transform device vector to world: R * v_device = v_world
    return [
      [xx, xy, xz], // X_world in device frame
      [yx, yy, yz], // Y_world in device frame
      [zx, zy, zz], // Z_world in device frame
    ];
  }

  /// Rotate a vector using rotation matrix
  List<double> _rotateVector(
    double x,
    double y,
    double z,
    List<List<double>> R,
  ) {
    return [
      R[0][0] * x + R[0][1] * y + R[0][2] * z,
      R[1][0] * x + R[1][1] * y + R[1][2] * z,
      R[2][0] * x + R[2][1] * y + R[2][2] * z,
    ];
  }

  /// Reset the gravity estimate (call when starting new session)
  void reset() {
    _gravityX = 0.0;
    _gravityY = 0.0;
    _gravityZ = 9.81;
    _isInitialized = false;
  }

  /// Get current gravity vector estimate
  SensorReading get gravityEstimate =>
      SensorReading(x: _gravityX, y: _gravityY, z: _gravityZ);
}
