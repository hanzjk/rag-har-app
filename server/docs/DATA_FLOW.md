# Data Flow Explanation

## Overview: How Sensor Data Flows from Mobile App to Server

```
Mobile App                WebSocket                Server
┌─────────┐              ┌─────────┐           ┌──────────┐
│ Sensors │──streaming──▶│  Live   │──receive─▶│ Process  │
│ (20 Hz) │   JSON       │ Channel │   JSON    │ & Store  │
└─────────┘              └─────────┘           └──────────┘
```

## Step-by-Step Data Flow

### 1. Mobile App Side (Data Collection Screen)

**What happens:**
1. User opens Data Collection screen
2. User selects activity label (e.g., "walking")
3. User taps "Start"
4. App connects to WebSocket server
5. Sensors start streaming at **20 Hz** (20 readings per second)
6. Each sensor reading is sent as JSON through WebSocket

**Sensor Reading Frequency:**
- 20 readings per second = 1 reading every 50ms
- For 1 minute: 20 × 60 = **1,200 data packets**
- For 3 minutes: 20 × 60 × 3 = **3,600 data packets**

### 2. WebSocket Connection

**What is WebSocket?**
- A **persistent, bidirectional** connection between client and server
- Unlike HTTP (request → response → close), WebSocket stays open
- Allows real-time streaming: client can send data continuously
- Server can also send data back anytime (for predictions)

**Connection Lifecycle:**

```
1. Initial Handshake (HTTP Upgrade)
   Mobile App → Server: "Upgrade to WebSocket"
   Server → Mobile App: "OK, upgraded"

2. Open Channel (stays open)
   ┌─────────────────────────────────┐
   │  Mobile App ←→ Server           │
   │  (bidirectional, persistent)    │
   └─────────────────────────────────┘

3. Data Streaming (continuous)
   Mobile App → Server: JSON packet 1
   Mobile App → Server: JSON packet 2
   Mobile App → Server: JSON packet 3
   ...
   (20 packets per second)

4. Close Connection
   User taps "Stop" → Close WebSocket
```

### 3. What Data is Received via WebSocket

**Example JSON Packet (from mobile app to server):**

```json
{
  "type": "sensor_data",
  "timestamp": "2025-12-26T10:30:45.123Z",
  "activity": "walking",
  "data": {
    "accelerometer": {
      "x": 0.123,
      "y": 9.81,
      "z": 0.045
    },
    "gyroscope": {
      "x": 0.001,
      "y": -0.002,
      "z": 0.0
    },
    "magnetometer": {
      "x": 23.4,
      "y": -12.1,
      "z": 45.6
    }
  }
}
```

**Field Explanations:**
- `type`: Message type (always "sensor_data" for sensor readings)
- `timestamp`: When the reading was taken (ISO 8601 format)
- `activity`: User-selected label ("walking", "running", "sitting", "standing")
- `data.accelerometer`: Acceleration in m/s² for x, y, z axes
- `data.gyroscope`: Rotation rate in rad/s for x, y, z axes
- `data.magnetometer`: Magnetic field in µT for x, y, z axes

### 4. Server-Side Processing

**When server receives a packet:**

```python
# In websocket_server.py, handle_client() function
async for message in websocket:  # ← Continuous stream
    data = json.loads(message)   # ← Parse JSON string to dict

    if SERVER_MODE == 'collect':
        # Extract activity label
        activity = data.get('activity', 'unlabeled')  # ← "walking"

        # Save to CSV
        data_collector.save_sensor_data(data, activity)

        # Send acknowledgment back
        response = {
            "type": "collection_ack",
            "samples_collected": sample_count,
            "activity": activity
        }
        await websocket.send(json.dumps(response))

    elif SERVER_MODE == 'predict':
        # Predict activity
        prediction = activity_predictor.predict(data)

        # Send prediction back
        await websocket.send(json.dumps(prediction))
```

### 5. Data Collector In Action

**How `DataCollector` saves data:**

```python
# In data_collector.py

def save_sensor_data(self, sensor_data: dict, activity_label: str):
    # 1. Get activity name
    activity = "walking"  # from sensor_data['activity']

    # 2. Open/create CSV file: collected_data/walking.csv
    if activity not in self.csv_files:
        # First time seeing this activity
        # Create: collected_data/walking.csv
        filename = self.data_dir / f"{activity}.csv"
        self.csv_files[activity] = open(filename, 'a')

        # Write CSV header
        # timestamp,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,mag_x,mag_y,mag_z,activity
        self.csv_writers[activity].writeheader()

    # 3. Extract sensor values
    accel = sensor_data['data']['accelerometer']  # {x: 0.123, y: 9.81, z: 0.045}
    gyro = sensor_data['data']['gyroscope']       # {x: 0.001, y: -0.002, z: 0.0}
    mag = sensor_data['data']['magnetometer']     # {x: 23.4, y: -12.1, z: 45.6}

    # 4. Write as CSV row
    row = {
        'timestamp': '2025-12-26T10:30:45.123Z',
        'accel_x': 0.123,
        'accel_y': 9.81,
        'accel_z': 0.045,
        'gyro_x': 0.001,
        'gyro_y': -0.002,
        'gyro_z': 0.0,
        'mag_x': 23.4,
        'mag_y': -12.1,
        'mag_z': 45.6,
        'activity': 'walking'
    }
    self.csv_writers[activity].writerow(row)

    # 5. Flush immediately (don't wait for buffer)
    self.csv_files[activity].flush()  # ← Saves to disk right away
```

### 6. Real-Time Example Timeline

**User collects walking data for 10 seconds:**

```
Time    Mobile App                          WebSocket                Server
─────────────────────────────────────────────────────────────────────────────
00:00   User selects "walking"              -                        -
00:00   User taps "Start"                   Opening connection...    Accepting...
00:01   Connected ✓                         Established ✓            Client connected ✓

00:01   Packet 1 (walking) ──────────────▶  Transmitting ─────────▶ Save to walking.csv
00:01   Packet 2 (walking) ──────────────▶  Transmitting ─────────▶ Save to walking.csv
00:01   Packet 3 (walking) ──────────────▶  Transmitting ─────────▶ Save to walking.csv
        ...
        (20 packets per second)
        ...
00:10   Packet 200 (walking) ─────────────▶  Transmitting ─────────▶ Save to walking.csv

00:10   User taps "Stop"                    Closing connection...    Client disconnected
00:10   Disconnected                        Closed                   Total: 200 samples
```

**Result:**
- File created: `server/collected_data/walking.csv`
- Contains: 200 rows (10 seconds × 20 Hz)
- Each row: 1 timestamp + 9 sensor values + 1 label = 11 columns

### 7. CSV File Output Example

**File: `collected_data/walking.csv`**

```csv
timestamp,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,mag_x,mag_y,mag_z,activity
2025-12-26T10:30:45.123Z,0.123,9.81,0.045,0.001,-0.002,0.0,23.4,-12.1,45.6,walking
2025-12-26T10:30:45.173Z,0.145,9.85,0.052,0.003,-0.001,0.001,23.5,-12.0,45.5,walking
2025-12-26T10:30:45.223Z,0.167,9.79,0.038,0.002,-0.003,0.0,23.3,-12.2,45.7,walking
2025-12-26T10:30:45.273Z,0.189,9.83,0.041,0.004,-0.002,0.002,23.4,-12.1,45.6,walking
...
(200 rows total for 10 seconds)
```

## Key Concepts

### Streaming vs Request-Response

**Traditional HTTP (Request-Response):**
```
Client: "Give me data"
Server: "Here's data" → Connection closes
Client: "Give me more data"
Server: "Here's more data" → Connection closes
```
❌ Inefficient for real-time data (too much overhead)

**WebSocket (Streaming):**
```
Client: "Open connection"
Server: "OK, connection open"
─────────────────────────────────
Client: Data packet 1 ───▶
Client: Data packet 2 ───▶
Server: ◀─── Response 1
Client: Data packet 3 ───▶
Server: ◀─── Response 2
...
(connection stays open)
─────────────────────────────────
Client: "Close connection"
```
✓ Efficient for continuous data streaming

### Why 20 Hz?

**Sampling Rate = 20 Hz means:**
- 20 samples per second
- 1 sample every 50 milliseconds
- Good balance between:
  - **Too slow** (1 Hz): Miss fast movements
  - **Too fast** (100 Hz): Huge data, battery drain
  - **Just right** (20 Hz): Captures human motion patterns efficiently

### Buffering vs Immediate Flush

**Without flush (buffered):**
```python
csv_writer.writerow(row)  # ← Stays in memory buffer
# If app crashes, data lost! ❌
```

**With immediate flush:**
```python
csv_writer.writerow(row)
csv_file.flush()  # ← Written to disk immediately ✓
# Data safe even if app crashes ✓
```

## Data Collection Workflow Summary

1. **Mobile App**: User performs activity (walking) for 3 minutes
2. **Sensors**: Collect data at 20 Hz = 3,600 readings
3. **WebSocket**: Streams 3,600 JSON packets to server
4. **Server**: Receives packets one-by-one in real-time
5. **DataCollector**: Writes each packet as CSV row immediately
6. **Result**: `walking.csv` with 3,600 rows ready for ML training

## Activity Recognition Workflow Summary

1. **Mobile App**: Sends sensor data (no activity label needed)
2. **WebSocket**: Streams JSON packets to server
3. **Server**: Receives packets in real-time
4. **ActivityPredictor**: Analyzes each packet, predicts activity
5. **WebSocket**: Sends prediction back to mobile app
6. **Mobile App**: Displays prediction on screen in real-time

## Performance Numbers

**Data Collection (3 minutes of walking):**
- Packets sent: 3,600
- Data transferred: ~3,600 × 500 bytes = ~1.8 MB
- CSV file size: ~500 KB
- Processing time: Real-time (no lag)

**Activity Recognition (real-time):**
- Latency: < 50ms per prediction
- Predictions per second: 20
- Network usage: ~10 KB/second
