import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_state_provider.dart';
import '../providers/sensor_data_provider.dart';
import '../providers/activity_provider.dart';
import '../services/permission_service.dart';
import '../services/websocket_service.dart';
import '../widgets/connection_status.dart';
import '../widgets/activity_display.dart';

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

    if (!sensorDataProvider.isCollecting) {
      // Only check permissions if not in demo mode
      if (!appState.isDemoMode) {
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
      }

      try {
        await _websocketService!.connect(appState.websocketUrl);
        activityProvider.startListening();
        sensorDataProvider.startActivityRecognition();
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
      sensorDataProvider.stopCollection();
      activityProvider.stopListening();
      _websocketService!.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Recognition'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Consumer<AppStateProvider>(
            builder: (context, appState, _) {
              return ConnectionStatusBanner(
                connectionState: appState.connectionState,
              );
            },
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Consumer<ActivityProvider>(
                    builder: (context, activityProvider, _) {
                      return ActivityDisplay(
                        activity: activityProvider.currentActivity,
                        confidence: activityProvider.confidence,
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Consumer<ActivityProvider>(
                    builder: (context, activityProvider, _) {
                      if (activityProvider.activityHistory.isEmpty) {
                        return const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text(
                              'No activity history yet',
                              style: TextStyle(color: Colors.grey),
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
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    title: Text(prediction.activity.displayName),
                                    subtitle: Text(
                                      DateFormat('HH:mm:ss').format(prediction.timestamp),
                                    ),
                                    trailing: Text(
                                      '${(prediction.confidence * 100).toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
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
      ),
      floatingActionButton: Consumer<SensorDataProvider>(
        builder: (context, sensorData, _) {
          return FloatingActionButton.extended(
            onPressed: _toggleRecognition,
            icon: Icon(
              sensorData.isCollecting ? Icons.stop : Icons.play_arrow,
            ),
            label: Text(
              sensorData.isCollecting ? 'Stop' : 'Start',
            ),
            backgroundColor:
                sensorData.isCollecting ? Colors.red : Colors.green,
          );
        },
      ),
    );
  }

  IconData _getActivityIcon(dynamic activityType) {
    switch (activityType) {
      case 'walking':
        return Icons.directions_walk;
      case 'running':
        return Icons.directions_run;
      case 'sitting':
        return Icons.event_seat;
      case 'standing':
        return Icons.accessibility_new;
      default:
        return Icons.help_outline;
    }
  }

  @override
  void dispose() {
    // Don't dispose the shared WebSocketService - it's managed by the provider
    super.dispose();
  }
}
