import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dotted_border/dotted_border.dart';
import '../providers/app_state_provider.dart';
import '../providers/sensor_data_provider.dart';
import '../providers/activity_provider.dart';
import '../providers/device_info_provider.dart';
import '../providers/datastore_provider.dart';
import '../services/permission_service.dart';
import '../services/websocket_service.dart' as ws;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  late TextEditingController _datastoreNameController;
  final PermissionService _permissionService = PermissionService();

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppStateProvider>();
    _urlController = TextEditingController(text: appState.websocketUrl);
    _datastoreNameController = TextEditingController();

    // Auto-refresh datastores when settings screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoRefreshDatastores();
    });
  }

  Future<void> _autoRefreshDatastores() async {
    final appState = context.read<AppStateProvider>();
    final sensorDataProvider = context.read<SensorDataProvider>();
    final datastoreProvider = context.read<DataStoreProvider>();

    // Skip if in demo mode
    if (appState.demoModeEnabled) return;

    // Connect to WebSocket if not connected
    if (sensorDataProvider.websocketService.connectionState != ws.ConnectionState.connected) {
      try {
        await sensorDataProvider.websocketService.connect(appState.websocketUrl);
      } catch (e) {
        // Connection failed, don't refresh
        return;
      }
    }

    // Refresh datastores
    datastoreProvider.refreshDatastores();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _datastoreNameController.dispose();
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
                    Consumer<DeviceInfoProvider>(
                      builder: (context, deviceInfo, child) {
                        return _buildDeviceCard(
                          icon: Icons.phone_android,
                          deviceName: deviceInfo.deviceName,
                          status: 'Connected',
                          battery: deviceInfo.batteryLevel,
                          isCharging: deviceInfo.isCharging,
                        );
                      },
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

              // Data Store Section
              Container(
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
                child: Consumer<DataStoreProvider>(
                  builder: (context, datastoreProvider, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Data Store',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827),
                              ),
                            ),
                            if (datastoreProvider.isLoading)
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Manage your personal data stores for activity recognition',
                          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                        ),
                        const SizedBox(height: 16),

                        // Current Data Store
                        if (datastoreProvider.currentDatastore != null) ...[
                          _buildCurrentDatastoreCard(datastoreProvider.currentDatastore!),
                          const SizedBox(height: 16),
                        ],

                        // Error message
                        if (datastoreProvider.error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    datastoreProvider.error!,
                                    style: TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.close, size: 16),
                                  onPressed: () => datastoreProvider.clearError(),
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
                        const SizedBox(height: 16),

                        // My Data Stores header
                        Text(
                          'My Data Stores',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // List of all data stores (including default)
                        if (datastoreProvider.datastores.isEmpty)
                          Text(
                            'No data stores available',
                            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                          )
                        else
                          ...datastoreProvider.datastores
                              .map((ds) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _buildDatastoreItem(ds, datastoreProvider),
                                  )),

                        const SizedBox(height: 12),

                        // Create New Data Store button
                        InkWell(
                          onTap: () => _showCreateDatastoreDialog(datastoreProvider),
                          borderRadius: BorderRadius.circular(12),
                          child: DottedBorder(
                            color: Color(0xFF2563EB),
                            strokeWidth: 1,
                            dashPattern: [4, 4],
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
                                    'Create New Data Store',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Refresh button
                        Center(
                          child: TextButton.icon(
                            onPressed: () => _refreshDatastores(datastoreProvider),
                            icon: Icon(Icons.refresh, size: 16),
                            label: Text('Refresh'),
                            style: TextButton.styleFrom(
                              foregroundColor: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
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

  Widget _buildCurrentDatastoreCard(ws.DataStore datastore) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Color(0xFF2563EB).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.storage, color: Color(0xFF2563EB), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active Data Store',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 2),
                Text(
                  datastore.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                Text(
                  '${datastore.sampleCount} samples',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Active',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatastoreItem(ws.DataStore datastore, DataStoreProvider provider) {
    final isActive = datastore.isActive;
    final isDefault = datastore.isDefault;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Color(0xFFF0F9FF) : Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? Color(0xFF2563EB).withValues(alpha: 0.3) : Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isDefault ? Icons.cloud : Icons.folder,
            color: isActive ? Color(0xFF2563EB) : Color(0xFF6B7280),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      datastore.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF111827),
                      ),
                    ),
                    if (isDefault) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Shared',
                          style: TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${datastore.sampleCount} samples',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          if (!isActive) ...[
            TextButton(
              onPressed: () => provider.setDatastore(datastore.collectionName),
              style: TextButton.styleFrom(
                foregroundColor: Color(0xFF2563EB),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
              ),
              child: Text('Use', style: TextStyle(fontSize: 13)),
            ),
          ],
          // Only show delete button for non-default stores
          if (!isDefault)
            IconButton(
              onPressed: () => _showDeleteDatastoreDialog(datastore, provider),
              icon: Icon(Icons.delete_outline, size: 20),
              color: Color(0xFFDC2626),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(),
            ),
        ],
      ),
    );
  }

  void _showCreateDatastoreDialog(DataStoreProvider provider) {
    _datastoreNameController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Data Store'),
        content: TextField(
          controller: _datastoreNameController,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g., My Running Data',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = _datastoreNameController.text.trim();
              if (name.isNotEmpty) {
                provider.createDatastore(name);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF2563EB),
              foregroundColor: Colors.white,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDatastoreDialog(ws.DataStore datastore, DataStoreProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Data Store'),
        content: Text(
          'Are you sure you want to delete "${datastore.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              provider.deleteDatastore(datastore.collectionName);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshDatastores(DataStoreProvider provider) async {
    final appState = context.read<AppStateProvider>();
    final sensorDataProvider = context.read<SensorDataProvider>();

    // Connect to WebSocket if not connected
    if (sensorDataProvider.websocketService.connectionState != ws.ConnectionState.connected) {
      try {
        await sensorDataProvider.websocketService.connect(appState.websocketUrl);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connection failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    provider.refreshDatastores();
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
    bool isCharging = false,
  }) {
    // Choose battery icon based on charging state and level
    IconData batteryIcon;
    if (isCharging) {
      batteryIcon = Icons.battery_charging_full;
    } else if (battery > 90) {
      batteryIcon = Icons.battery_full;
    } else if (battery > 60) {
      batteryIcon = Icons.battery_5_bar;
    } else if (battery > 30) {
      batteryIcon = Icons.battery_3_bar;
    } else if (battery > 10) {
      batteryIcon = Icons.battery_2_bar;
    } else {
      batteryIcon = Icons.battery_1_bar;
    }

    // Battery color based on level
    Color batteryColor;
    if (battery <= 20) {
      batteryColor = Color(0xFFDC2626); // Red for low battery
    } else if (battery <= 50) {
      batteryColor = Color(0xFFF59E0B); // Orange for medium battery
    } else {
      batteryColor = Color(0xFF059669); // Green for good battery
    }

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
                    batteryIcon,
                    color: batteryColor,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$battery%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: batteryColor,
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
