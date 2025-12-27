import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state_provider.dart';
import 'providers/sensor_data_provider.dart';
import 'providers/activity_provider.dart';
import 'services/sensor_service.dart';
import 'services/demo_sensor_service.dart';
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

  @override
  void initState() {
    super.initState();
    _websocketService = WebSocketService();
    _appStateProvider = AppStateProvider();
  }

  @override
  void dispose() {
    _websocketService.dispose();
    _appStateProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _appStateProvider,
      child: Consumer<AppStateProvider>(
        builder: (context, appState, _) {
          final sensorService = appState.isDemoMode
              ? DemoSensorService()
              : SensorService();

          return MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: appState),
              ChangeNotifierProvider(
                create: (_) => SensorDataProvider(
                  sensorService: sensorService,
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
        },
      ),
    );
  }
}
