import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/activity_provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/sensor_data_provider.dart';
import '../models/activity_type.dart';
import '../services/permission_service.dart';

class HomeTabScreen extends StatefulWidget {
  const HomeTabScreen({super.key});

  @override
  State<HomeTabScreen> createState() => _HomeTabScreenState();
}

class _HomeTabScreenState extends State<HomeTabScreen> with TickerProviderStateMixin {
  final PermissionService _permissionService = PermissionService();
  late AnimationController _activityAnimationController;
  late AnimationController _cardFlashController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _flashAnimation;
  ActivityType? _previousActivity;
  bool _hasAutoStarted = false;
  bool _hasReceivedFirstPrediction = false;
  int _predictionCount = 0; // Track number of predictions to trigger animation

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
      CurvedAnimation(
        parent: _cardFlashController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _activityAnimationController.dispose();
    _cardFlashController.dispose();
    super.dispose();
  }

  Future<void> _toggleRecognition() async {
    print('🔘 HomeTabScreen: _toggleRecognition called');
    final sensorDataProvider = context.read<SensorDataProvider>();
    final activityProvider = context.read<ActivityProvider>();
    final appState = context.read<AppStateProvider>();

    // Check if session is active (any state except idle)
    final isSessionActive = sensorDataProvider.recognitionState != RecognitionState.idle;
    print('🔘 HomeTabScreen: isSessionActive=$isSessionActive, recognitionState=${sensorDataProvider.recognitionState}');

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
          print('🌐 HomeTabScreen: Connected! Starting ActivityProvider listener...');
          activityProvider.startListening();
          print('🌐 HomeTabScreen: Starting SensorDataProvider recognition...');
          sensorDataProvider.startActivityRecognition();
          print('✅ HomeTabScreen: All started successfully');
        }

        await appState.setActivityRecognitionEnabled(true);
      } catch (e) {
        print('❌ HomeTabScreen: Error starting recognition: $e');
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
      // Stop active session
      print('⏹️ HomeTabScreen: Stopping recognition session');
      sensorDataProvider.stopCollection();
      activityProvider.stopListening();

      // Only disconnect if motion capture is also disabled
      if (!appState.motionCaptureEnabled) {
        activityProvider.websocketService.disconnect();
      }

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
      case ActivityType.walkingUpstairs:
        return 'Upward movement with elevated effort detected';
      case ActivityType.walkingDownstairs:
        return 'Downward movement with controlled pace';
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
                  final currentPredictionCount = activityProvider.activityHistory.length;

                  // Detect new prediction by checking history count
                  if (currentPredictionCount > _predictionCount && currentActivity != ActivityType.unknown && isEnabled) {
                    _predictionCount = currentPredictionCount;
                    if (!_hasReceivedFirstPrediction) {
                      print('🎊 HomeTabScreen: First prediction received! ${currentActivity.displayName}');
                      _hasReceivedFirstPrediction = true;
                    } else {
                      print('🎯 HomeTabScreen: New prediction #$currentPredictionCount received! ${currentActivity.displayName} (${_previousActivity == currentActivity ? "SAME ACTIVITY" : "CHANGED"})');
                    }
                    // Trigger animations for EVERY prediction (even if same activity)
                    print('🎬 HomeTabScreen: Triggering bounce and flash animations!');
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
                  final isWaitingForFirstPrediction = isEnabled &&
                                                       !_hasReceivedFirstPrediction &&
                                                       recognitionState != RecognitionState.idle;

                  _previousActivity = currentActivity;

                  // Auto-start recognition if enabled and not running (only once)
                  if (isEnabled && recognitionState == RecognitionState.idle && !_hasAutoStarted) {
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
                              ? _flashAnimation.value * 2  // 0 to 1 (first half)
                              : (1 - _flashAnimation.value) * 2; // 1 to 0 (second half)

                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isEnabled
                                    ? [
                                        Color.lerp(Color(0xFF8B5CF6), Color(0xFFFFFFFF), flashValue * 0.4)!,
                                        Color.lerp(Color(0xFF9333EA), Color(0xFFFFFFFF), flashValue * 0.4)!,
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
                                    color: Color(0xFF8B5CF6).withValues(alpha: flashValue * 0.5),
                                    blurRadius: 24 * flashValue,
                                    offset: const Offset(0, 0),
                                  ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Show header when enabled and not in loading state
                                if (isEnabled && !isWaitingForFirstPrediction) ...[
                                  // Animate the "Activity Detected" header for each prediction
                                  ScaleTransition(
                                    scale: _scaleAnimation,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.sensors,
                                          color: Colors.white,
                                          size: 20
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
                                  padding: const EdgeInsets.only(left: 32),
                                  child: Text(
                                    'This may take a few seconds',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
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
                            const SizedBox(height: 4),
                            Text(
                              _getActivityDescription(currentActivity),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 14,
                              ),
                            ),
                          ],
                                ] else ...[
                                  // Disabled state - show with similar layout to active state
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                        'Enable Activity Recognition in Settings to start tracking',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.8),
                                          fontSize: 14,
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
                                            color: Colors.white.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(8),
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
                                              Text(
                                                '87%',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                ),
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
                      // Stop button in top-right corner when recognition is active
                      if (isEnabled && recognitionState != RecognitionState.idle)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _toggleRecognition,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                        ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 16),

              // Stats Grid
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
                children: [
                  _buildStatCard(
                    icon: Icons.directions_walk,
                    iconColor: Color(0xFF3B82F6),
                    title: 'Steps',
                    value: '8,547',
                    change: '+12% vs yesterday',
                    changePositive: true,
                  ),
                  _buildStatCard(
                    icon: Icons.local_fire_department,
                    iconColor: Color(0xFFFF6B00),
                    title: 'Calories',
                    value: '520',
                    unit: 'kcal',
                    change: '+8% vs yesterday',
                    changePositive: true,
                  ),
                  _buildStatCard(
                    icon: Icons.access_time,
                    iconColor: Color(0xFF10B981),
                    title: 'Active Time',
                    value: '75',
                    unit: 'min',
                    change: '-5% vs yesterday',
                    changePositive: false,
                  ),
                  _buildStatCard(
                    icon: Icons.favorite,
                    iconColor: Color(0xFFEF4444),
                    title: 'Heart Rate',
                    value: '78',
                    unit: 'bpm',
                    change: null,
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Quick Start Section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Color(0xFFE5E7EB),
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
                    Text(
                      'Quick Start',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildQuickStartButton(
                            icon: Icons.directions_walk,
                            label: 'Walk',
                            color: Color(0xFFDDEEFF),
                            iconColor: Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildQuickStartButton(
                            icon: Icons.directions_run,
                            label: 'Run',
                            color: Color(0xFFFFE5E5),
                            iconColor: Color(0xFFDC2626),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildQuickStartButton(
                            icon: Icons.fitness_center,
                            label: 'Workout',
                            color: Color(0xFFE0F5E9),
                            iconColor: Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    String? unit,
    String? change,
    bool? changePositive,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color(0xFFE5E7EB),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      unit,
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ],
              ),
              if (change != null) ...[
                const SizedBox(height: 4),
                Text(
                  change,
                  style: TextStyle(
                    fontSize: 12,
                    color: changePositive == true
                        ? Color(0xFF059669)
                        : Color(0xFFDC2626),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStartButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: iconColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
