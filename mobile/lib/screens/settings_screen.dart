import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dotted_border/dotted_border.dart';
import '../providers/app_state_provider.dart';
import '../providers/sensor_data_provider.dart';
import '../providers/activity_provider.dart';
import '../services/permission_service.dart';
import '../services/websocket_service.dart' as ws;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _dataSharingEnabled = false;
  bool _sleepModeEnabled = false;
  bool _gpsTrackingEnabled = true;
  late TextEditingController _urlController;
  final PermissionService _permissionService = PermissionService();

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppStateProvider>();
    _urlController = TextEditingController(text: appState.websocketUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _toggleActivityRecognition(bool value) async {
    final sensorDataProvider = context.read<SensorDataProvider>();
    final activityProvider = context.read<ActivityProvider>();
    final appState = context.read<AppStateProvider>();

    if (value) {
      // Enable Activity Recognition
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
          // Connect to WebSocket
          await sensorDataProvider.websocketService.connect(appState.websocketUrl);

          // Start listening for predictions
          activityProvider.startListening();

          // Start activity recognition mode
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
      // Disable Activity Recognition
      sensorDataProvider.stopCollection();
      activityProvider.stopListening();

      // Only disconnect if motion capture is also disabled
      if (!appState.motionCaptureEnabled) {
        sensorDataProvider.websocketService.disconnect();
      }

      // Update global state
      await appState.setActivityRecognitionEnabled(false);
    }
  }

  Future<void> _toggleMotionCapture(bool value) async {
    final sensorDataProvider = context.read<SensorDataProvider>();
    final appState = context.read<AppStateProvider>();

    if (value) {
      // Enable Motion Capture
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
          // Enable demo mode - no WebSocket connection needed
          // Motion capture will use mock data in the data collection screen
        } else {
          // Connect to WebSocket if not already connected
          if (sensorDataProvider.websocketService.connectionState != ws.ConnectionState.connected) {
            await sensorDataProvider.websocketService.connect(appState.websocketUrl);
          }
        }

        // Update global state
        appState.setMotionCaptureEnabled(true);
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
      // Disable Motion Capture
      sensorDataProvider.stopCollection();

      // Only disconnect if activity recognition is also disabled
      if (!appState.activityRecognitionEnabled) {
        sensorDataProvider.websocketService.disconnect();
      }

      // Update global state
      appState.setMotionCaptureEnabled(false);
    }
  }

  void _showUrlDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('WebSocket URL'),
        content: TextField(
          controller: _urlController,
          decoration: const InputDecoration(
            labelText: 'URL',
            hintText: 'ws://192.168.1.100:8080/ws',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final appState = context.read<AppStateProvider>();
              appState.setWebSocketUrl(_urlController.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Activity Recognition Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Color(0xFFE5E7EB), width: 1),
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
                  children: [
                    Text(
                      'Activity Recognition',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Consumer<AppStateProvider>(
                      builder: (context, appState, _) => _buildToggleItem(
                        icon: Icons.timeline,
                        title: 'Enable Activity Recognition',
                        subtitle:
                            'Use AI to automatically detect your activities',
                        value: appState.activityRecognitionEnabled,
                        onChanged: _toggleActivityRecognition,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Consumer<AppStateProvider>(
                      builder: (context, appState, _) => _buildToggleItem(
                        icon: Icons.storage,
                        title: 'Motion Capture',
                        subtitle:
                            'Collect labeled sensor data for model training',
                        value: appState.motionCaptureEnabled,
                        onChanged: _toggleMotionCapture,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
                    const SizedBox(height: 16),
                    Text(
                      'Connected Devices',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDeviceCard(
                      icon: Icons.phone_android,
                      deviceName: 'Samsung Galaxy S24',
                      status: 'Connected',
                      battery: 87,
                    ),
                    const SizedBox(height: 20),
                    InkWell(
                      onTap: () {
                        // TODO: Implement device pairing (smartwatch, fitness tracker, etc.)
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: DottedBorder(
                        color: Color.fromARGB(255, 147, 180, 227),
                        strokeWidth: 1,
                        dashPattern: [2, 2],
                        borderType: BorderType.RRect,
                        radius: Radius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Color(0xFFF0F9FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add,
                                color: Color(0xFF2563EB),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Connect New Device',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2563EB),
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

              const SizedBox(height: 16),

              // General Settings Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Color(0xFFE5E7EB), width: 1),
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
                  children: [
                    Text(
                      'General Settings',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildToggleItem(
                      icon: Icons.notifications_outlined,
                      title: 'Notifications',
                      subtitle: 'Get reminders and progress updates',
                      value: _notificationsEnabled,
                      onChanged: (value) {
                        setState(() {
                          _notificationsEnabled = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildToggleItem(
                      icon: Icons.share_outlined,
                      title: 'Data Sharing',
                      subtitle: 'Share anonymized data for research',
                      value: _dataSharingEnabled,
                      onChanged: (value) {
                        setState(() {
                          _dataSharingEnabled = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildToggleItem(
                      icon: Icons.bedtime_outlined,
                      title: 'Sleep Mode',
                      subtitle: 'Pause tracking during sleep hours',
                      value: _sleepModeEnabled,
                      onChanged: (value) {
                        setState(() {
                          _sleepModeEnabled = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildToggleItem(
                      icon: Icons.location_on_outlined,
                      title: 'GPS Tracking',
                      subtitle: 'Track your outdoor routes and distance',
                      value: _gpsTrackingEnabled,
                      onChanged: (value) {
                        setState(() {
                          _gpsTrackingEnabled = value;
                        });
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Server Configuration Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Color(0xFFE5E7EB), width: 1),
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
                  children: [
                    Text(
                      'Server Configuration',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Consumer<AppStateProvider>(
                      builder: (context, appState, _) => _buildToggleItem(
                        icon: Icons.science_outlined,
                        title: 'Demo Mode',
                        subtitle: 'Use mock data without server connection',
                        value: appState.demoModeEnabled,
                        onChanged: (value) {
                          appState.setDemoModeEnabled(value);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _showUrlDialog,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.cloud_outlined, size: 20, color: Color(0xFF6B7280)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'WebSocket URL',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Consumer<AppStateProvider>(
                                    builder: (context, appState, _) {
                                      return Text(
                                        appState.websocketUrl,
                                        style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                                        overflow: TextOverflow.ellipsis,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: Color(0xFF9CA3AF),
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildToggleItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Color(0xFF6B7280)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: Color(0xFF2563EB),
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: Color(0xFFE5E7EB),
          trackOutlineColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.selected)) {
                return null; // Use default for active state
              }
              return Color.fromARGB(222, 162, 163, 166); // Very light gray border for inactive
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard({
    required IconData icon,
    required String deviceName,
    required String status,
    required int battery,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Color(0xFF2563EB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                deviceName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    status,
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '•',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.battery_charging_full,
                    color: Color(0xFF059669),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$battery%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Color(0xFFD1FAE5),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.wifi, color: Color(0xFF059669), size: 18),
        ),
      ],
    );
  }
}
