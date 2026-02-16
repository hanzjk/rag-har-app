import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state_provider.dart';
import 'providers/sensor_data_provider.dart';
import 'providers/activity_provider.dart';
import 'providers/device_info_provider.dart';
import 'services/sensor_service.dart';
import 'services/websocket_service.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Create services once and reuse them
  final WebSocketService _websocketService = WebSocketService();
  final AppStateProvider _appStateProvider = AppStateProvider();
  final SensorService _sensorService = SensorService(normalizeOrientation: false);
  late final ActivityProvider _activityProvider = ActivityProvider(websocketService: _websocketService);

  @override
  void initState() {
    super.initState();

    // Listen for settings changes and start demo mode when ready
    _appStateProvider.addListener(_checkAndStartDemoMode);

    // Also check immediately after first frame in case settings are already loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndStartDemoMode();
    });
  }

  void _checkAndStartDemoMode() {
    // Only manage demo mode here - don't interfere with real mode
    if (_appStateProvider.demoModeEnabled &&
        _appStateProvider.activityRecognitionEnabled &&
        !_activityProvider.isListening) {
      print('🎮 main.dart: Starting demo mode predictions');
      _activityProvider.startListening(demoMode: true);
    } else if (_appStateProvider.demoModeEnabled &&
        !_appStateProvider.activityRecognitionEnabled &&
        _activityProvider.isListening) {
      // Stop demo mode if activity recognition is disabled
      print('🛑 main.dart: Stopping demo mode predictions');
      _activityProvider.stopListening();
    }
    // Note: Real mode (non-demo) is managed by HomeTabScreen, not here
  }

  @override
  void dispose() {
    _appStateProvider.removeListener(_checkAndStartDemoMode);
    _activityProvider.dispose();
    _websocketService.dispose();
    _appStateProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _appStateProvider),
        ChangeNotifierProvider(
          create: (_) => SensorDataProvider(
            sensorService: _sensorService,
            websocketService: _websocketService,
          ),
        ),
        ChangeNotifierProvider.value(value: _activityProvider),
        ChangeNotifierProvider(
          create: (_) => DeviceInfoProvider(),
        ),
      ],
      child: MaterialApp(
        title: 'FitTrack',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2563EB),
            primary: const Color(0xFF2563EB),
            secondary: const Color(0xFF9333EA),
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
