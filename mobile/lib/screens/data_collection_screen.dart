import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/app_state_provider.dart';
import '../providers/sensor_data_provider.dart';
import '../providers/activity_provider.dart';
import '../services/permission_service.dart';
import '../services/websocket_service.dart';
import 'home_screen.dart';

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
  bool _showStatistics = true;
  bool _isDemoCollecting = false;
  int _demoSamplesCollected = 0;
  DateTime? _demoCollectionStartTime;

  // Live chart data - store last 100 points (2 seconds at 50Hz)
  final List<double> _accelX = [];
  final List<double> _accelY = [];
  final List<double> _accelZ = [];
  final List<double> _gyroX = [];
  final List<double> _gyroY = [];
  final List<double> _gyroZ = [];
  static const int _maxDataPoints = 100;

  StreamSubscription? _demoDataSubscription;
  Timer? _demoDataTimer;

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

  bool _isCollecting(SensorDataProvider sensorData, AppStateProvider appState) {
    return appState.demoModeEnabled ? _isDemoCollecting : sensorData.isCollecting;
  }

  void _addSensorData(Map<String, double> accel, Map<String, double> gyro) {
    setState(() {
      // Add new data
      _accelX.add(accel['x']!);
      _accelY.add(accel['y']!);
      _accelZ.add(accel['z']!);
      _gyroX.add(gyro['x']!);
      _gyroY.add(gyro['y']!);
      _gyroZ.add(gyro['z']!);

      // Keep only last _maxDataPoints
      if (_accelX.length > _maxDataPoints) {
        _accelX.removeAt(0);
        _accelY.removeAt(0);
        _accelZ.removeAt(0);
        _gyroX.removeAt(0);
        _gyroY.removeAt(0);
        _gyroZ.removeAt(0);
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
    });
  }

  Future<void> _toggleCollection() async {
    final sensorDataProvider = context.read<SensorDataProvider>();
    final appState = context.read<AppStateProvider>();
    final activityProvider = context.read<ActivityProvider>();

    final isCurrentlyCollecting = _isCollecting(sensorDataProvider, appState);

    if (!isCurrentlyCollecting) {
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
        // Clear previous sensor data
        _clearSensorData();

        // Check if in demo mode
        if (appState.demoModeEnabled) {
          // Demo mode - start mock collection without WebSocket
          setState(() {
            _isDemoCollecting = true;
            _demoSamplesCollected = 0;
            _demoCollectionStartTime = DateTime.now();
          });

          // Start mock data collection using demo service
          final demoService = activityProvider.demoService;

          demoService.startMockCollection(
            samplingRate: 50, // Collection runs until user stops
          );

          // Listen to demo collection progress
          _demoDataSubscription = demoService.collectionSamplesStream.listen((sampleCount) {
            if (mounted) {
              setState(() {
                _demoSamplesCollected = sampleCount;
              });
            }
          });

          // Generate mock sensor data for charts at 20Hz (smoother UI updates)
          _demoDataTimer = Timer.periodic(Duration(milliseconds: 50), (timer) {
            if (mounted && _isDemoCollecting) {
              final mockData = demoService.getMockSensorData();
              _addSensorData(
                mockData['accelerometer']!.cast<String, double>(),
                mockData['gyroscope']!.cast<String, double>(),
              );
            }
          });
        } else {
          // Real mode - connect to WebSocket
          await _websocketService!.connect(appState.websocketUrl);
          sensorDataProvider.setActivityLabel(_selectedActivityLabel);
          sensorDataProvider.startDataCollection();

          // Poll sensor data for charts at 20Hz (smoother UI updates)
          _demoDataTimer = Timer.periodic(Duration(milliseconds: 50), (timer) {
            if (mounted && sensorDataProvider.isCollecting) {
              final latestData = sensorDataProvider.latestData;
              if (latestData != null) {
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
              }
            }
          });
        }
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
      // Stop collection
      if (appState.demoModeEnabled) {
        activityProvider.demoService.stopMockCollection();
        _demoDataSubscription?.cancel();
        _demoDataSubscription = null;
        _demoDataTimer?.cancel();
        _demoDataTimer = null;
        setState(() {
          _isDemoCollecting = false;
          _demoCollectionStartTime = null;
        });
      } else {
        // Send stop_collection signal to server before disconnecting
        _websocketService!.sendStopCollection();

        // Wait briefly for server to process the signal
        await Future.delayed(Duration(milliseconds: 500));

        sensorDataProvider.stopCollection();
        _websocketService!.disconnect();
        _demoDataTimer?.cancel();
        _demoDataTimer = null;
      }
    }
  }

  Duration get _demoCollectionDuration {
    if (_demoCollectionStartTime == null) return Duration.zero;
    return DateTime.now().difference(_demoCollectionStartTime!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      body: Consumer<AppStateProvider>(
        builder: (context, appState, _) {
          // Check if motion capture is disabled from settings
          if (!appState.motionCaptureEnabled) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.storage_outlined,
                      size: 80,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Motion Capture Disabled',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Enable Motion Capture in Settings to start collecting labeled sensor data.',
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

          // Motion capture is enabled, show normal UI
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
              child: Consumer2<SensorDataProvider, AppStateProvider>(
                builder: (context, sensorData, appState, _) {
                  final isCollecting = _isCollecting(sensorData, appState);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Motion Capture Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8B5CF6), Color(0xFF9333EA)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.storage, color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        Text(
                          'Motion Capture',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Collection Status Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Collection Status',
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: isCollecting
                                        ? Color(0xFFEF4444)
                                        : Color(0xFF9CA3AF),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isCollecting ? 'Recording' : 'Stopped',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Duration',
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              appState.demoModeEnabled
                                  ? '${_demoCollectionDuration.inMinutes.toString().padLeft(2, '0')}:${(_demoCollectionDuration.inSeconds % 60).toString().padLeft(2, '0')}'
                                  : '${sensorData.collectionDuration.inMinutes.toString().padLeft(2, '0')}:${(sensorData.collectionDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Current Activity Badge (when recording)
                  if (isCollecting)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Color(0xFFDDEEFF),
                        border: Border.all(
                          color: Color(0xFFBFDBFE),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.bolt, color: Color(0xFF2563EB), size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Current Activity: ',
                            style: TextStyle(
                              color: Color(0xFF1E40AF),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            _getActivityDisplayName(_selectedActivityLabel),
                            style: TextStyle(
                              color: Color(0xFF1E40AF),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (isCollecting) const SizedBox(height: 12),

                  // Active Devices (for now showing only iPhone)
                  if (!isCollecting)
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
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.layers, color: Color(0xFF2563EB), size: 20),
                              const SizedBox(width: 12),
                              Text(
                                'Active Devices',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildDeviceCard('iPhone', Icons.phone_android, 87),
                            ],
                          ),
                        ],
                      ),
                    ),

                  if (!isCollecting) const SizedBox(height: 12),

                  // Select Activity to Record (when not recording)
                  if (!isCollecting)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
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
                        children: [
                          Text(
                            'Select Activity to Record',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 8),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                            childAspectRatio: 3.5,
                            children: [
                              _buildActivityButton('Walking', '🚶', 'walking'),
                              _buildActivityButton('Running', '🏃', 'running'),
                              _buildActivityButton('Sitting', '🪑', 'sitting'),
                              _buildActivityButton('Standing', '🧍', 'standing'),
                              _buildActivityButton('Jumping', '🦘', 'jumping'),
                              _buildActivityButton('Lying Down', '🛏️', 'lying_down'),
                            ],
                          ),
                        ],
                      ),
                    ),

                  if (!isCollecting) const SizedBox(height: 12),

                  // Start/Stop Recording Button
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
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
                    child: ElevatedButton(
                      onPressed: _toggleCollection,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCollecting
                            ? Color(0xFFDC2626)
                            : Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isCollecting ? Icons.pause : Icons.play_arrow,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isCollecting ? 'Stop Recording' : 'Start Recording',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Sensor Charts (when recording)
                  if (isCollecting) ...[
                    const SizedBox(height: 16),
                    _buildSensorChart('Accelerometer', sensorData),
                    const SizedBox(height: 16),
                    _buildSensorChart('Gyroscope', sensorData),
                  ],

                  const SizedBox(height: 12),

                  // Collection Statistics
                  Container(
                    width: double.infinity,
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
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              _showStatistics = !_showStatistics;
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
                                    Icon(Icons.bar_chart, color: Color(0xFF059669), size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Collection Statistics',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                  ],
                                ),
                                Icon(
                                  _showStatistics ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                  color: Color(0xFF9CA3AF),
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_showStatistics) ...[
                          Divider(height: 1, color: Color(0xFFF3F4F6)),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _buildStatRow(
                                  'Total Samples',
                                  appState.demoModeEnabled
                                      ? '$_demoSamplesCollected'
                                      : '${sensorData.packetsSent}',
                                ),
                                const SizedBox(height: 8),
                                _buildStatRow(
                                  'Duration',
                                  appState.demoModeEnabled
                                      ? '${_demoCollectionDuration.inMinutes.toString().padLeft(2, '0')}:${(_demoCollectionDuration.inSeconds % 60).toString().padLeft(2, '0')}'
                                      : '${sensorData.collectionDuration.inMinutes.toString().padLeft(2, '0')}:${(sensorData.collectionDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                                ),
                                const SizedBox(height: 8),
                                _buildStatRow('Sampling Rate', '50 Hz'),
                                const SizedBox(height: 8),
                                _buildStatRow('Sensors', 'Accelerometer, Gyroscope${appState.demoModeEnabled ? ' (Demo)' : ''}'),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeviceCard(String name, IconData icon, int battery) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Color(0xFF10B981), width: 2),
      ),
      child: Column(
        children: [
          Icon(icon, color: Color(0xFF059669), size: 20),
          const SizedBox(height: 8),
          Text(
            name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF047857),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.battery_std, color: Color(0xFF059669), size: 12),
              const SizedBox(width: 4),
              Text(
                '$battery%',
                style: TextStyle(
                  color: Color(0xFF059669),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivityButton(String label, String emoji, String value) {
    final isSelected = _selectedActivityLabel == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedActivityLabel = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFFDDEEFF) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Color(0xFF2563EB) : Color(0xFFE5E7EB),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Text(emoji, style: TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Color(0xFF2563EB) : Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorChart(String name, SensorDataProvider sensorData) {
    // Get the appropriate data lists based on sensor type
    List<double> xData, yData, zData;
    double minY, maxY;

    if (name == 'Accelerometer') {
      xData = _accelX;
      yData = _accelY;
      zData = _accelZ;
      // Accelerometer range: Y is around 9.81, X and Z are smaller
      minY = -2.0;
      maxY = 12.0;
    } else {
      xData = _gyroX;
      yData = _gyroY;
      zData = _gyroZ;
      // Gyroscope range: smaller rotational values
      minY = -0.5;
      maxY = 0.5;
    }

    // Convert to FlSpot format
    List<FlSpot> xSpots = [];
    List<FlSpot> ySpots = [];
    List<FlSpot> zSpots = [];

    for (int i = 0; i < xData.length; i++) {
      xSpots.add(FlSpot(i.toDouble(), xData[i]));
      ySpots.add(FlSpot(i.toDouble(), yData[i]));
      zSpots.add(FlSpot(i.toDouble(), zData[i]));
    }

    // Don't render chart until we have enough data - prevents initial animation
    // Wait for at least 10 data points for smooth appearance
    if (xSpots.isEmpty || xSpots.length < 10) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
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
            color: Colors.black.withOpacity(0.05),
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

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF6B7280),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF111827),
          ),
        ),
      ],
    );
  }

  String _getActivityDisplayName(String value) {
    switch (value) {
      case 'walking':
        return 'Walking';
      case 'running':
        return 'Running';
      case 'sitting':
        return 'Sitting';
      case 'standing':
        return 'Standing';
      case 'jumping':
        return 'Jumping';
      case 'lying_down':
        return 'Lying Down';
      default:
        return value;
    }
  }

  @override
  void dispose() {
    // Clean up timers and subscriptions
    _demoDataSubscription?.cancel();
    _demoDataTimer?.cancel();
    // Don't dispose the shared WebSocketService - it's managed by the provider
    super.dispose();
  }
}
