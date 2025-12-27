import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/sensor_data_provider.dart';
import '../services/permission_service.dart';
import '../services/websocket_service.dart';
import '../widgets/connection_status.dart';
import '../widgets/sensor_data_display.dart';

class DataCollectionScreen extends StatefulWidget {
  const DataCollectionScreen({super.key});

  @override
  State<DataCollectionScreen> createState() => _DataCollectionScreenState();
}

class _DataCollectionScreenState extends State<DataCollectionScreen> {
  final PermissionService _permissionService = PermissionService();
  WebSocketService? _websocketService;
  bool _isInitialized = false;
  String _selectedActivityLabel = 'walking';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      // Get the WebSocketService from SensorDataProvider instead of creating a new one
      final sensorDataProvider = context.read<SensorDataProvider>();
      _websocketService = sensorDataProvider.websocketService;
      _websocketService!.connectionStateStream.listen((state) {
        if (mounted) {
          context.read<AppStateProvider>().setConnectionState(state);
        }
      });
      _isInitialized = true;
    }
  }

  Future<void> _toggleCollection() async {
    final sensorDataProvider = context.read<SensorDataProvider>();
    final appState = context.read<AppStateProvider>();

    if (!sensorDataProvider.isCollecting) {
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
        await _websocketService!.connect(appState.websocketUrl);
        sensorDataProvider.setActivityLabel(_selectedActivityLabel);
        sensorDataProvider.startDataCollection();
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
      _websocketService!.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Collection'),
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
              child: Consumer<SensorDataProvider>(
                builder: (context, sensorData, _) {
                  return Column(
                    children: [
                      Consumer<AppStateProvider>(
                        builder: (context, appState, _) {
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  Text(
                                    'WebSocket URL',
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    appState.websocketUrl,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Card(
                        color: Colors.green[50],
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Activity Label for Data Collection',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Select the activity you are performing to label the collected data:',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedActivityLabel,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'walking', child: Text('Walking')),
                                  DropdownMenuItem(value: 'running', child: Text('Running')),
                                  DropdownMenuItem(value: 'sitting', child: Text('Sitting')),
                                  DropdownMenuItem(value: 'standing', child: Text('Standing')),
                                  DropdownMenuItem(value: 'walking_upstairs', child: Text('Walking Upstairs')),
                                  DropdownMenuItem(value: 'walking_downstairs', child: Text('Walking Downstairs')),
                                ],
                                onChanged: sensorData.isCollecting ? null : (value) {
                                  if (value != null) {
                                    setState(() {
                                      _selectedActivityLabel = value;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (sensorData.isCollecting) ...[
                        Card(
                          color: Colors.blue[50],
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Column(
                                  children: [
                                    Text(
                                      '${sensorData.collectionDuration.inMinutes}:${(sensorData.collectionDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                                      style: Theme.of(context).textTheme.headlineSmall,
                                    ),
                                    const Text('Duration'),
                                  ],
                                ),
                                Column(
                                  children: [
                                    Text(
                                      '${sensorData.packetsSent}',
                                      style: Theme.of(context).textTheme.headlineSmall,
                                    ),
                                    const Text('Packets Sent'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      SensorDataDisplay(
                        sensorName: 'Accelerometer',
                        reading: sensorData.latestData?.accelerometer,
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 12),
                      SensorDataDisplay(
                        sensorName: 'Gyroscope',
                        reading: sensorData.latestData?.gyroscope,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 12),
                      SensorDataDisplay(
                        sensorName: 'Magnetometer',
                        reading: sensorData.latestData?.magnetometer,
                        color: Colors.purple,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Consumer<SensorDataProvider>(
        builder: (context, sensorData, _) {
          return FloatingActionButton.extended(
            onPressed: _toggleCollection,
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

  @override
  void dispose() {
    // Don't dispose the shared WebSocketService - it's managed by the provider
    super.dispose();
  }
}
