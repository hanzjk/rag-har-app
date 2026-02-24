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
import '../services/websocket_service.dart';

class HomeTabScreen extends StatefulWidget {
  const HomeTabScreen({super.key});

  @override
  State<HomeTabScreen> createState() => _HomeTabScreenState();
}

class _HomeTabScreenState extends State<HomeTabScreen> with SingleTickerProviderStateMixin {
  final PermissionService _permissionService = PermissionService();
  bool _hasAutoStarted = false;

  // Live badge blink animation
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  // Live chart data - store last 100 points (2 seconds at 50Hz)
  final List<double> _accelX = [];
  final List<double> _accelY = [];
  final List<double> _accelZ = [];
  final List<double> _gyroX = [];
  final List<double> _gyroY = [];
  final List<double> _gyroZ = [];
  static const int _maxDataPoints = 100;
  Timer? _chartDataTimer;
  bool _chartsExpanded = true;
  DateTime? _lastChartDataTimestamp; // Track last added data to avoid duplicates

  // Collection window markers - track start/end positions for visual indicators
  final List<int> _collectionStartMarkers = []; // Chart indices where collection started
  final List<int> _collectionEndMarkers = []; // Chart indices where collection ended
  int _totalDataPointsAdded = 0; // Running count to calculate relative positions
  RecognitionState? _previousRecognitionState;
  int _previousWindowNumber = 0; // Track window number to detect window completion

  // Next prediction countdown timer
  Timer? _nextPredictionTimer;
  int _nextPredictionCountdown = 0;

  // Processing time tracker
  Timer? _processingTimer;
  int _processingSeconds = 0;

  // Activity Detected text visibility (shows for 2 seconds after new prediction)
  bool _showActivityDetected = false;
  Timer? _activityDetectedTimer;

  // Track last prediction timestamp to detect new predictions
  DateTime? _lastPredictionTimestamp;

  // Flag to prevent adding duplicate listeners
  bool _activityListenerAdded = false;

  // Store reference to provider to avoid looking it up after dispose
  ActivityProvider? _activityProviderRef;

  @override
  void initState() {
    super.initState();
    // Initialize blink animation for Live badge
    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _blinkAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(_blinkController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for new predictions from ActivityProvider (only add once)
    if (!_activityListenerAdded) {
      _activityProviderRef = Provider.of<ActivityProvider>(context, listen: false);
      _activityProviderRef!.addListener(_onActivityProviderChanged);
      _activityListenerAdded = true;
    }
  }

  void _onActivityProviderChanged() {
    // Check if widget is still mounted before accessing state
    if (!mounted || _activityProviderRef == null) return;

    if (_activityProviderRef!.activityHistory.isNotEmpty) {
      final latestPrediction = _activityProviderRef!.activityHistory.first;
      // Check if this is a new prediction by comparing timestamps
      if (_lastPredictionTimestamp == null ||
          latestPrediction.timestamp != _lastPredictionTimestamp) {
        _lastPredictionTimestamp = latestPrediction.timestamp;
        print('🎬 HomeTabScreen: New prediction detected via listener! ${latestPrediction.activity.displayName}');
        _showActivityDetectedText();
        _startNextPredictionCountdown();
      }
    }
  }

  @override
  void dispose() {
    // Remove listener using stored reference
    _activityProviderRef?.removeListener(_onActivityProviderChanged);
    _activityProviderRef = null;
    _blinkController.dispose();
    _stopChartDataPolling();
    _stopNextPredictionCountdown();
    _stopProcessingTimer();
    _stopActivityDetectedTimer();
    super.dispose();
  }

  void _startNextPredictionCountdown() {
    if (!mounted) return;
    _stopNextPredictionCountdown();
    // Set initial value and trigger rebuild immediately
    setState(() {
      _nextPredictionCountdown = 4;
    });
    _nextPredictionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _nextPredictionCountdown--;
        if (_nextPredictionCountdown <= 0) {
          timer.cancel();
          _nextPredictionTimer = null;
        }
      });
    });
  }

  void _stopNextPredictionCountdown() {
    _nextPredictionTimer?.cancel();
    _nextPredictionTimer = null;
    _nextPredictionCountdown = 0;
  }

  void _showActivityDetectedText() {
    if (!mounted) return;
    _activityDetectedTimer?.cancel();
    setState(() {
      _showActivityDetected = true;
    });
    _activityDetectedTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _showActivityDetected = false;
      });
    });
  }

  void _stopActivityDetectedTimer() {
    _activityDetectedTimer?.cancel();
    _activityDetectedTimer = null;
    _showActivityDetected = false;
  }

  void _startProcessingTimer() {
    _stopProcessingTimer();
    _processingSeconds = 0;
    _processingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _processingSeconds++;
      });
    });
  }

  void _stopProcessingTimer() {
    _processingTimer?.cancel();
    _processingTimer = null;
    _processingSeconds = 0;
  }

  void _addSensorData(Map<String, double> accel, Map<String, double> gyro) {
    setState(() {
      _accelX.add(accel['x']!);
      _accelY.add(accel['y']!);
      _accelZ.add(accel['z']!);
      _gyroX.add(gyro['x']!);
      _gyroY.add(gyro['y']!);
      _gyroZ.add(gyro['z']!);
      _totalDataPointsAdded++;

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
      _collectionStartMarkers.clear();
      _collectionEndMarkers.clear();
      _totalDataPointsAdded = 0;
      _previousRecognitionState = null;
      _previousWindowNumber = 0;
    });
  }

  // Get current sensor data as snapshots for storing with predictions
  List<SensorSnapshot> _getSensorSnapshots() {
    final snapshots = <SensorSnapshot>[];
    final length = _accelX.length;
    for (int i = 0; i < length; i++) {
      snapshots.add(SensorSnapshot(
        accelX: _accelX[i],
        accelY: _accelY[i],
        accelZ: _accelZ[i],
        gyroX: i < _gyroX.length ? _gyroX[i] : 0.0,
        gyroY: i < _gyroY.length ? _gyroY[i] : 0.0,
        gyroZ: i < _gyroZ.length ? _gyroZ[i] : 0.0,
      ));
    }
    return snapshots;
  }

  void _startChartDataPolling() {
    // Cancel any existing timer first to prevent multiple timers
    _stopChartDataPolling();

    final sensorDataProvider = context.read<SensorDataProvider>();

    print('📊 Chart polling started');

    int pollCount = 0;
    _chartDataTimer = Timer.periodic(Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      pollCount++;
      final currentState = sensorDataProvider.recognitionState;
      final latestData = sensorDataProvider.latestData;

      // Detect state transitions for collection markers
      if (_previousRecognitionState != currentState) {
        // Started collecting - add start marker
        if (currentState == RecognitionState.collecting) {
          setState(() {
            _collectionStartMarkers.add(_totalDataPointsAdded);
            _previousWindowNumber = sensorDataProvider.currentWindowNumber;
          });
        }
        // Stopped collecting - add end marker (when going to idle)
        if (_previousRecognitionState == RecognitionState.collecting &&
            currentState == RecognitionState.idle) {
          setState(() {
            _collectionEndMarkers.add(_totalDataPointsAdded);
          });
        }
        _previousRecognitionState = currentState;
      }

      // Detect window completion during continuous collection
      final currentWindowNumber = sensorDataProvider.currentWindowNumber;
      if (currentState == RecognitionState.collecting &&
          currentWindowNumber > _previousWindowNumber) {
        // Window completed - add end marker for old window, start marker for new window
        setState(() {
          _collectionEndMarkers.add(_totalDataPointsAdded);
          _collectionStartMarkers.add(_totalDataPointsAdded);
        });
        _previousWindowNumber = currentWindowNumber;
      }

      // Log every 40 polls (2 seconds)
      if (pollCount % 40 == 0) {
        print('📊 Poll #$pollCount: state=$currentState, hasData=${latestData != null}, chartPoints=${_accelX.length}');
      }

      if (currentState == RecognitionState.collecting) {
        // Real mode - get actual sensor data only when collecting or showing prediction
        // (not during countdown or idle when sensor isn't streaming)
        if (latestData != null) {
          // Add data if timestamp is new OR if this is the first data point
          if (_lastChartDataTimestamp == null || latestData.timestamp != _lastChartDataTimestamp) {
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
      }
    });
  }

  void _stopChartDataPolling() {
    _chartDataTimer?.cancel();
    _chartDataTimer = null;
  }

  bool _isConnecting = false; // Prevent multiple connection attempts

  Future<void> _toggleRecognition() async {
    print('🔘 HomeTabScreen: _toggleRecognition called');
    final sensorDataProvider = context.read<SensorDataProvider>();
    final activityProvider = context.read<ActivityProvider>();
    final appState = context.read<AppStateProvider>();

    // Prevent multiple simultaneous connection attempts
    if (_isConnecting) {
      print('⏳ HomeTabScreen: Already connecting, ignoring tap');
      return;
    }

    // Check if session is active (any state except idle)
    final isSessionActive =
        sensorDataProvider.recognitionState != RecognitionState.idle;
    print(
      '🔘 HomeTabScreen: isSessionActive=$isSessionActive, recognitionState=${sensorDataProvider.recognitionState}',
    );

    if (!isSessionActive) {
      // Start new session
      print('▶️ HomeTabScreen: Starting new recognition session');
      _isConnecting = true; // Set flag to prevent multiple taps

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

      // Set up sensor data callback to capture data with predictions
      activityProvider.setSensorDataCallback(() {
        return _getSensorSnapshots();
      });

      // Set up collection start time callback - consumes from FIFO queue
      // so each prediction gets its own corresponding window start time
      activityProvider.setCollectionStartTimeCallback(() {
        return sensorDataProvider.consumeOldestWindowStartTime();
      });

      try {
        print('🌐 HomeTabScreen: Starting recognition');
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

        await appState.setActivityRecognitionEnabled(true);
        _isConnecting = false; // Reset flag on success
      } catch (e) {
        _isConnecting = false; // Reset flag on error
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
      activityProvider.setSensorDataCallback(null); // Clear sensor callback
      activityProvider.setCollectionStartTimeCallback(null); // Clear time callback

      // Stop chart data polling and countdown
      _stopChartDataPolling();
      _stopNextPredictionCountdown();

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
                  // Reset state when disabled
                  if (!isEnabled) {
                    _showActivityDetected = false;
                    _activityDetectedTimer?.cancel();
                    _lastPredictionTimestamp = null;
                  }

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
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isEnabled
                                ? [Color(0xFF8B5CF6), Color(0xFF9333EA)]
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
                          ],
                        ),
                        child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header removed - using split card layout with section headers instead
                                if (isEnabled) ...[
                                  // Show state-specific UI
                                  if (recognitionState == RecognitionState.countdown) ...[
                                    // Countdown before collection starts
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.hourglass_top_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Starting in ${sensorDataProvider.countdown}...',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else if (recognitionState == RecognitionState.collecting) ...[
                                    // OPTION A: Current Activity (Big, prominent)
                                    Center(
                                      child: Column(
                                        children: [
                                          if (sensorDataProvider.latestPrediction != null) ...[
                                            // Space for "Activity Detected" text at top
                                            const SizedBox(height: 16),
                                            // Show detected activity
                                            Text(
                                              currentActivity.displayName,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 32,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            // Show reasoning when not in fast inference mode
                                            if (!sensorDataProvider.fastInference &&
                                                activityProvider.activityHistory.isNotEmpty &&
                                                activityProvider.activityHistory.first.reasoning != null) ...[
                                              const SizedBox(height: 12),
                                              Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Icon(
                                                      Icons.psychology,
                                                      color: Colors.white.withValues(alpha: 0.8),
                                                      size: 16,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        activityProvider.activityHistory.first.reasoning!,
                                                        style: TextStyle(
                                                          color: Colors.white.withValues(alpha: 0.9),
                                                          fontSize: 12,
                                                          height: 1.4,
                                                        ),
                                                        maxLines: 4,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ] else ...[
                                            // No prediction yet - show waiting
                                            Icon(
                                              Icons.sensors,
                                              color: Colors.white.withValues(alpha: 0.6),
                                              size: 48,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              'Detecting Activity...',
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.9),
                                                fontSize: 20,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
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
                                        color: Colors.white.withValues(alpha: 0.75),
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
                      ),
                      // Live badge OR Activity Detected text in top-left corner
                      if (isEnabled &&
                          recognitionState == RecognitionState.collecting &&
                          sensorDataProvider.latestPrediction != null)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: _showActivityDetected
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome,
                                      size: 14,
                                      color: Colors.white.withValues(alpha: 0.8),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Activity Detected',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                )
                              : FadeTransition(
                                  opacity: _blinkAnimation,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.green.withValues(alpha: 0.5),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: Colors.greenAccent,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.greenAccent.withValues(alpha: 0.5),
                                                blurRadius: 6,
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Live',
                                          style: TextStyle(
                                            color: Colors.greenAccent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
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
                      // Pending indicator moved inline to collection status section
                    ],
                  );
                },
              ),

              // OPTION C: Process Status Card (Sequential flow)
              Consumer3<ActivityProvider, AppStateProvider, SensorDataProvider>(
                builder: (context, activityProvider, appState, sensorDataProvider, _) {
                  final isEnabled = appState.activityRecognitionEnabled;
                  final recognitionState = sensorDataProvider.recognitionState;

                  // Only show when actively collecting (not countdown or idle)
                  if (!isEnabled || recognitionState != RecognitionState.collecting) {
                    return const SizedBox.shrink();
                  }

                  // Determine what phase we're in for display
                  final pendingCount = sensorDataProvider.pendingPredictions;
                  final samplesCollected = sensorDataProvider.samplesInCurrentWindow;
                  final windowSize = sensorDataProvider.windowSize;
                  final progress = samplesCollected / windowSize;

                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                color: Color(0xFF8B5CF6),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Recognition Pipeline',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF374151),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Step 1: Collecting
                          _buildPipelineStep(
                            icon: Icons.sensors,
                            label: 'Collecting',
                            detail: '',
                            progress: progress,
                            isActive: true,
                            isComplete: false,
                          ),

                          const SizedBox(height: 12),

                          // Step 2: Processing
                          _buildPipelineStep(
                            icon: Icons.psychology,
                            label: 'Processing',
                            detail: pendingCount > 0
                                ? '$pendingCount prediction${pendingCount > 1 ? 's' : ''} in queue'
                                : 'Waiting for data',
                            progress: null,
                            isActive: pendingCount > 0,
                            isComplete: false,
                          ),

                          const SizedBox(height: 12),

                          // Step 3: Detecting (shows green spinner for continuous detection)
                          _buildPipelineStep(
                            icon: Icons.check_circle,
                            label: 'Detecting',
                            detail: sensorDataProvider.latestPrediction ?? 'No prediction yet',
                            progress: null,
                            isActive: sensorDataProvider.latestPrediction != null, // Green spinner when detecting
                            isComplete: sensorDataProvider.latestPrediction != null,
                          ),
                        ],
                      ),
                    ),
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
                      recognitionState != RecognitionState.idle) {
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

  // Convert marker position (total data points when marker was added) to chart index
  double? _markerToChartIndex(int markerPosition) {
    final chartOffset = _totalDataPointsAdded - _accelX.length;
    final chartIndex = markerPosition - chartOffset;
    if (chartIndex < 0 || chartIndex >= _accelX.length) {
      return null; // Marker is not visible in current chart window
    }
    return chartIndex.toDouble();
  }

  // Build vertical lines for collection start/end markers
  List<VerticalLine> _buildCollectionMarkerLines(double minY, double maxY) {
    final lines = <VerticalLine>[];

    // Start markers (green)
    for (final marker in _collectionStartMarkers) {
      final chartIndex = _markerToChartIndex(marker);
      if (chartIndex != null) {
        lines.add(VerticalLine(
          x: chartIndex,
          color: Color(0xFF10B981).withValues(alpha: 0.8),
          strokeWidth: 2,
          dashArray: [4, 4],
        ));
      }
    }

    // End markers (red/orange)
    for (final marker in _collectionEndMarkers) {
      final chartIndex = _markerToChartIndex(marker);
      if (chartIndex != null) {
        lines.add(VerticalLine(
          x: chartIndex,
          color: Color(0xFFF59E0B).withValues(alpha: 0.8),
          strokeWidth: 2,
          dashArray: [4, 4],
        ));
      }
    }

    return lines;
  }

  // Build vertical range annotations for shaded collection windows
  List<VerticalRangeAnnotation> _buildVerticalRangeAnnotations() {
    final annotations = <VerticalRangeAnnotation>[];

    // Pair up start and end markers to create shaded regions
    final numPairs = _collectionStartMarkers.length < _collectionEndMarkers.length
        ? _collectionStartMarkers.length
        : _collectionEndMarkers.length;

    for (int i = 0; i < numPairs; i++) {
      final startIndex = _markerToChartIndex(_collectionStartMarkers[i]);
      final endIndex = _markerToChartIndex(_collectionEndMarkers[i]);

      if (startIndex != null || endIndex != null) {
        // At least one boundary is visible
        final visibleStart = startIndex ?? 0.0;
        final visibleEnd = endIndex ?? _accelX.length.toDouble();

        if (visibleEnd > visibleStart) {
          annotations.add(VerticalRangeAnnotation(
            x1: visibleStart,
            x2: visibleEnd,
            color: Color(0xFF8B5CF6).withValues(alpha: 0.1),
          ));
        }
      }
    }

    // Handle ongoing collection (has start but no end yet)
    if (_collectionStartMarkers.length > _collectionEndMarkers.length) {
      final startIndex = _markerToChartIndex(_collectionStartMarkers.last);
      if (startIndex != null) {
        annotations.add(VerticalRangeAnnotation(
          x1: startIndex,
          x2: _accelX.length.toDouble(),
          color: Color(0xFF8B5CF6).withValues(alpha: 0.1),
        ));
      }
    }

    return annotations;
  }

  Widget _buildSensorChart(String name) {
    List<double> xData, yData, zData;
    double minY, maxY;

    if (name == 'Accelerometer') {
      xData = _accelX;
      yData = _accelY;
      zData = _accelZ;
      minY = -20.0;
      maxY = 20.0;
    } else {
      xData = _gyroX;
      yData = _gyroY;
      zData = _gyroZ;
      minY = -20.0;
      maxY = 20.0;
    }

    List<FlSpot> xSpots = [];
    List<FlSpot> ySpots = [];
    List<FlSpot> zSpots = [];

    for (int i = 0; i < xData.length; i++) {
      xSpots.add(FlSpot(i.toDouble(), xData[i]));
      ySpots.add(FlSpot(i.toDouble(), yData[i]));
      zSpots.add(FlSpot(i.toDouble(), zData[i]));
    }

    // Build collection window markers
    final markerLines = _buildCollectionMarkerLines(minY, maxY);

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
                extraLinesData: ExtraLinesData(
                  verticalLines: markerLines,
                ),
                rangeAnnotations: RangeAnnotations(
                  verticalRangeAnnotations: _buildVerticalRangeAnnotations(),
                ),
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
              const SizedBox(width: 12),
              _buildLegend('Y', Color(0xFF10B981)),
              const SizedBox(width: 12),
              _buildLegend('Z', Color(0xFF3B82F6)),
              if (_collectionStartMarkers.isNotEmpty) ...[
                const SizedBox(width: 12),
                _buildLineLegend('Start', Color(0xFF10B981)),
                const SizedBox(width: 12),
                _buildLineLegend('End', Color(0xFFF59E0B)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineStep({
    required IconData icon,
    required String label,
    required String detail,
    double? progress,
    required bool isActive,
    required bool isComplete,
  }) {
    final Color primaryColor = isComplete
        ? Color(0xFF10B981) // Green for complete
        : isActive
            ? Color(0xFF8B5CF6) // Purple for active
            : Color(0xFF9CA3AF); // Gray for inactive

    return Row(
      children: [
        // Icon with status indicator
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: isActive
              ? Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                    ),
                  ),
                )
              : Icon(
                  isComplete ? Icons.check_circle : icon,
                  color: primaryColor,
                  size: 20,
                ),
        ),
        const SizedBox(width: 12),

        // Label and detail
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isActive || isComplete
                      ? Color(0xFF374151)
                      : Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(height: 2),
              if (progress != null) ...[
                // Show progress bar for collecting step
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Color(0xFFE5E7EB),
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                    minHeight: 6,
                  ),
                ),
              ] else if (detail.isNotEmpty) ...[
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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

  Widget _buildLineLegend(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 2,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
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
