# Example Data Collection Session

This document shows a **real example** of what happens during a data collection session.

## Scenario: Collecting Walking Data for 5 Seconds

### Step 1: Start Server

```bash
$ cd server
$ python websocket_server.py --mode collect --data-dir my_dataset

============================================================
Starting WebSocket server on ws://0.0.0.0:8000
Server mode: collect
Data will be saved to: my_dataset
Ready to collect labeled sensor data from mobile app
============================================================
Waiting for connections...
```

### Step 2: Mobile App Connects

**Mobile App:**
1. User selects activity label: "walking"
2. User taps "Start"
3. App creates WebSocket connection to `ws://192.168.1.100:8000/ws`

**Server Console:**
```
10:30:45 - INFO - Client connected: 192.168.1.100:54321 (Total: 1)
10:30:45 - INFO - Server mode: collect
10:30:45 - INFO - Data collector initialized. Data directory: my_dataset
10:30:45 - INFO - Created new CSV file: my_dataset/walking.csv
```

**What happened in code:**

```python
# In websocket_server.py
async def handle_client(websocket, path):
    client_id = "192.168.1.100:54321"
    connected_clients.add(websocket)
    logger.info(f"Client connected: {client_id}")
    # ↑ This prints to console

    # Now waiting for messages in a loop...
    async for message in websocket:
        # Each sensor packet arrives here
```

```python
# In data_collector.py
class DataCollector:
    def __init__(self, data_dir: str):
        self.data_dir = Path('my_dataset')
        self.data_dir.mkdir(exist_ok=True)  # Create folder
        # ↑ Creates: server/my_dataset/
```

### Step 3: Streaming Sensor Data (5 seconds × 20 Hz = 100 packets)

**Mobile App sends (Packet #1 at 10:30:45.000):**

```json
{
  "type": "sensor_data",
  "timestamp": "2025-12-26T10:30:45.000Z",
  "activity": "walking",
  "data": {
    "accelerometer": {"x": 0.245, "y": 9.812, "z": 0.123},
    "gyroscope": {"x": 0.012, "y": -0.023, "z": 0.005},
    "magnetometer": {"x": 23.4, "y": -12.1, "z": 45.6}
  }
}
```

**Server receives and processes:**

```python
# In websocket_server.py (line 51)
data = json.loads(message)
# ↑ Converts JSON string to Python dict

# Now data is:
# {
#   'type': 'sensor_data',
#   'timestamp': '2025-12-26T10:30:45.000Z',
#   'activity': 'walking',
#   'data': {...}
# }

if data.get('type') == 'sensor_data':  # ← True!
    activity = data.get('activity', 'unlabeled')  # ← 'walking'
    success = data_collector.save_sensor_data(data, activity)
    # ↑ Calls DataCollector to save to CSV
```

```python
# In data_collector.py
def save_sensor_data(self, sensor_data: dict, activity_label: str):
    activity = 'walking'  # from parameter

    # First time? Create file and CSV writer
    if 'walking' not in self.csv_files:
        filename = Path('my_dataset/walking.csv')
        self.csv_files['walking'] = open(filename, 'a')

        # Create CSV writer with column names
        self.csv_writers['walking'] = csv.DictWriter(
            file,
            fieldnames=['timestamp', 'accel_x', 'accel_y', 'accel_z',
                       'gyro_x', 'gyro_y', 'gyro_z',
                       'mag_x', 'mag_y', 'mag_z', 'activity']
        )

        # Write header row
        self.csv_writers['walking'].writeheader()
        # ↑ Writes: timestamp,accel_x,accel_y,accel_z,...

    # Extract sensor values from nested dict
    accel = sensor_data['data']['accelerometer']
    # ↑ accel = {'x': 0.245, 'y': 9.812, 'z': 0.123}

    gyro = sensor_data['data']['gyroscope']
    # ↑ gyro = {'x': 0.012, 'y': -0.023, 'z': 0.005}

    mag = sensor_data['data']['magnetometer']
    # ↑ mag = {'x': 23.4, 'y': -12.1, 'z': 45.6}

    # Create row dict
    row = {
        'timestamp': '2025-12-26T10:30:45.000Z',
        'accel_x': 0.245,
        'accel_y': 9.812,
        'accel_z': 0.123,
        'gyro_x': 0.012,
        'gyro_y': -0.023,
        'gyro_z': 0.005,
        'mag_x': 23.4,
        'mag_y': -12.1,
        'mag_z': 45.6,
        'activity': 'walking'
    }

    # Write to CSV
    self.csv_writers['walking'].writerow(row)
    # ↑ Appends row to walking.csv

    # Save immediately (don't wait for buffer)
    self.csv_files['walking'].flush()
    # ↑ Forces write to disk
```

**Server sends acknowledgment back to app:**

```python
# In websocket_server.py (line 67)
response = {
    "type": "collection_ack",
    "samples_collected": 1,  # First sample
    "activity": "walking",
    "timestamp": "2025-12-26T10:30:45.001Z"
}
await websocket.send(json.dumps(response))
# ↑ Sends JSON back through WebSocket
```

**Mobile App receives:**
- Shows "Samples collected: 1" on screen

### Step 4: More Packets Arrive (20 per second)

**Server Console (logs every 20 samples):**
```
10:30:46 - INFO - Collected 20 samples for activity: walking
10:30:47 - INFO - Collected 40 samples for activity: walking
10:30:48 - INFO - Collected 60 samples for activity: walking
10:30:49 - INFO - Collected 80 samples for activity: walking
10:30:50 - INFO - Collected 100 samples for activity: walking
```

**What's happening:**
- Mobile app sends packet every 50ms (20 Hz)
- Server receives each packet in `async for message in websocket`
- Each packet triggers `save_sensor_data()`
- Each packet gets written to CSV immediately

**walking.csv grows in real-time:**

```csv
timestamp,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,mag_x,mag_y,mag_z,activity
2025-12-26T10:30:45.000Z,0.245,9.812,0.123,0.012,-0.023,0.005,23.4,-12.1,45.6,walking
2025-12-26T10:30:45.050Z,0.267,9.798,0.145,0.015,-0.019,0.008,23.5,-12.0,45.5,walking
2025-12-26T10:30:45.100Z,0.289,9.823,0.167,0.018,-0.015,0.011,23.3,-12.2,45.7,walking
2025-12-26T10:30:45.150Z,0.312,9.805,0.189,0.021,-0.011,0.014,23.4,-12.1,45.6,walking
... (96 more rows)
```

### Step 5: User Stops Collection

**Mobile App:**
1. User taps "Stop"
2. App calls `_websocketService.disconnect()`
3. WebSocket connection closes

**Server Console:**
```
10:30:50 - INFO - Client disconnected: 192.168.1.100:54321
10:30:50 - INFO - Total samples collected from 192.168.1.100:54321: 100
10:30:50 - INFO - Client removed: 192.168.1.100:54321 (Total: 0)
```

**What happened in code:**

```python
# In websocket_server.py
try:
    async for message in websocket:
        # Process messages...
except websockets.exceptions.ConnectionClosed:
    # ↑ Triggered when client disconnects
    logger.info(f"Client disconnected: {client_id}")
    logger.info(f"Total samples collected: {sample_count}")
    # ↑ sample_count was incremented for each packet
finally:
    connected_clients.remove(websocket)
    # ↑ Clean up
```

### Step 6: Server Shutdown

**User presses Ctrl+C:**

```bash
^C
10:30:55 - INFO - Server stopped by user
10:30:55 - INFO - Closed CSV file for activity: walking
10:30:55 - INFO - All CSV files closed
```

**What happened in code:**

```python
# In websocket_server.py (line 163)
except KeyboardInterrupt:
    logger.info("\nServer stopped by user")
    if SERVER_MODE == 'collect':
        data_collector.close_all()
        # ↑ Closes all open CSV files
```

```python
# In data_collector.py
def close_all(self):
    for activity, file in self.csv_files.items():
        file.close()  # ← Close walking.csv
        logger.info(f"Closed CSV file for activity: {activity}")
```

### Final Result

**File created: `server/my_dataset/walking.csv`**

```
Size: ~15 KB
Rows: 100 (header + 100 data rows)
Columns: 11
Ready for ML training! ✓
```

**CSV structure:**
```
Row 0:   timestamp,accel_x,accel_y,...          ← Header
Row 1:   2025-12-26T10:30:45.000Z,0.245,...     ← Data
Row 2:   2025-12-26T10:30:45.050Z,0.267,...     ← Data
...
Row 100: 2025-12-26T10:30:49.950Z,0.398,...     ← Data
```

## Visual Summary: The Loop

```
╔═══════════════════════════════════════════════════════════╗
║  Mobile App (running at 20 Hz)                            ║
╚═══════════════════════════════════════════════════════════╝
           │
           │ Every 50ms, send JSON packet
           │
           ▼
╔═══════════════════════════════════════════════════════════╗
║  WebSocket Connection (persistent, bidirectional)         ║
║                                                            ║
║  async for message in websocket:                          ║
║    ↓                                                       ║
║    Receive JSON string                                    ║
║    ↓                                                       ║
║    Parse to Python dict                                   ║
║    ↓                                                       ║
║    Extract: type, timestamp, activity, sensor data        ║
╚═══════════════════════════════════════════════════════════╝
           │
           │ Pass to DataCollector
           │
           ▼
╔═══════════════════════════════════════════════════════════╗
║  DataCollector.save_sensor_data()                         ║
║                                                            ║
║  1. Get activity label: "walking"                         ║
║  2. Open/create CSV file: walking.csv                     ║
║  3. Extract sensor values from nested dict                ║
║  4. Create row dict with 11 fields                        ║
║  5. Write row to CSV                                      ║
║  6. Flush to disk immediately                             ║
╚═══════════════════════════════════════════════════════════╝
           │
           │ Row saved! ✓
           │
           ▼
     walking.csv
     (grows by 1 row)
           │
           │ Send acknowledgment back
           │
           ▼
╔═══════════════════════════════════════════════════════════╗
║  WebSocket Connection                                     ║
║  await websocket.send(json.dumps(response))               ║
╚═══════════════════════════════════════════════════════════╝
           │
           │ JSON response
           │
           ▼
╔═══════════════════════════════════════════════════════════╗
║  Mobile App                                               ║
║  Update UI: "Samples collected: N"                        ║
╚═══════════════════════════════════════════════════════════╝

     (Loop repeats 20 times per second)
```

## Key Takeaways

1. **WebSocket = Persistent Connection**: Opens once, streams data continuously
2. **Async Processing**: Server handles each packet asynchronously without blocking
3. **Real-time CSV Writing**: Each packet is written immediately (no batching)
4. **20 Hz Sampling**: 20 packets per second = rich data for ML
5. **Activity Labeling**: User selects label, app includes it in every packet
6. **Bidirectional**: Server can send acknowledgments back to app

## Memory and Performance

**Memory Usage:**
- Server keeps 1 file handle per activity (low memory)
- CSV buffer is flushed immediately (no large buffers)
- WebSocket handles streaming efficiently

**CPU Usage:**
- Minimal: Just JSON parsing + CSV writing
- Async I/O: Non-blocking, can handle multiple clients

**Disk I/O:**
- Sequential writes (fast)
- Immediate flush (data safe)
- ~10-20 KB per minute per activity
