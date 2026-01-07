import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:battery_plus/battery_plus.dart';
import '../services/device_info_service.dart';

/// Provider for device information and battery status
class DeviceInfoProvider extends ChangeNotifier {
  final DeviceInfoService _deviceInfoService = DeviceInfoService();

  int _batteryLevel = 100;
  String _deviceName = 'Loading...';
  String _deviceModel = 'Unknown';
  BatteryState _batteryState = BatteryState.full;
  bool _isInitialized = false;

  StreamSubscription<int>? _batteryMonitorSubscription;

  /// Get current battery level (0-100)
  int get batteryLevel => _batteryLevel;

  /// Get device name
  String get deviceName => _deviceName;

  /// Get device model
  String get deviceModel => _deviceModel;

  /// Get battery state
  BatteryState get batteryState => _batteryState;

  /// Check if device is charging
  bool get isCharging => _deviceInfoService.isCharging;

  /// Check if provider is initialized
  bool get isInitialized => _isInitialized;

  DeviceInfoProvider() {
    _initialize();
  }

  /// Initialize device info and start battery monitoring
  Future<void> _initialize() async {
    try {
      await _deviceInfoService.initialize();

      _batteryLevel = _deviceInfoService.batteryLevel;
      _deviceName = _deviceInfoService.deviceName;
      _deviceModel = _deviceInfoService.deviceModel;
      _batteryState = _deviceInfoService.batteryState;

      _isInitialized = true;
      notifyListeners();

      // Start monitoring battery level (update every 30 seconds)
      _batteryMonitorSubscription =
          _deviceInfoService.monitorBatteryLevel(intervalSeconds: 30).listen(
        (level) {
          _batteryLevel = level;
          _batteryState = _deviceInfoService.batteryState;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('Error initializing device info provider: $e');
      _deviceName = 'Unknown Device';
      _isInitialized = false;
    }
  }

  /// Manually refresh battery level
  Future<void> refresh() async {
    await _deviceInfoService.refreshBatteryLevel();
    _batteryLevel = _deviceInfoService.batteryLevel;
    _batteryState = _deviceInfoService.batteryState;
    notifyListeners();
  }

  @override
  void dispose() {
    _batteryMonitorSubscription?.cancel();
    _deviceInfoService.dispose();
    super.dispose();
  }
}
