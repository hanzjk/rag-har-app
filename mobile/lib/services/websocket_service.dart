import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/sensor_data.dart';
import '../models/activity_type.dart';

enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class ActivityPrediction {
  final ActivityType activity;
  final double confidence;
  final DateTime timestamp;

  ActivityPrediction({
    required this.activity,
    required this.confidence,
    required this.timestamp,
  });
}

class WebSocketService {
  WebSocketChannel? _channel;
  final StreamController<ActivityPrediction> _activityController =
      StreamController<ActivityPrediction>.broadcast();
  final StreamController<ConnectionState> _connectionStateController =
      StreamController<ConnectionState>.broadcast();

  ConnectionState _connectionState = ConnectionState.disconnected;

  Stream<ActivityPrediction> get activityStream => _activityController.stream;
  Stream<ConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  ConnectionState get connectionState => _connectionState;

  Future<void> connect(String url) async {
    try {
      print('WebSocketService: Attempting to connect to $url');
      _updateConnectionState(ConnectionState.connecting);

      final uri = Uri.parse(url);
      print('WebSocketService: Parsed URI - scheme: ${uri.scheme}, host: ${uri.host}, port: ${uri.port}, path: ${uri.path}');

      _channel = WebSocketChannel.connect(uri);
      print('WebSocketService: Channel created, waiting for ready...');

      // Add timeout to prevent hanging indefinitely
      await _channel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Connection timeout after 10 seconds');
        },
      );
      print('WebSocketService: Connection ready!');

      _updateConnectionState(ConnectionState.connected);

      _channel!.stream.listen(
        (message) {
          print('WebSocketService: Received message: ${message.toString().substring(0, message.toString().length > 100 ? 100 : message.toString().length)}...');
          _handleIncomingMessage(message);
        },
        onError: (error) {
          print('WebSocketService: Stream error: $error');
          _updateConnectionState(ConnectionState.error);
        },
        onDone: () {
          print('WebSocketService: Stream closed');
          _updateConnectionState(ConnectionState.disconnected);
        },
      );
    } catch (e) {
      print('WebSocketService: Connection failed: $e');
      _updateConnectionState(ConnectionState.error);
      rethrow;
    }
  }

  void sendSensorData(SensorData data) {
    if (_connectionState == ConnectionState.connected && _channel != null) {
      try {
        final jsonData = jsonEncode(data.toJson());
        _channel!.sink.add(jsonData);
      } catch (e) {
        print('WebSocketService: Error sending sensor data: $e');
      }
    }
  }

  void _handleIncomingMessage(dynamic message) {
    try {
      final data = jsonDecode(message.toString());

      String? activity;
      double? confidence;

      if (data['type'] == 'activity_prediction') {
        // Skip buffering/initializing predictions
        final status = data['status'];
        final activityName = data['activity'];

        if (status == 'buffering' || activityName == 'initializing') {
          // Don't add buffering predictions to stream
          return;
        }

        activity = activityName;
        confidence = (data['confidence'] as num?)?.toDouble();
      } else if (data.containsKey('prediction')) {
        activity = data['prediction'];
        confidence = (data['probability'] as num?)?.toDouble();
      }

      if (activity != null) {
        _activityController.add(
          ActivityPrediction(
            activity: ActivityType.fromString(activity),
            confidence: confidence ?? 0.0,
            timestamp: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      // Error parsing incoming message: $e
    }
  }

  void _updateConnectionState(ConnectionState state) {
    _connectionState = state;
    _connectionStateController.add(state);
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _updateConnectionState(ConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _activityController.close();
    _connectionStateController.close();
  }
}
