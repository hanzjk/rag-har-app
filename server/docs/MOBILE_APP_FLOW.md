# Mobile App Data Streaming Flow

This document explains how the Flutter mobile app streams sensor data to the server.

## Mobile App Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Data Collection Screen (UI)                            │
│  - User taps "Start"                                    │
│  - User selects activity label                          │
└──────────────────┬──────────────────────────────────────┘
                   │
                   │ Calls startCollection()
                   ▼
┌─────────────────────────────────────────────────────────┐
│  SensorDataProvider (State Management)                  │
│  - Manages collection state                             │
│  - Coordinates sensor service & WebSocket service       │
└──────────┬──────────────────────┬───────────────────────┘
           │                      │
           │                      │
           ▼                      ▼
┌──────────────────────┐   ┌──────────────────────────────┐
│  SensorService       │   │  WebSocketService            │
│  - Reads sensors     │   │  - Maintains connection      │
│  - Emits stream      │   │  - Sends JSON packets        │
│  - 20 Hz sampling    │   │  - Receives responses        │
└──────────────────────┘   └──────────────────────────────┘
           │                      │
           │ SensorData stream    │ WebSocket channel
           ▼                      ▼
     Device Sensors         Network (WiFi)
```

## Code Flow Step-by-Step

### Step 1: User Taps "Start"

**File: `mobile/lib/screens/data_collection_screen.dart:62`**

```dart
Future<void> _toggleCollection() async {
  final sensorDataProvider = context.read<SensorDataProvider>();
  final appState = context.read<AppStateProvider>();

  if (!sensorDataProvider.isCollecting) {
    // 1. Connect to WebSocket server
    await _websocketService.connect(appState.websocketUrl);
    //    ↑ Opens persistent connection to ws://192.168.1.100:8000/ws

    // 2. Set the activity label
    sensorDataProvider.setActivityLabel(_selectedActivityLabel);
    //    ↑ Sets label to "walking" (user selected)

    // 3. Start collecting sensor data
    sensorDataProvider.startCollection();
    //    ↑ Starts sensor streaming at 20 Hz
  }
}
```

### Step 2: SensorDataProvider Starts Streaming

**File: `mobile/lib/providers/sensor_data_provider.dart:40`**

```dart
void startCollection() {
  _isCollecting = true;
  _collectionStartTime = DateTime.now();

  // Subscribe to sensor stream (20 Hz)
  _subscription = _sensorService.getSensorStream().listen((data) {
    //                                  ↑
    //  This is called 20 times per second with fresh sensor data

    // Create labeled sensor data
    final labeledData = SensorData(
      timestamp: data.timestamp,
      accelerometer: data.accelerometer,
      gyroscope: data.gyroscope,
      magnetometer: data.magnetometer,
      activityLabel: _currentActivityLabel,  // ← "walking"
    );

    // Send to WebSocket server
    _websocketService.sendSensorData(labeledData);
    //    ↑ Sends JSON packet to server

    _packetsSent++;  // Increment counter for UI
    notifyListeners();  // Update UI
  });
}
```

### Step 3: Sensor Service Emits Data Stream

**File: `mobile/lib/services/sensor_service.dart` (conceptual)**

```dart
class SensorService {
  Stream<SensorData> getSensorStream() {
    // Combine three sensor streams
    return Rx.combineLatest3(
      accelerometerEvents,     // Built-in Android sensor stream
      gyroscopeEvents,         // Built-in Android sensor stream
      magnetometerEvents,      // Built-in Android sensor stream
      (accel, gyro, mag) {
        // This callback fires when all 3 sensors have new data
        // Happens ~20 times per second

        return SensorData.fromSensorEvents(
          accelerometerEvent: accel,
          gyroscopeEvent: gyro,
          magnetometerEvent: mag,
        );
      },
    ).throttleTime(
      Duration(milliseconds: 50),  // ← 20 Hz = 1/0.05 = 20 per second
    );
  }
}
```

### Step 4: WebSocket Service Sends Data

**File: `mobile/lib/services/websocket_service.dart:67`**

```dart
void sendSensorData(SensorData data) {
  if (_connectionState == ConnectionState.connected && _channel != null) {
    // Convert SensorData object to JSON
    final jsonData = jsonEncode(data.toJson());
    //    ↑
    // Produces: '{"type":"sensor_data","timestamp":"...","activity":"walking",...}'

    // Send through WebSocket
    _channel!.sink.add(jsonData);
    //         ↑
    // Sends JSON string to server through open WebSocket connection
  }
}
```

### Step 5: SensorData Serialization

**File: `mobile/lib/models/sensor_data.dart:43`**

```dart
class SensorData {
  final DateTime timestamp;
  final SensorReading accelerometer;
  final SensorReading gyroscope;
  final SensorReading magnetometer;
  final String? activityLabel;

  Map<String, dynamic> toJson() {
    final json = {
      'type': 'sensor_data',
      'timestamp': timestamp.toIso8601String(),  // "2025-12-26T10:30:45.123Z"
      'data': {
        'accelerometer': accelerometer.toJson(),  // {x: 0.123, y: 9.81, z: 0.045}
        'gyroscope': gyroscope.toJson(),          // {x: 0.001, y: -0.002, z: 0.0}
        'magnetometer': magnetometer.toJson(),    // {x: 23.4, y: -12.1, z: 45.6}
      }
    };

    if (activityLabel != null) {
      json['activity'] = activityLabel!;  // "walking"
    }

    return json;
  }
}
```

## Timeline of Events (First 1 Second)

```
Time    Event                                     Code Location
────────────────────────────────────────────────────────────────────────────
00.000  User taps "Start" button                  data_collection_screen.dart:217
00.010  Connect to WebSocket                      websocket_service.dart:40
00.050  WebSocket connected ✓                     websocket_service.dart:46
00.050  Set activity label to "walking"           sensor_data_provider.dart:35
00.050  Start sensor stream subscription          sensor_data_provider.dart:40

        ┌──────────── Streaming Loop Begins ────────────┐

00.050  Sensor reading #1                         sensor_service.dart
        ├─ Accelerometer: (0.245, 9.812, 0.123)
        ├─ Gyroscope: (0.012, -0.023, 0.005)
        └─ Magnetometer: (23.4, -12.1, 45.6)

00.051  Create SensorData object                  sensor_data_provider.dart:49
00.052  Serialize to JSON                         sensor_data.dart:43
00.053  Send via WebSocket                        websocket_service.dart:71
00.054  Server receives packet #1                 [SERVER SIDE]

00.100  Sensor reading #2                         (50ms later)
00.101  Create SensorData object
00.102  Serialize to JSON
00.103  Send via WebSocket
00.104  Server receives packet #2

00.150  Sensor reading #3
        ...

00.950  Sensor reading #20
01.000  ← End of first second                     (20 packets sent)
```

## Data Flow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│  Android Device Sensors (Hardware)                               │
│  - Accelerometer: Measures acceleration (m/s²)                   │
│  - Gyroscope: Measures rotation (rad/s)                          │
│  - Magnetometer: Measures magnetic field (µT)                    │
└───────────┬──────────────────────────────────────────────────────┘
            │
            │ Native Android Sensor API
            │ (continuous stream, ~100+ Hz raw)
            ▼
┌──────────────────────────────────────────────────────────────────┐
│  sensors_plus Flutter Plugin                                     │
│  - Wraps Android sensor API                                      │
│  - Exposes Dart streams                                          │
└───────────┬──────────────────────────────────────────────────────┘
            │
            │ Dart Stream<AccelerometerEvent>
            │ Dart Stream<GyroscopeEvent>
            │ Dart Stream<MagnetometerEvent>
            ▼
┌──────────────────────────────────────────────────────────────────┐
│  SensorService                                                   │
│  - Combines 3 streams into 1                                     │
│  - Throttles to 20 Hz (50ms intervals)                           │
│  - Emits: Stream<SensorData>                                     │
└───────────┬──────────────────────────────────────────────────────┘
            │
            │ 20 SensorData objects per second
            │
            ▼
┌──────────────────────────────────────────────────────────────────┐
│  SensorDataProvider (listening to stream)                        │
│                                                                   │
│  _subscription.listen((data) {                                   │
│    final labeled = SensorData(                                   │
│      ...data fields,                                             │
│      activityLabel: "walking"  ← Add label                       │
│    );                                                             │
│    websocketService.sendSensorData(labeled);                     │
│  });                                                              │
└───────────┬──────────────────────────────────────────────────────┘
            │
            │ SensorData object with label
            │
            ▼
┌──────────────────────────────────────────────────────────────────┐
│  SensorData.toJson()                                             │
│  - Converts object to Map<String, dynamic>                       │
│  - Nested structure preserved                                    │
└───────────┬──────────────────────────────────────────────────────┘
            │
            │ Map<String, dynamic>
            │
            ▼
┌──────────────────────────────────────────────────────────────────┐
│  jsonEncode() [Dart's built-in JSON encoder]                     │
│  - Converts Map to JSON string                                   │
└───────────┬──────────────────────────────────────────────────────┘
            │
            │ String (JSON format)
            │
            ▼
┌──────────────────────────────────────────────────────────────────┐
│  WebSocketService                                                │
│  - _channel.sink.add(jsonString)                                 │
│  - Writes to WebSocket output stream                             │
└───────────┬──────────────────────────────────────────────────────┘
            │
            │ Raw bytes over network
            │
            ▼
┌──────────────────────────────────────────────────────────────────┐
│  Network (WiFi)                                                  │
│  - TCP/IP packets                                                │
│  - WebSocket framing                                             │
└───────────┬──────────────────────────────────────────────────────┘
            │
            │ Arrives at server
            │
            ▼
   [SERVER RECEIVES]
```

## Example: What's Sent Over the Wire

**Dart object in memory:**
```dart
SensorData(
  timestamp: DateTime(2025, 12, 26, 10, 30, 45, 123),
  accelerometer: SensorReading(x: 0.245, y: 9.812, z: 0.123),
  gyroscope: SensorReading(x: 0.012, y: -0.023, z: 0.005),
  magnetometer: SensorReading(x: 23.4, y: -12.1, z: 45.6),
  activityLabel: "walking"
)
```

**After `toJson()`:**
```dart
{
  'type': 'sensor_data',
  'timestamp': '2025-12-26T10:30:45.123Z',
  'activity': 'walking',
  'data': {
    'accelerometer': {'x': 0.245, 'y': 9.812, 'z': 0.123},
    'gyroscope': {'x': 0.012, 'y': -0.023, 'z': 0.005},
    'magnetometer': {'x': 23.4, 'y': -12.1, 'z': 45.6}
  }
}
```

**After `jsonEncode()` (what's sent):**
```json
{"type":"sensor_data","timestamp":"2025-12-26T10:30:45.123Z","activity":"walking","data":{"accelerometer":{"x":0.245,"y":9.812,"z":0.123},"gyroscope":{"x":0.012,"y":-0.023,"z":0.005},"magnetometer":{"x":23.4,"y":-12.1,"z":45.6}}}
```

**Size:** ~280 bytes per packet

**At 20 Hz:** 280 bytes × 20 = 5.6 KB per second

## Receiving Server Response

**Server sends back (in collect mode):**

```json
{
  "type": "collection_ack",
  "samples_collected": 42,
  "activity": "walking",
  "timestamp": "2025-12-26T10:30:47.123Z"
}
```

**Mobile app receives:**

```dart
// In websocket_service.dart:50
_channel!.stream.listen((message) {
  _handleIncomingMessage(message);
});

void _handleIncomingMessage(dynamic message) {
  final data = jsonDecode(message.toString());
  // data = {'type': 'collection_ack', 'samples_collected': 42, ...}

  // In this case, it's an acknowledgment (not a prediction)
  // So we can log it or ignore it
  // The UI already shows packetsSent counter
}
```

**Server sends back (in predict mode):**

```json
{
  "type": "activity_prediction",
  "activity": "walking",
  "confidence": 0.80,
  "timestamp": "2025-12-26T10:30:47.124Z"
}
```

**Mobile app receives and displays:**

```dart
void _handleIncomingMessage(dynamic message) {
  final data = jsonDecode(message);

  if (data['type'] == 'activity_prediction') {
    final activity = data['activity'];  // "walking"
    final confidence = data['confidence'];  // 0.80

    _activityController.add(
      ActivityPrediction(
        activity: ActivityType.fromString(activity),
        confidence: confidence,
        timestamp: DateTime.now(),
      )
    );
    // ↑ This updates the UI to show "Walking (80%)"
  }
}
```

## Performance Characteristics

### Memory Usage (Mobile App)
- **SensorService**: ~1 MB (sensor buffers)
- **WebSocket**: ~100 KB (connection overhead)
- **UI state**: ~10 KB
- **Total**: ~1-2 MB

### Battery Impact
- **Sensors at 20 Hz**: Low (optimized by Android)
- **WiFi continuous**: Moderate
- **Screen on**: High (normal)
- **Total**: ~5-10% battery per hour

### Network Usage
- **Upload**: 5.6 KB/s
- **Download**: ~100 bytes/s (acknowledgments)
- **Total**: ~6 KB/s = 360 KB/minute = 21 MB/hour

### CPU Usage
- **Sensor reading**: ~5% (hardware accelerated)
- **JSON serialization**: ~2%
- **Network I/O**: ~1%
- **UI updates**: ~5%
- **Total**: ~10-15% CPU

## Error Handling

**What if WebSocket disconnects?**

```dart
// In websocket_service.dart:54
_channel!.stream.listen(
  (message) { ... },
  onError: (error) {
    _updateConnectionState(ConnectionState.error);
    // UI shows red banner: "Connection Lost"
  },
  onDone: () {
    _updateConnectionState(ConnectionState.disconnected);
    // Auto-stop collection
  },
);
```

**What if server is slow?**
- WebSocket has internal buffering
- If buffer fills, packets may be dropped
- Solution: Server should process fast enough (CSV writing is fast)

**What if network is unstable?**
- WebSocket will attempt to maintain connection
- If connection drops, data collection stops automatically
- User must restart collection when connection restored

## Summary

The mobile app:
1. **Reads sensors** at 20 Hz using Android's sensor API
2. **Labels data** with user-selected activity
3. **Serializes** to JSON format
4. **Streams** continuously via WebSocket
5. **Receives** acknowledgments or predictions back
6. **Updates UI** in real-time

All of this happens **asynchronously** and **efficiently** with minimal battery and network impact!
