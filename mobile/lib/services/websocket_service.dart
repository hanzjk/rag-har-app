import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/sensor_data.dart';
import '../models/activity_type.dart';

enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
  reconnecting,
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
  final String? windowId; // Window ID for correlation with continuous collection

  ActivityPrediction({
    required this.activity,
    required this.timestamp,
    this.reasoning,
    this.fastInference = false,
    this.sensorData,
    this.windowId,
  });

  // JSON serialization for persistence
  Map<String, dynamic> toJson() => {
    'activity': activity.name,
    'timestamp': timestamp.toIso8601String(),
    'reasoning': reasoning,
    'fast_inference': fastInference,
    'sensor_data': sensorData?.map((s) => s.toJson()).toList(),
    'window_id': windowId,
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
      windowId: json['window_id'],
    );
  }
}

/// Window acknowledgment from server (for continuous collection tracking)
class WindowAcknowledgment {
  final String windowId;
  final DateTime timestamp;

  WindowAcknowledgment({required this.windowId, required this.timestamp});
}

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;
  final StreamController<ActivityPrediction> _activityController =
      StreamController<ActivityPrediction>.broadcast();
  final StreamController<ConnectionState> _connectionStateController =
      StreamController<ConnectionState>.broadcast();
  final StreamController<String> _messageController =
      StreamController<String>.broadcast();
  final StreamController<WindowAcknowledgment> _windowAckController =
      StreamController<WindowAcknowledgment>.broadcast();

  ConnectionState _connectionState = ConnectionState.disconnected;
  String? _lastUrl;

  // Reconnection settings
  bool _autoReconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _initialReconnectDelay = Duration(seconds: 1);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);
  Timer? _reconnectTimer;
  bool _isDisposed = false;

  Stream<ActivityPrediction> get activityStream => _activityController.stream;
  Stream<ConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  Stream<String> get messageStream => _messageController.stream;
  Stream<WindowAcknowledgment> get windowAckStream => _windowAckController.stream;
  ConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == ConnectionState.connected;

  /// Enable or disable automatic reconnection
  void setAutoReconnect(bool enabled) {
    _autoReconnect = enabled;
    if (!enabled) {
      _cancelReconnect();
    }
  }

  Future<void> connect(String url) async {
    // Skip if already connected to the same URL
    if (_connectionState == ConnectionState.connected && _channel != null && _lastUrl == url) {
      print('WebSocketService: Already connected to $url, skipping');
      return;
    }

    // Skip if already connecting
    if (_connectionState == ConnectionState.connecting) {
      print('WebSocketService: Already connecting, skipping');
      return;
    }

    _lastUrl = url;
    _cancelReconnect();
    await _connectInternal(url);
  }

  Future<void> _connectInternal(String url) async {
    // Clean up existing connection
    await _cleanupChannel();

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
      _reconnectAttempts = 0; // Reset on successful connection

      _channelSubscription = _channel!.stream.listen(
        (message) {
          print('WebSocketService: Received message: ${message.toString().substring(0, message.toString().length > 100 ? 100 : message.toString().length)}...');
          _handleIncomingMessage(message);
        },
        onError: (error) {
          print('WebSocketService: Stream error: $error');
          _handleDisconnection(wasError: true);
        },
        onDone: () {
          print('WebSocketService: Stream closed');
          _handleDisconnection(wasError: false);
        },
        cancelOnError: false,
      );
    } catch (e) {
      print('WebSocketService: Connection failed: $e');
      _updateConnectionState(ConnectionState.error);
      _channel = null;
      _scheduleReconnect();
      rethrow;
    }
  }

  void _handleDisconnection({required bool wasError}) {
    _updateConnectionState(wasError ? ConnectionState.error : ConnectionState.disconnected);
    _cleanupChannel();

    if (_autoReconnect && !_isDisposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_isDisposed || !_autoReconnect) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('WebSocketService: Max reconnection attempts reached ($_maxReconnectAttempts)');
      _updateConnectionState(ConnectionState.error);
      return;
    }

    // Exponential backoff with jitter
    final delay = _calculateReconnectDelay();
    _reconnectAttempts++;

    print('WebSocketService: Scheduling reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts in ${delay.inSeconds}s');
    _updateConnectionState(ConnectionState.reconnecting);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_lastUrl != null && !_isDisposed && _autoReconnect) {
        print('WebSocketService: Attempting reconnection...');
        _connectInternal(_lastUrl!).catchError((e) {
          print('WebSocketService: Reconnection attempt failed: $e');
        });
      }
    });
  }

  Duration _calculateReconnectDelay() {
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s... capped at 30s
    final exponentialDelay = _initialReconnectDelay * pow(2, _reconnectAttempts);
    final cappedDelay = exponentialDelay > _maxReconnectDelay ? _maxReconnectDelay : exponentialDelay;

    // Add jitter (±25%) to prevent thundering herd
    final jitter = (Random().nextDouble() * 0.5 - 0.25) * cappedDelay.inMilliseconds;
    return Duration(milliseconds: cappedDelay.inMilliseconds + jitter.toInt());
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> _cleanupChannel() async {
    _channelSubscription?.cancel();
    _channelSubscription = null;

    try {
      _channel?.sink.close();
    } catch (e) {
      print('WebSocketService: Error closing channel: $e');
    }
    _channel = null;
  }

  /// Send data with error handling and state update on failure
  bool _safeSend(String data, String operationName) {
    if (_connectionState != ConnectionState.connected || _channel == null) {
      print('WebSocketService: Cannot send $operationName - not connected');
      return false;
    }

    try {
      _channel!.sink.add(data);
      return true;
    } catch (e) {
      print('WebSocketService: Error sending $operationName: $e');
      // Connection likely broken, trigger disconnection handling
      _handleDisconnection(wasError: true);
      return false;
    }
  }

  void sendSensorData(SensorData data) {
    final jsonData = jsonEncode(data.toJson());
    _safeSend(jsonData, 'sensor_data');
  }

  void sendStopCollection() {
    final stopMessage = jsonEncode({
      'type': 'stop_collection',
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_safeSend(stopMessage, 'stop_collection')) {
      print('WebSocketService: Sent stop_collection signal');
    }
  }

  void sendPing() {
    final pingMessage = jsonEncode({
      'type': 'ping',
      'timestamp': DateTime.now().toIso8601String(),
    });
    _safeSend(pingMessage, 'ping');
  }

  void _handleIncomingMessage(dynamic message) {
    try {
      // Emit raw message to stream
      _messageController.add(message.toString());

      final data = jsonDecode(message.toString());
      final messageType = data['type'];

      // Handle window acknowledgment (for continuous collection)
      if (messageType == 'window_received') {
        final windowId = data['window_id'] as String;
        print('WebSocketService: Window $windowId acknowledged by server');
        _windowAckController.add(WindowAcknowledgment(
          windowId: windowId,
          timestamp: DateTime.now(),
        ));
        return;
      }

      String? activity;
      String? reasoning;
      String? windowId;
      bool fastInference = false;

      if (messageType == 'activity_prediction') {
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
        windowId = data['window_id'];  // Extract window_id for correlation
      } else if (data.containsKey('prediction')) {
        activity = data['prediction'];
        reasoning = data['reasoning'];  // Extract reasoning if present
        fastInference = data['fast_inference'] ?? false;
      }

      if (activity != null) {
        final reasoningPreview = reasoning != null
            ? reasoning.substring(0, reasoning.length > 50 ? 50 : reasoning.length)
            : 'none';
        print('WebSocketService: Adding prediction to activityStream: $activity (windowId: $windowId, fastInference: $fastInference, reasoning: $reasoningPreview...)');
        _activityController.add(
          ActivityPrediction(
            activity: ActivityType.fromString(activity),
            timestamp: DateTime.now(),
            reasoning: reasoning,
            fastInference: fastInference,
            windowId: windowId,
          ),
        );
        print('WebSocketService: Prediction added to activityStream');
      }
    } catch (e, stackTrace) {
      // Log parsing errors instead of silently swallowing them
      print('WebSocketService: Error parsing incoming message: $e');
      print('WebSocketService: Message was: ${message.toString().substring(0, min(200, message.toString().length))}');
      print('WebSocketService: Stack trace: $stackTrace');
    }
  }

  void _updateConnectionState(ConnectionState state) {
    if (_connectionState != state) {
      print('WebSocketService: Connection state changed: $_connectionState -> $state');
      _connectionState = state;
      _connectionStateController.add(state);
    }
  }

  void disconnect() {
    _autoReconnect = false; // Disable auto-reconnect on manual disconnect
    _cancelReconnect();
    _cleanupChannel();
    _updateConnectionState(ConnectionState.disconnected);
  }

  /// Reset reconnection state (call when user manually triggers reconnect)
  void resetReconnection() {
    _reconnectAttempts = 0;
    _autoReconnect = true;
  }

  // ==================== Data Store Management ====================

  void createDatastore(String name) {
    final message = jsonEncode({
      'type': 'create_datastore',
      'name': name,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_safeSend(message, 'create_datastore')) {
      print('WebSocketService: Sent create_datastore request for: $name');
    }
  }

  void deleteDatastore(String collectionName) {
    final message = jsonEncode({
      'type': 'delete_datastore',
      'collection_name': collectionName,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_safeSend(message, 'delete_datastore')) {
      print('WebSocketService: Sent delete_datastore request for: $collectionName');
    }
  }

  void listDatastores() {
    final message = jsonEncode({
      'type': 'list_datastores',
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_safeSend(message, 'list_datastores')) {
      print('WebSocketService: Sent list_datastores request');
    }
  }

  void setDatastore(String collectionName) {
    final message = jsonEncode({
      'type': 'set_datastore',
      'collection_name': collectionName,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_safeSend(message, 'set_datastore')) {
      print('WebSocketService: Sent set_datastore request for: $collectionName');
    }
  }

  void getCurrentDatastore() {
    final message = jsonEncode({
      'type': 'get_current_datastore',
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_safeSend(message, 'get_current_datastore')) {
      print('WebSocketService: Sent get_current_datastore request');
    }
  }

  void dispose() {
    _isDisposed = true;
    _autoReconnect = false;
    _cancelReconnect();
    _cleanupChannel();
    _activityController.close();
    _connectionStateController.close();
    _messageController.close();
    _windowAckController.close();
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
