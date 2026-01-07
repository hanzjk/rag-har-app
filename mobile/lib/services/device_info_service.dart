import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;

/// Service for monitoring device information and battery status
class DeviceInfoService {
  final Battery _battery = Battery();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  int _currentBatteryLevel = 100;
  String _deviceName = 'Unknown Device';
  String _deviceModel = 'Unknown Model';
  BatteryState _batteryState = BatteryState.full;

  StreamSubscription<BatteryState>? _batteryStateSubscription;

  /// Get current battery level (0-100)
  int get batteryLevel => _currentBatteryLevel;

  /// Get device name
  String get deviceName => _deviceName;

  /// Get device model
  String get deviceModel => _deviceModel;

  /// Get battery state (charging, discharging, etc.)
  BatteryState get batteryState => _batteryState;

  /// Check if device is charging
  bool get isCharging =>
      _batteryState == BatteryState.charging ||
      _batteryState == BatteryState.full;

  /// Initialize device info and battery monitoring
  Future<void> initialize() async {
    // Get device information
    await _loadDeviceInfo();

    // Get initial battery level
    _currentBatteryLevel = await _battery.batteryLevel;

    // Get initial battery state
    _batteryState = await _battery.batteryState;

    // Listen to battery state changes
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((state) {
      _batteryState = state;
    });
  }

  /// Load device information (name, model, etc.)
  Future<void> _loadDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        _deviceModel = androidInfo.model;
        _deviceName = '${androidInfo.manufacturer} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        _deviceModel = iosInfo.model;
        _deviceName = '${iosInfo.name} (${iosInfo.model})';
      } else {
        _deviceName = 'Unknown Device';
        _deviceModel = 'Unknown Model';
      }
    } catch (e) {
      print('Error loading device info: $e');
      _deviceName = 'Unknown Device';
      _deviceModel = 'Unknown Model';
    }
  }

  /// Refresh battery level
  Future<void> refreshBatteryLevel() async {
    try {
      _currentBatteryLevel = await _battery.batteryLevel;
    } catch (e) {
      print('Error refreshing battery level: $e');
    }
  }

  /// Start periodic battery monitoring
  /// Updates battery level every [intervalSeconds] seconds
  Stream<int> monitorBatteryLevel({int intervalSeconds = 30}) async* {
    while (true) {
      await refreshBatteryLevel();
      yield _currentBatteryLevel;
      await Future.delayed(Duration(seconds: intervalSeconds));
    }
  }

  /// Dispose resources
  void dispose() {
    _batteryStateSubscription?.cancel();
  }
}
