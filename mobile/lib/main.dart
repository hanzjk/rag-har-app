import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state_provider.dart';
import 'providers/sensor_data_provider.dart';
import 'providers/activity_provider.dart';
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
  // Create WebSocketService once and reuse it
  late final WebSocketService _websocketService;
  late final AppStateProvider _appStateProvider;
  late final SensorService _sensorService;

  @override
  void initState() {
    super.initState();
    _websocketService = WebSocketService();
    _appStateProvider = AppStateProvider();
    _sensorService = SensorService(); // Always use real sensors
  }

  @override
  void dispose() {
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
        ChangeNotifierProvider(
          create: (_) => ActivityProvider(
            websocketService: _websocketService,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Activity Recognition',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
