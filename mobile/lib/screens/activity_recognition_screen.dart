import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_state_provider.dart';
import '../providers/sensor_data_provider.dart';
import '../providers/activity_provider.dart';
import '../services/permission_service.dart';
import '../services/websocket_service.dart';
import '../models/activity_type.dart';
import '../widgets/connection_status.dart';
import '../widgets/activity_display.dart';
import 'home_screen.dart';

class ActivityRecognitionScreen extends StatefulWidget {
  const ActivityRecognitionScreen({super.key});

  @override
  State<ActivityRecognitionScreen> createState() =>
      _ActivityRecognitionScreenState();
}

class _ActivityRecognitionScreenState extends State<ActivityRecognitionScreen> {
  final PermissionService _permissionService = PermissionService();
  WebSocketService? _websocketService;
  bool _isInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      // Get the WebSocketService from ActivityProvider instead of creating a new one
      final activityProvider = context.read<ActivityProvider>();
      _websocketService = activityProvider.websocketService;
      _websocketService!.connectionStateStream.listen((state) {
        if (mounted) {
          context.read<AppStateProvider>().setConnectionState(state);
        }
      });
      _isInitialized = true;
    }
  }

  Future<void> _toggleRecognition() async {
    final sensorDataProvider = context.read<SensorDataProvider>();
    final activityProvider = context.read<ActivityProvider>();
    final appState = context.read<AppStateProvider>();

    // Check if session is active (any state except idle)
    final isSessionActive = sensorDataProvider.recognitionState != RecognitionState.idle;

    if (!isSessionActive) {
      // Start new session
      // Check sensor permissions
      final hasPermission = await _permissionService.requestSensorPermissions();
      if (!hasPermission) {
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
          // Start demo mode - no WebSocket connection needed
          activityProvider.startListening(demoMode: true);
        } else {
          await _websocketService!.connect(appState.websocketUrl);
          activityProvider.startListening();
          sensorDataProvider.startActivityRecognition();
        }

        // Update global state
        await appState.setActivityRecognitionEnabled(true);
      } catch (e) {
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
      sensorDataProvider.stopCollection();
      activityProvider.stopListening();

      // Only disconnect if motion capture is also disabled
      if (!appState.motionCaptureEnabled) {
        _websocketService!.disconnect();
      }

      // Update global state
      await appState.setActivityRecognitionEnabled(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Recognition'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<AppStateProvider>(
        builder: (context, appState, _) {
          // Check if activity recognition is disabled from settings
          if (!appState.activityRecognitionEnabled) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.timeline_outlined,
                      size: 80,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Activity Recognition Disabled',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Enable Activity Recognition in Settings to start detecting your activities.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Navigate to settings tab
                        HomeScreen.of(context)?.navigateToTab(4);
                      },
                      icon: const Icon(Icons.settings),
                      label: const Text('Go to Settings'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Activity recognition is enabled, show normal UI
          return Column(
            children: [
              ConnectionStatusBanner(
                connectionState: appState.connectionState,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                  Consumer2<ActivityProvider, SensorDataProvider>(
                    builder: (context, activityProvider, sensorDataProvider, _) {
                      final state = sensorDataProvider.recognitionState;

                      // Show countdown when in countdown state
                      if (state == RecognitionState.countdown) {
                        return Card(
                          elevation: 4,
                          child: Container(
                            padding: const EdgeInsets.all(48.0),
                            width: double.infinity,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  sensorDataProvider.countdown == 0 ? 'GO!' : '${sensorDataProvider.countdown}',
                                  style: TextStyle(
                                    fontSize: 120,
                                    fontWeight: FontWeight.bold,
                                    color: sensorDataProvider.countdown == 0
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  sensorDataProvider.countdown == 0
                                      ? 'Starting...'
                                      : 'Get ready!',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      // Show buffering/loading when:
                      // 1. Collecting (any window)
                      // 2. Waiting for prediction (server processing)
                      // Only show actual activity when prediction is received
                      final isBuffering = state == RecognitionState.collecting ||
                                         state == RecognitionState.waitingForPrediction;

                      // Get last updated time and reasoning from most recent prediction
                      final lastUpdated = activityProvider.activityHistory.isNotEmpty
                          ? activityProvider.activityHistory.first.timestamp
                          : null;
                      final reasoning = activityProvider.activityHistory.isNotEmpty
                          ? activityProvider.activityHistory.first.reasoning
                          : null;

                      return ActivityDisplay(
                        activity: activityProvider.currentActivity,
                        isBuffering: isBuffering,
                        lastUpdated: lastUpdated,
                        reasoning: reasoning,
                        onStop: state != RecognitionState.idle ? _toggleRecognition : null,
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  // Window progress and status indicator
                  Consumer<SensorDataProvider>(
                    builder: (context, sensorDataProvider, _) {
                      final state = sensorDataProvider.recognitionState;

                      if (state == RecognitionState.idle || state == RecognitionState.countdown) {
                        return const SizedBox.shrink();
                      }

                      final progress = sensorDataProvider.samplesInCurrentWindow / sensorDataProvider.windowSize;

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // State title
                              Row(
                                children: [
                                  if (state == RecognitionState.collecting)
                                    const Icon(Icons.sensors, color: Colors.blue, size: 20)
                                  else if (state == RecognitionState.waitingForPrediction)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  else if (state == RecognitionState.predictionReceived)
                                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    state == RecognitionState.collecting
                                        ? 'Collecting Data'
                                        : state == RecognitionState.waitingForPrediction
                                            ? 'Processing'
                                            : 'Ready',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Progress bar
                              LinearProgressIndicator(
                                value: progress,
                                backgroundColor: Colors.grey[200],
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  state == RecognitionState.collecting
                                      ? Colors.blue
                                      : state == RecognitionState.waitingForPrediction
                                          ? Colors.orange
                                          : Colors.green,
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Sample count
                              Text(
                                '${sensorDataProvider.samplesInCurrentWindow}/${sensorDataProvider.windowSize} samples',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),

                              // State message
                              const SizedBox(height: 8),
                              if (state == RecognitionState.collecting)
                                const Text(
                                  '📊 Collecting sensor data...',
                                  style: TextStyle(fontSize: 13, color: Colors.blue),
                                )
                              else if (state == RecognitionState.waitingForPrediction)
                                const Text(
                                  '⏳ Server is analyzing the data...',
                                  style: TextStyle(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.bold),
                                )
                              else if (state == RecognitionState.predictionReceived)
                                Text(
                                  '✅ Prediction: ${sensorDataProvider.latestPrediction?.toUpperCase() ?? "N/A"}',
                                  style: const TextStyle(fontSize: 14, color: Colors.green, fontWeight: FontWeight.bold),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Consumer2<ActivityProvider, SensorDataProvider>(
                    builder: (context, activityProvider, sensorDataProvider, _) {
                      if (activityProvider.activityHistory.isEmpty) {
                        // Show different message when buffering vs not started
                        final message = sensorDataProvider.isCollecting
                            ? 'Waiting for predictions...'
                            : 'No activity history yet';

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (sensorDataProvider.isCollecting) ...[
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Text(
                                  message,
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Activity History',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: activityProvider.activityHistory.length.clamp(0, 10),
                                separatorBuilder: (_, _) => const Divider(),
                                itemBuilder: (context, index) {
                                  final prediction =
                                      activityProvider.activityHistory[index];
                                  return ListTile(
                                    dense: true,
                                    leading: Icon(
                                      _getActivityIcon(prediction.activity),
                                      color: _getActivityColor(prediction.activity),
                                    ),
                                    title: Text(prediction.activity.displayName),
                                    subtitle: Text(
                                      DateFormat('HH:mm:ss').format(prediction.timestamp),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Consumer2<AppStateProvider, SensorDataProvider>(
        builder: (context, appState, sensorData, _) {
          // Don't show button if activity recognition is disabled
          if (!appState.activityRecognitionEnabled) {
            return const SizedBox.shrink();
          }

          final state = sensorData.recognitionState;

          // Show "Next Window" button when prediction is received
          if (state == RecognitionState.predictionReceived) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  onPressed: () {
                    sensorData.collectNextWindow();
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Next Window'),
                  backgroundColor: Colors.blue,
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  onPressed: _toggleRecognition,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  backgroundColor: Colors.red,
                ),
              ],
            );
          }

          // Hide button while waiting for prediction (show only in status card)
          if (state == RecognitionState.waitingForPrediction) {
            return FloatingActionButton.extended(
              onPressed: _toggleRecognition,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
              backgroundColor: Colors.red,
            );
          }

          // Default Start/Stop button
          final isSessionActive = state != RecognitionState.idle;

          return FloatingActionButton.extended(
            onPressed: _toggleRecognition,
            icon: Icon(
              isSessionActive ? Icons.stop : Icons.play_arrow,
            ),
            label: Text(
              isSessionActive ? 'Stop' : 'Start',
            ),
            backgroundColor:
                isSessionActive ? Colors.red : Colors.green,
          );
        },
      ),
    );
  }

  IconData _getActivityIcon(ActivityType activityType) {
    switch (activityType) {
      case ActivityType.walking:
        return Icons.directions_walk;
      case ActivityType.running:
        return Icons.directions_run;
      case ActivityType.sitting:
        return Icons.event_seat;
      case ActivityType.standing:
        return Icons.accessibility_new;
      case ActivityType.walkingUpstairs:
        return Icons.stairs;
      case ActivityType.walkingDownstairs:
        return Icons.stairs;
      case ActivityType.unknown:
        return Icons.help_outline;
    }
  }

  Color _getActivityColor(ActivityType activityType) {
    switch (activityType) {
      case ActivityType.walking:
        return Colors.blue;
      case ActivityType.running:
        return Colors.red;
      case ActivityType.sitting:
        return Colors.green;
      case ActivityType.standing:
        return Colors.orange;
      case ActivityType.walkingUpstairs:
        return Colors.purple;
      case ActivityType.walkingDownstairs:
        return Colors.teal;
      case ActivityType.unknown:
        return Colors.grey;
    }
  }

  @override
  void dispose() {
    // Don't dispose the shared WebSocketService - it's managed by the provider
    super.dispose();
  }
}
