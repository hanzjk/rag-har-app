import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> requestSensorPermissions() async {
    // On Android, sensor permissions (accelerometer, gyroscope, magnetometer)
    // are "normal" permissions and don't require runtime requests.
    // They are automatically granted at install time.
    if (Platform.isAndroid) {
      return true;
    }

    // For iOS or other platforms, check sensor permission
    final status = await Permission.sensors.status;

    if (status.isGranted) {
      return true;
    }

    if (status.isDenied) {
      final result = await Permission.sensors.request();
      return result.isGranted;
    }

    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    return false;
  }

  Future<bool> checkPermissions() async {
    // On Android, sensors are always available
    if (Platform.isAndroid) {
      return true;
    }

    final status = await Permission.sensors.status;
    return status.isGranted;
  }
}
