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
  final DateTime timestamp;
  final String? reasoning;
  final bool fastInference;

  ActivityPrediction({
    required this.activity,
    required this.timestamp,
    this.reasoning,
    this.fastInference = false,
  });

  // JSON serialization for persistence
  Map<String, dynamic> toJson() => {
    'activity': activity.name,
    'timestamp': timestamp.toIso8601String(),
    'reasoning': reasoning,
    'fast_inference': fastInference,
  };

  factory ActivityPrediction.fromJson(Map<String, dynamic> json) {
    return ActivityPrediction(
      activity: ActivityType.values.firstWhere(
        (e) => e.name == json['activity'],
        orElse: () => ActivityType.unknown,
      ),
      timestamp: DateTime.parse(json['timestamp']),
      reasoning: json['reasoning'],
      fastInference: json['fast_inference'] ?? false,
    );
  }
}

class WebSocketService {
  WebSocketChannel? _channel;
  final StreamController<ActivityPrediction> _activityController =
      StreamController<ActivityPrediction>.broadcast();
  final StreamController<ConnectionState> _connectionStateController =
      StreamController<ConnectionState>.broadcast();
  final StreamController<String> _messageController =
      StreamController<String>.broadcast();

  ConnectionState _connectionState = ConnectionState.disconnected;

  Stream<ActivityPrediction> get activityStream => _activityController.stream;
  Stream<ConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  Stream<String> get messageStream => _messageController.stream;
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

  void sendStopCollection() {
    if (_connectionState == ConnectionState.connected && _channel != null) {
      try {
        final stopMessage = jsonEncode({
          'type': 'stop_collection',
          'timestamp': DateTime.now().toIso8601String(),
        });
        _channel!.sink.add(stopMessage);
        print('WebSocketService: Sent stop_collection signal');
      } catch (e) {
        print('WebSocketService: Error sending stop_collection: $e');
      }
    }
  }

  void sendPing() {
    if (_connectionState == ConnectionState.connected && _channel != null) {
      try {
        final pingMessage = jsonEncode({
          'type': 'ping',
          'timestamp': DateTime.now().toIso8601String(),
        });
        _channel!.sink.add(pingMessage);
      } catch (e) {
        print('WebSocketService: Error sending ping: $e');
      }
    }
  }

  void _handleIncomingMessage(dynamic message) {
    try {
      // Emit raw message to stream
      _messageController.add(message.toString());

      final data = jsonDecode(message.toString());

      String? activity;
      String? reasoning;
      bool fastInference = false;

      if (data['type'] == 'activity_prediction') {
        // Skip buffering/initializing predictions
        final status = data['status'];
        final activityName = data['activity'];

        if (status == 'buffering' || activityName == 'initializing') {
          // Don't add buffering predictions to stream
          return;
        }

        activity = activityName;
        reasoning = data['reasoning'];  // Extract reasoning if present
        fastInference = data['fast_inference'] ?? false;
      } else if (data.containsKey('prediction')) {
        activity = data['prediction'];
        reasoning = data['reasoning'];  // Extract reasoning if present
        fastInference = data['fast_inference'] ?? false;
      }

      if (activity != null) {
        print('🎯 Adding prediction to activityStream: $activity (fastInference: $fastInference, reasoning: ${reasoning?.substring(0, reasoning.length > 50 ? 50 : reasoning.length)}...)');
        _activityController.add(
          ActivityPrediction(
            activity: ActivityType.fromString(activity),
            timestamp: DateTime.now(),
            reasoning: reasoning,
            fastInference: fastInference,
          ),
        );
        print('✅ Prediction added to activityStream');
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
    _messageController.close();
  }
}
