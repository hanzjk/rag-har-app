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

// Sensor data snapshot for a single point in time
class SensorSnapshot {
  final double accelX, accelY, accelZ;
  final double gyroX, gyroY, gyroZ;

  SensorSnapshot({
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
  });

  Map<String, dynamic> toJson() => {
    'ax': accelX, 'ay': accelY, 'az': accelZ,
    'gx': gyroX, 'gy': gyroY, 'gz': gyroZ,
  };

  factory SensorSnapshot.fromJson(Map<String, dynamic> json) {
    return SensorSnapshot(
      accelX: (json['ax'] as num).toDouble(),
      accelY: (json['ay'] as num).toDouble(),
      accelZ: (json['az'] as num).toDouble(),
      gyroX: (json['gx'] as num).toDouble(),
      gyroY: (json['gy'] as num).toDouble(),
      gyroZ: (json['gz'] as num).toDouble(),
    );
  }
}

class ActivityPrediction {
  final ActivityType activity;
  final DateTime timestamp;
  final String? reasoning;
  final bool fastInference;
  final List<SensorSnapshot>? sensorData; // Sensor data window for this prediction

  ActivityPrediction({
    required this.activity,
    required this.timestamp,
    this.reasoning,
    this.fastInference = false,
    this.sensorData,
  });

  // JSON serialization for persistence
  Map<String, dynamic> toJson() => {
    'activity': activity.name,
    'timestamp': timestamp.toIso8601String(),
    'reasoning': reasoning,
    'fast_inference': fastInference,
    'sensor_data': sensorData?.map((s) => s.toJson()).toList(),
  };

  factory ActivityPrediction.fromJson(Map<String, dynamic> json) {
    List<SensorSnapshot>? sensorData;
    if (json['sensor_data'] != null) {
      sensorData = (json['sensor_data'] as List)
          .map((s) => SensorSnapshot.fromJson(s))
          .toList();
    }
    return ActivityPrediction(
      activity: ActivityType.values.firstWhere(
        (e) => e.name == json['activity'],
        orElse: () => ActivityType.unknown,
      ),
      timestamp: DateTime.parse(json['timestamp']),
      reasoning: json['reasoning'],
      fastInference: json['fast_inference'] ?? false,
      sensorData: sensorData,
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
    // Skip if already connected
    if (_connectionState == ConnectionState.connected && _channel != null) {
      print('WebSocketService: Already connected, skipping');
      return;
    }

    // Skip if already connecting
    if (_connectionState == ConnectionState.connecting) {
      print('WebSocketService: Already connecting, skipping');
      return;
    }

    // Clear any existing failed channel (don't await close - it may hang)
    if (_channel != null) {
      print('WebSocketService: Clearing previous channel');
      _channel = null;
    }

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

  // ==================== Data Store Management ====================

  void createDatastore(String name) {
    if (_connectionState == ConnectionState.connected && _channel != null) {
      try {
        final message = jsonEncode({
          'type': 'create_datastore',
          'name': name,
          'timestamp': DateTime.now().toIso8601String(),
        });
        _channel!.sink.add(message);
        print('WebSocketService: Sent create_datastore request for: $name');
      } catch (e) {
        print('WebSocketService: Error sending create_datastore: $e');
      }
    }
  }

  void deleteDatastore(String collectionName) {
    if (_connectionState == ConnectionState.connected && _channel != null) {
      try {
        final message = jsonEncode({
          'type': 'delete_datastore',
          'collection_name': collectionName,
          'timestamp': DateTime.now().toIso8601String(),
        });
        _channel!.sink.add(message);
        print('WebSocketService: Sent delete_datastore request for: $collectionName');
      } catch (e) {
        print('WebSocketService: Error sending delete_datastore: $e');
      }
    }
  }

  void listDatastores() {
    if (_connectionState == ConnectionState.connected && _channel != null) {
      try {
        final message = jsonEncode({
          'type': 'list_datastores',
          'timestamp': DateTime.now().toIso8601String(),
        });
        _channel!.sink.add(message);
        print('WebSocketService: Sent list_datastores request');
      } catch (e) {
        print('WebSocketService: Error sending list_datastores: $e');
      }
    }
  }

  void setDatastore(String collectionName) {
    if (_connectionState == ConnectionState.connected && _channel != null) {
      try {
        final message = jsonEncode({
          'type': 'set_datastore',
          'collection_name': collectionName,
          'timestamp': DateTime.now().toIso8601String(),
        });
        _channel!.sink.add(message);
        print('WebSocketService: Sent set_datastore request for: $collectionName');
      } catch (e) {
        print('WebSocketService: Error sending set_datastore: $e');
      }
    }
  }

  void getCurrentDatastore() {
    if (_connectionState == ConnectionState.connected && _channel != null) {
      try {
        final message = jsonEncode({
          'type': 'get_current_datastore',
          'timestamp': DateTime.now().toIso8601String(),
        });
        _channel!.sink.add(message);
        print('WebSocketService: Sent get_current_datastore request');
      } catch (e) {
        print('WebSocketService: Error sending get_current_datastore: $e');
      }
    }
  }

  void dispose() {
    disconnect();
    _activityController.close();
    _connectionStateController.close();
    _messageController.close();
  }
}

// ==================== Data Store Model ====================

class DataStore {
  final String name;
  final String collectionName;
  final int sampleCount;
  final bool isDefault;
  final bool isActive;

  DataStore({
    required this.name,
    required this.collectionName,
    required this.sampleCount,
    required this.isDefault,
    required this.isActive,
  });

  factory DataStore.fromJson(Map<String, dynamic> json) {
    return DataStore(
      name: json['name'] ?? '',
      collectionName: json['collection_name'] ?? '',
      sampleCount: json['sample_count'] ?? 0,
      isDefault: json['is_default'] ?? false,
      isActive: json['is_active'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'collection_name': collectionName,
    'sample_count': sampleCount,
    'is_default': isDefault,
    'is_active': isActive,
  };
}
