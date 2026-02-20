import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/activity_provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/sensor_data_provider.dart';
import '../providers/device_info_provider.dart';
import '../models/activity_type.dart';
import '../services/permission_service.dart';

class HomeTabScreen extends StatefulWidget {
  const HomeTabScreen({super.key});

  @override
  State<HomeTabScreen> createState() => _HomeTabScreenState();
}

class _HomeTabScreenState extends State<HomeTabScreen>
    with TickerProviderStateMixin {
  final PermissionService _permissionService = PermissionService();
  late AnimationController _activityAnimationController;
  late AnimationController _cardFlashController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _flashAnimation;
  ActivityType? _previousActivity;
  bool _hasAutoStarted = false;
  bool _hasReceivedFirstPrediction = false;
  int _predictionCount = 0; // Track number of predictions to trigger animation

  // Live chart data - store last 100 points (2 seconds at 50Hz)
  final List<double> _accelX = [];
  final List<double> _accelY = [];
  final List<double> _accelZ = [];
  final List<double> _gyroX = [];
  final List<double> _gyroY = [];
  final List<double> _gyroZ = [];
  static const int _maxDataPoints = 100;
  Timer? _chartDataTimer;
  bool _chartsExpanded = false;
  DateTime? _lastChartDataTimestamp; // Track last added data to avoid duplicates

  @override
  void initState() {
    super.initState();
    _activityAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _activityAnimationController,
        curve: Curves.elasticOut,
      ),
    );

    // Card flash animation
    _cardFlashController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _flashAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _cardFlashController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _activityAnimationController.dispose();
    _cardFlashController.dispose();
    _stopChartDataPolling();
    super.dispose();
  }

  void _addSensorData(Map<String, double> accel, Map<String, double> gyro) {
    setState(() {
      _accelX.add(accel['x']!);
      _accelY.add(accel['y']!);
      _accelZ.add(accel['z']!);
      _gyroX.add(gyro['x']!);
      _gyroY.add(gyro['y']!);
      _gyroZ.add(gyro['z']!);

      if (_accelX.length > _maxDataPoints) {
        _accelX.removeAt(0);
        _accelY.removeAt(0);
        _accelZ.removeAt(0);
        _gyroX.removeAt(0);
        _gyroY.removeAt(0);
        _gyroZ.removeAt(0);
      }

      // Debug: log when data is first added
      if (_accelX.length == 1) {
        print('📈 First chart data point added!');
      }
    });
  }

  void _clearSensorData() {
    setState(() {
      _accelX.clear();
      _accelY.clear();
      _accelZ.clear();
      _gyroX.clear();
      _gyroY.clear();
      _gyroZ.clear();
      _lastChartDataTimestamp = null;
    });
  }

  void _startChartDataPolling() {
    final sensorDataProvider = context.read<SensorDataProvider>();
    final appState = context.read<AppStateProvider>();
    final activityProvider = context.read<ActivityProvider>();

    print('📊 Chart polling started');

    int _pollCount = 0;
    _chartDataTimer = Timer.periodic(Duration(milliseconds: 50), (timer) {
      if (!mounted) return;

      _pollCount++;
      final currentState = sensorDataProvider.recognitionState;
      final latestData = sensorDataProvider.latestData;

      // Log every 40 polls (2 seconds)
      if (_pollCount % 40 == 0) {
        print('📊 Poll #$_pollCount: state=$currentState, hasData=${latestData != null}, chartPoints=${_accelX.length}');
      }

      if (appState.demoModeEnabled) {
        // Demo mode - get mock data
        final mockData = activityProvider.demoService.getMockSensorData();
        _addSensorData(
          mockData['accelerometer']!.cast<String, double>(),
          mockData['gyroscope']!.cast<String, double>(),
        );
      } else if (currentState != RecognitionState.idle) {
        // Real mode - get actual sensor data (any active state except idle)
        // Only add if we have new data (different timestamp)
        if (latestData != null && latestData.timestamp != _lastChartDataTimestamp) {
          _lastChartDataTimestamp = latestData.timestamp;
          _addSensorData(
            {
              'x': latestData.accelerometer.x,
              'y': latestData.accelerometer.y,
              'z': latestData.accelerometer.z,
            },
            {
              'x': latestData.gyroscope.x,
              'y': latestData.gyroscope.y,
              'z': latestData.gyroscope.z,
            },
          );
          // Debug: log chart data count periodically
          if (_accelX.length % 20 == 0) {
            print('📈 Chart data points: ${_accelX.length}, state: $currentState');
          }
        }
      }
    });
  }

  void _stopChartDataPolling() {
    _chartDataTimer?.cancel();
    _chartDataTimer = null;
  }

  Future<void> _toggleRecognition() async {
    print('🔘 HomeTabScreen: _toggleRecognition called');
    final sensorDataProvider = context.read<SensorDataProvider>();
    final activityProvider = context.read<ActivityProvider>();
    final appState = context.read<AppStateProvider>();

    // Check if session is active (any state except idle)
    final isSessionActive =
        sensorDataProvider.recognitionState != RecognitionState.idle;
    print(
      '🔘 HomeTabScreen: isSessionActive=$isSessionActive, recognitionState=${sensorDataProvider.recognitionState}',
    );

    if (!isSessionActive) {
      // Start new session
      print('▶️ HomeTabScreen: Starting new recognition session');
      final hasPermission = await _permissionService.requestSensorPermissions();
      if (!hasPermission) {
        print('❌ HomeTabScreen: No sensor permissions');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sensor permissions are required'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Clear previous sensor data and expand charts
      _clearSensorData();
      setState(() {
        _chartsExpanded = true;
      });

      // Start chart data polling BEFORE connection attempt
      _startChartDataPolling();

      try {
        // Check if in demo mode
        if (appState.demoModeEnabled) {
          print('🎮 HomeTabScreen: Starting in DEMO mode');
          activityProvider.startListening(demoMode: true);
        } else {
          print('🌐 HomeTabScreen: Starting in REAL mode');
          final websocketService = activityProvider.websocketService;
          print('🌐 HomeTabScreen: Connecting to ${appState.websocketUrl}');
          await websocketService.connect(appState.websocketUrl);
          print(
            '🌐 HomeTabScreen: Connected! Starting ActivityProvider listener...',
          );
          activityProvider.startListening();
          print('🌐 HomeTabScreen: Starting SensorDataProvider recognition...');
          sensorDataProvider.startActivityRecognition();
          print('✅ HomeTabScreen: All started successfully');
        }

        await appState.setActivityRecognitionEnabled(true);
      } catch (e) {
        print('❌ HomeTabScreen: Error starting recognition: $e');
        // Keep chart polling running - user can retry connection
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connection failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      // Stop active session - fully disable like settings toggle
      print('⏹️ HomeTabScreen: Fully stopping recognition (disabling)');
      sensorDataProvider.stopCollection();
      activityProvider.stopListening();

      // Stop chart data polling
      _stopChartDataPolling();

      // Disconnect WebSocket if motion capture is also disabled
      if (!appState.motionCaptureEnabled) {
        sensorDataProvider.websocketService.disconnect();
      }

      // Disable activity recognition (same as settings toggle)
      await appState.setActivityRecognitionEnabled(false);
    }
  }

  String _getActivityDescription(ActivityType activity) {
    switch (activity) {
      case ActivityType.running:
        return 'High-intensity movement with fast pace detected';
      case ActivityType.walking:
        return 'Steady movement with moderate pace detected';
      case ActivityType.sitting:
        return 'Minimal movement detected, user at rest';
      case ActivityType.standing:
        return 'Stationary position with slight movements';
      case ActivityType.jumping:
        return 'Vertical movement with high acceleration detected';
      case ActivityType.lying:
        return 'Horizontal position with minimal movement detected';
      case ActivityType.unknown:
        return 'Analyzing movement patterns...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Activity Detected Card
              Consumer3<ActivityProvider, AppStateProvider, SensorDataProvider>(
                builder: (context, activityProvider, appState, sensorDataProvider, _) {
                  final currentActivity = activityProvider.currentActivity;
                  final isEnabled = appState.activityRecognitionEnabled;
                  final recognitionState = sensorDataProvider.recognitionState;
                  final currentPredictionCount =
                      activityProvider.activityHistory.length;

                  // Detect new prediction by checking history count
                  if (currentPredictionCount > _predictionCount &&
                      currentActivity != ActivityType.unknown &&
                      isEnabled) {
                    _predictionCount = currentPredictionCount;
                    if (!_hasReceivedFirstPrediction) {
                      print(
                        '🎊 HomeTabScreen: First prediction received! ${currentActivity.displayName}',
                      );
                      _hasReceivedFirstPrediction = true;
                    } else {
                      print(
                        '🎯 HomeTabScreen: New prediction #$currentPredictionCount received! ${currentActivity.displayName} (${_previousActivity == currentActivity ? "SAME ACTIVITY" : "CHANGED"})',
                      );
                    }
                    // Trigger animations for EVERY prediction (even if same activity)
                    print(
                      '🎬 HomeTabScreen: Triggering bounce and flash animations!',
                    );
                    _activityAnimationController.reset();
                    _activityAnimationController.forward();
                    _cardFlashController.reset();
                    _cardFlashController.forward();
                  }

                  // Reset flags when disabled
                  if (!isEnabled) {
                    _hasReceivedFirstPrediction = false;
                    _predictionCount = 0;
                  }

                  // Show processing state before first prediction (during both collecting and waiting)
                  final isWaitingForFirstPrediction =
                      isEnabled &&
                      !_hasReceivedFirstPrediction &&
                      recognitionState != RecognitionState.idle;

                  _previousActivity = currentActivity;

                  // Auto-start recognition if enabled and not running (only once)
                  if (isEnabled &&
                      recognitionState == RecognitionState.idle &&
                      !_hasAutoStarted) {
                    _hasAutoStarted = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _toggleRecognition();
                    });
                  }

                  // Reset flag when disabled
                  if (!isEnabled && _hasAutoStarted) {
                    _hasAutoStarted = false;
                  }

                  return Stack(
                    children: [
                      AnimatedBuilder(
                        animation: _flashAnimation,
                        builder: (context, child) {
                          // Create flash effect that peaks and fades (0 → 1 → 0)
                          final flashValue = _flashAnimation.value < 0.5
                              ? _flashAnimation.value *
                                    2 // 0 to 1 (first half)
                              : (1 - _flashAnimation.value) *
                                    2; // 1 to 0 (second half)

                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isEnabled
                                    ? [
                                        Color.lerp(
                                          Color(0xFF8B5CF6),
                                          Color(0xFFFFFFFF),
                                          flashValue * 0.4,
                                        )!,
                                        Color.lerp(
                                          Color(0xFF9333EA),
                                          Color(0xFFFFFFFF),
                                          flashValue * 0.4,
                                        )!,
                                      ]
                                    : [Color(0xFF9CA3AF), Color(0xFF6B7280)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isEnabled
                                    ? Color(0xFFC084FC).withValues(alpha: 0.3)
                                    : Color(0xFF9CA3AF).withValues(alpha: 0.3),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                                // Add glow during flash
                                if (flashValue > 0.1)
                                  BoxShadow(
                                    color: Color(
                                      0xFF8B5CF6,
                                    ).withValues(alpha: flashValue * 0.5),
                                    blurRadius: 24 * flashValue,
                                    offset: const Offset(0, 0),
                                  ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Show header when enabled and not in loading state
                                if (isEnabled &&
                                    !isWaitingForFirstPrediction) ...[
                                  // Animate the "Activity Detected" header for each prediction
                                  ScaleTransition(
                                    scale: _scaleAnimation,
                                    child: Row(
                                      children: [
                                        // Show loader when collecting/waiting, sensor icon when prediction received
                                        if (recognitionState ==
                                                RecognitionState.collecting ||
                                            recognitionState ==
                                                RecognitionState
                                                    .waitingForPrediction)
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.white,
                                                  ),
                                            ),
                                          )
                                        else
                                          Icon(
                                            Icons.sensors,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Activity Detected',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                if (isEnabled) ...[
                                  // Show special UI for first prediction (only when processing)
                                  if (isWaitingForFirstPrediction) ...[
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(Colors.white),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              'Processing prediction...',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 32,
                                          ),
                                          child: Text(
                                            'This may take a few seconds',
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.7,
                                              ),
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    // Show activity name (no animation here, animation is on header)
                                    Text(
                                      currentActivity.displayName,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    // Hide description in fast inference mode
                                    if (activityProvider.activityHistory.isEmpty ||
                                        !activityProvider.activityHistory.first.fastInference) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        // Use actual backend reasoning when available (demo mode off)
                                        // Otherwise use mocked description (demo mode on or no reasoning)
                                        appState.demoModeEnabled ||
                                                activityProvider
                                                    .activityHistory
                                                    .isEmpty
                                            ? _getActivityDescription(
                                                currentActivity,
                                              )
                                            : (activityProvider
                                                      .activityHistory
                                                      .first
                                                      .reasoning ??
                                                  _getActivityDescription(
                                                    currentActivity,
                                                  )),
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.8,
                                          ),
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ],
                                ] else ...[
                                  // Disabled state - show with similar layout to active state
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.sensors_off,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                          const SizedBox(width: 12),
                                          Flexible(
                                            child: Text(
                                              'Activity Recognition Disabled',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Tap Start below to enable activity tracking',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.8,
                                          ),
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      // Start button in the disabled card (small style like Stop)
                                      InkWell(
                                        onTap: _toggleRecognition,
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.2,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.4,
                                              ),
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.play_arrow,
                                                size: 16,
                                                color: Colors.white,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Start',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                                const SizedBox(height: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Active Devices',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.75),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.2,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.phone_android,
                                                color: Colors.white,
                                                size: 14,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Phone',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(
                                                Icons.battery_std,
                                                color: Colors.white,
                                                size: 12,
                                              ),
                                              const SizedBox(width: 2),
                                              Consumer<DeviceInfoProvider>(
                                                builder:
                                                    (
                                                      context,
                                                      deviceInfo,
                                                      child,
                                                    ) {
                                                      return Text(
                                                        '${deviceInfo.batteryLevel}%',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                        ),
                                                      );
                                                    },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      // Controls in top-right corner when recognition is active
                      if (isEnabled &&
                          recognitionState != RecognitionState.idle)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Fast Inference Toggle
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    sensorDataProvider.setFastInference(
                                      !sensorDataProvider.fastInference,
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: sensorDataProvider.fastInference
                                          ? Colors.amber.withValues(alpha: 0.3)
                                          : Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: sensorDataProvider.fastInference
                                            ? Colors.amber.withValues(alpha: 0.6)
                                            : Colors.white.withValues(alpha: 0.4),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          sensorDataProvider.fastInference
                                              ? Icons.bolt
                                              : Icons.bolt_outlined,
                                          size: 14,
                                          color: sensorDataProvider.fastInference
                                              ? Colors.amber
                                              : Colors.white,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Fast',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: sensorDataProvider.fastInference
                                                ? Colors.amber
                                                : Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Stop button
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _toggleRecognition,
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.4),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.stop_circle,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Stop',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),

              // Sensor Charts (when activity recognition is running)
              Consumer2<AppStateProvider, SensorDataProvider>(
                builder: (context, appState, sensorDataProvider, _) {
                  final isEnabled = appState.activityRecognitionEnabled;
                  final recognitionState = sensorDataProvider.recognitionState;

                  // Show charts section when recognition is active (any state except idle)
                  if (isEnabled &&
                      (recognitionState != RecognitionState.idle ||
                       appState.demoModeEnabled)) {
                    return Column(
                      children: [
                        const SizedBox(height: 16),
                        // Collapsible header
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Color(0xFFE5E7EB), width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _chartsExpanded = !_chartsExpanded;
                                  });
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.show_chart, color: Color(0xFF8B5CF6), size: 20),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Live Sensor Data',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF111827),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Icon(
                                        _chartsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                        color: Color(0xFF9CA3AF),
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_chartsExpanded) ...[
                                Divider(height: 1, color: Color(0xFFF3F4F6)),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      _buildSensorChart('Accelerometer'),
                                      const SizedBox(height: 16),
                                      _buildSensorChart('Gyroscope'),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),

              // TODO: Uncomment when real stat tracking is implemented
              // const SizedBox(height: 16),

              // // Stats Grid
              // GridView.count(
              //   shrinkWrap: true,
              //   physics: const NeverScrollableScrollPhysics(),
              //   crossAxisCount: 2,
              //   mainAxisSpacing: 12,
              //   crossAxisSpacing: 12,
              //   childAspectRatio: 1.15,
              //   children: [
              //     _buildStatCard(
              //       icon: Icons.directions_walk,
              //       iconColor: Color(0xFF3B82F6),
              //       title: 'Steps',
              //       value: '8,547',
              //       change: '+12% vs yesterday',
              //       changePositive: true,
              //     ),
              //     _buildStatCard(
              //       icon: Icons.local_fire_department,
              //       iconColor: Color(0xFFFF6B00),
              //       title: 'Calories',
              //       value: '520',
              //       unit: 'kcal',
              //       change: '+8% vs yesterday',
              //       changePositive: true,
              //     ),
              //     _buildStatCard(
              //       icon: Icons.access_time,
              //       iconColor: Color(0xFF10B981),
              //       title: 'Active Time',
              //       value: '75',
              //       unit: 'min',
              //       change: '-5% vs yesterday',
              //       changePositive: false,
              //     ),
              //     _buildStatCard(
              //       icon: Icons.favorite,
              //       iconColor: Color(0xFFEF4444),
              //       title: 'Heart Rate',
              //       value: '78',
              //       unit: 'bpm',
              //       change: null,
              //     ),
              //   ],
              // ),

            ],
          ),
        ),
      ),
    );
  }

  // TODO: Uncomment when real stat tracking is implemented
  // Widget _buildStatCard({
  //   required IconData icon,
  //   required Color iconColor,
  //   required String title,
  //   required String value,
  //   String? unit,
  //   String? change,
  //   bool? changePositive,
  // }) {
  //   return Container(
  //     padding: const EdgeInsets.all(16),
  //     decoration: BoxDecoration(
  //       color: Colors.white,
  //       borderRadius: BorderRadius.circular(12),
  //       border: Border.all(color: Color(0xFFE5E7EB), width: 1),
  //       boxShadow: [
  //         BoxShadow(
  //           color: Colors.black.withOpacity(0.05),
  //           blurRadius: 4,
  //           offset: const Offset(0, 1),
  //         ),
  //       ],
  //     ),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //       children: [
  //         Container(
  //           padding: const EdgeInsets.all(10),
  //           decoration: BoxDecoration(
  //             color: iconColor,
  //             borderRadius: BorderRadius.circular(8),
  //           ),
  //           child: Icon(icon, color: Colors.white, size: 20),
  //         ),
  //         Column(
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           children: [
  //             Text(
  //               title,
  //               style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
  //             ),
  //             const SizedBox(height: 4),
  //             Row(
  //               crossAxisAlignment: CrossAxisAlignment.baseline,
  //               textBaseline: TextBaseline.alphabetic,
  //               children: [
  //                 Flexible(
  //                   child: Text(
  //                     value,
  //                     style: TextStyle(
  //                       fontSize: 24,
  //                       fontWeight: FontWeight.w600,
  //                       color: Color(0xFF111827),
  //                     ),
  //                     overflow: TextOverflow.ellipsis,
  //                   ),
  //                 ),
  //                 if (unit != null) ...[
  //                   const SizedBox(width: 4),
  //                   Text(
  //                     unit,
  //                     style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
  //                   ),
  //                 ],
  //               ],
  //             ),
  //             if (change != null) ...[
  //               const SizedBox(height: 4),
  //               Text(
  //                 change,
  //                 style: TextStyle(
  //                   fontSize: 12,
  //                   color: changePositive == true
  //                       ? Color(0xFF059669)
  //                       : Color(0xFFDC2626),
  //                 ),
  //                 overflow: TextOverflow.ellipsis,
  //               ),
  //             ],
  //           ],
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildSensorChart(String name) {
    List<double> xData, yData, zData;
    double minY, maxY;

    if (name == 'Accelerometer') {
      xData = _accelX;
      yData = _accelY;
      zData = _accelZ;
      minY = -12.0;
      maxY = 12.0;
    } else {
      xData = _gyroX;
      yData = _gyroY;
      zData = _gyroZ;
      minY = -12.0;
      maxY = 12.0;
    }

    List<FlSpot> xSpots = [];
    List<FlSpot> ySpots = [];
    List<FlSpot> zSpots = [];

    for (int i = 0; i < xData.length; i++) {
      xSpots.add(FlSpot(i.toDouble(), xData[i]));
      ySpots.add(FlSpot(i.toDouble(), yData[i]));
      zSpots.add(FlSpot(i.toDouble(), zData[i]));
    }

    if (xSpots.isEmpty || xSpots.length < 10) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: Center(
                child: Text(
                  'Waiting for data...',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: xSpots,
                    isCurved: false,
                    color: Color(0xFF8B5CF6),
                    barWidth: 2,
                    dotData: FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: ySpots,
                    isCurved: false,
                    color: Color(0xFF10B981),
                    barWidth: 2,
                    dotData: FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: zSpots,
                    isCurved: false,
                    color: Color(0xFF3B82F6),
                    barWidth: 2,
                    dotData: FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegend('X', Color(0xFF8B5CF6)),
              const SizedBox(width: 16),
              _buildLegend('Y', Color(0xFF10B981)),
              const SizedBox(width: 16),
              _buildLegend('Z', Color(0xFF3B82F6)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
