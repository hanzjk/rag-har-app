# Server Modes Comparison

## Side-by-Side Comparison: Collect vs Predict

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         COLLECT MODE                                    │
└─────────────────────────────────────────────────────────────────────────┘

Purpose:     Create labeled datasets for ML training
Server runs: python websocket_server.py --mode collect
Mobile app:  Data Collection screen

Flow:
  Mobile App                 Server
     │                         │
     │  "walking" + data ─────▶│
     │                         │ Save to walking.csv
     │◀──── "saved!" ──────────│
     │                         │
     │  "walking" + data ─────▶│
     │                         │ Save to walking.csv
     │◀──── "saved!" ──────────│
     │                         │
    ...                       ...

Output:      CSV files (walking.csv, running.csv, etc.)
Use case:    Gathering training data



┌─────────────────────────────────────────────────────────────────────────┐
│                         PREDICT MODE                                    │
└─────────────────────────────────────────────────────────────────────────┘

Purpose:     Real-time activity recognition
Server runs: python websocket_server.py --mode predict
Mobile app:  Activity Recognition screen

Flow:
  Mobile App                 Server
     │                         │
     │  sensor data ──────────▶│
     │                         │ Analyze → "walking"
     │◀──── "walking 80%" ─────│
     │                         │
     │  sensor data ──────────▶│
     │                         │ Analyze → "walking"
     │◀──── "walking 82%" ─────│
     │                         │
    ...                       ...

Output:      Real-time predictions displayed on mobile app
Use case:    Live activity monitoring
```

## Detailed Comparison Table

| Aspect | Collection Mode | Prediction Mode |
|--------|----------------|-----------------|
| **Command** | `--mode collect` | `--mode predict` |
| **Mobile Screen** | Data Collection | Activity Recognition |
| **User selects** | Activity label | Nothing (auto-detect) |
| **Data sent** | Sensors + Label | Sensors only |
| **Server does** | Save to CSV | Predict activity |
| **Server returns** | Acknowledgment | Prediction |
| **Output** | CSV files on disk | JSON to mobile app |
| **Use case** | Create training dataset | Real-time monitoring |
| **Duration** | Minutes (collect enough data) | Continuous |
| **Active module** | `DataCollector` | `ActivityPredictor` |

## Message Format Comparison

### Collection Mode: Mobile → Server

```json
{
  "type": "sensor_data",
  "timestamp": "2025-12-26T10:30:45.123Z",
  "activity": "walking",                    ← User-selected label
  "data": {
    "accelerometer": {"x": 0.245, "y": 9.812, "z": 0.123},
    "gyroscope": {"x": 0.012, "y": -0.023, "z": 0.005},
    "magnetometer": {"x": 23.4, "y": -12.1, "z": 45.6}
  }
}
```

### Collection Mode: Server → Mobile

```json
{
  "type": "collection_ack",
  "samples_collected": 142,
  "activity": "walking",
  "timestamp": "2025-12-26T10:30:47.123Z"
}
```

### Prediction Mode: Mobile → Server

```json
{
  "type": "sensor_data",
  "timestamp": "2025-12-26T10:30:45.123Z",
  "data": {
    "accelerometer": {"x": 0.245, "y": 9.812, "z": 0.123},
    "gyroscope": {"x": 0.012, "y": -0.023, "z": 0.005},
    "magnetometer": {"x": 23.4, "y": -12.1, "z": 45.6}
  }
}
```

**Notice:** No `"activity"` field in prediction mode!

### Prediction Mode: Server → Mobile

```json
{
  "type": "activity_prediction",
  "activity": "walking",                    ← Server's prediction
  "confidence": 0.80,                       ← How confident (0-1)
  "timestamp": "2025-12-26T10:30:45.124Z"
}
```

## Code Path Comparison

### Collection Mode Code Path

```python
# websocket_server.py:56
if SERVER_MODE == "collect":
    activity = data.get("activity", "unlabeled")  # ← Get user's label
    success = data_collector.save_sensor_data(data, activity)
    #              ↓
    #     data_collector.py:47
    #     def save_sensor_data(self, sensor_data, activity_label):
    #         # Extract values
    #         # Write to CSV: collected_data/walking.csv
    #         # Flush to disk

    # Send acknowledgment
    response = {
        "type": "collection_ack",
        "samples_collected": sample_count,
        "activity": activity
    }
    await websocket.send(json.dumps(response))
```

### Prediction Mode Code Path

```python
# websocket_server.py:77
elif SERVER_MODE == "predict":
    prediction = activity_predictor.predict(data)
    #              ↓
    #     activity_predictor.py:25
    #     def predict(self, sensor_data):
    #         return self._predict_rule_based(sensor_data)
    #              ↓
    #     activity_predictor.py:29
    #     def _predict_rule_based(self, sensor_data):
    #         # Calculate magnitudes
    #         # Apply decision rules
    #         # Return {"activity": "walking", "confidence": 0.80}

    # Send prediction
    await websocket.send(json.dumps(prediction))
```

## Server Console Output Comparison

### Collection Mode Console

```bash
$ python websocket_server.py --mode collect
============================================================
Starting WebSocket server on ws://0.0.0.0:8080
Server mode: collect
Data will be saved to: collected_data
Ready to collect labeled sensor data from mobile app
============================================================
Waiting for connections...

10:30:45 - INFO - Client connected: 192.168.1.100:54321 (Total: 1)
10:30:45 - INFO - Server mode: collect
10:30:45 - INFO - Data collector initialized. Data directory: collected_data
10:30:45 - INFO - Created new CSV file: collected_data/walking.csv
10:30:46 - INFO - Collected 20 samples for activity: walking
10:30:47 - INFO - Collected 40 samples for activity: walking
10:30:48 - INFO - Collected 60 samples for activity: walking
...
10:33:45 - INFO - Client disconnected: 192.168.1.100:54321
10:33:45 - INFO - Total samples collected from 192.168.1.100:54321: 3600
```

### Prediction Mode Console

```bash
$ python websocket_server.py --mode predict
============================================================
Starting WebSocket server on ws://0.0.0.0:8080
Server mode: predict
Ready to send activity predictions to mobile app
============================================================
Waiting for connections...

10:30:45 - INFO - Client connected: 192.168.1.100:54321 (Total: 1)
10:30:45 - INFO - Server mode: predict
10:30:45 - INFO - Activity predictor initialized with rule-based classification
10:30:45 - INFO - Sent prediction to 192.168.1.100:54321: walking (80%)
10:30:45 - INFO - Sent prediction to 192.168.1.100:54321: walking (80%)
10:30:45 - INFO - Sent prediction to 192.168.1.100:54321: walking (82%)
10:30:46 - INFO - Sent prediction to 192.168.1.100:54321: running (85%)
10:30:46 - INFO - Sent prediction to 192.168.1.100:54321: running (85%)
...
10:33:45 - INFO - Client disconnected: 192.168.1.100:54321
```

## Server File System Comparison

### After Collection Mode (3 minutes per activity)

```
server/
├── collected_data/            ← Created by DataCollector
│   ├── walking.csv           ← 3,600 rows
│   ├── running.csv           ← 3,600 rows
│   ├── sitting.csv           ← 3,600 rows
│   └── standing.csv          ← 3,600 rows
├── data_collector.py
├── activity_predictor.py
└── websocket_server.py
```

### After Prediction Mode

```
server/
├── data_collector.py
├── activity_predictor.py
└── websocket_server.py

(No files created - predictions sent to mobile app only)
```

## Mobile App UI Comparison

### Data Collection Screen

```
┌────────────────────────────┐
│   Data Collection          │
├────────────────────────────┤
│                            │
│  Activity Label:           │
│  ┌────────────────────┐    │
│  │ Walking        ▼   │    │
│  └────────────────────┘    │
│                            │
│  Demo Activity:            │
│  ┌────────────────────┐    │
│  │ Walking        ▼   │    │
│  └────────────────────┘    │
│                            │
│  ┌─────────┬──────────┐    │
│  │  2:35   │   3140   │    │
│  │ Duration│  Packets │    │
│  └─────────┴──────────┘    │
│                            │
│  Accelerometer: 9.8 m/s²   │
│  Gyroscope: 0.25 rad/s     │
│  Magnetometer: 45.2 µT     │
│                            │
│          [STOP]            │  ← Red button (collecting)
│                            │
└────────────────────────────┘
```

### Activity Recognition Screen

```
┌────────────────────────────┐
│  Activity Recognition      │
├────────────────────────────┤
│                            │
│                            │
│         🚶                  │
│                            │
│       Walking              │  ← Predicted activity
│         82%                │  ← Confidence
│                            │
│  Last 5 predictions:       │
│  • Walking (80%)           │
│  • Walking (82%)           │
│  • Walking (81%)           │
│  • Walking (83%)           │
│  • Walking (82%)           │
│                            │
│          [STOP]            │  ← Red button (recognizing)
│                            │
└────────────────────────────┘
```

## Typical Workflow

### Phase 1: Data Collection (Once)

```
1. Start server in collect mode
   $ python websocket_server.py --mode collect

2. Open mobile app → Data Collection

3. For each activity:
   a. Select activity label (e.g., "walking")
   b. Optionally select demo pattern
   c. Tap "Start"
   d. Perform activity for 2-3 minutes
   e. Tap "Stop"

4. Repeat for all activities (walking, running, sitting, standing)

5. Stop server (Ctrl+C)

6. Result: 4 CSV files ready for ML training
```

### Phase 2: Model Training (Once)

```
1. Load CSV files
2. Extract features
3. Train ML model
4. Save model (activity_model.pkl)
5. Update activity_predictor.py to load model
```

### Phase 3: Real-Time Recognition (Ongoing)

```
1. Start server in predict mode
   $ python websocket_server.py --mode predict --model activity_model.pkl

2. Open mobile app → Activity Recognition

3. Tap "Start"

4. Move around, perform activities

5. Watch real-time predictions on screen!

6. Tap "Stop" when done
```

## Performance Comparison

| Metric | Collection Mode | Prediction Mode |
|--------|----------------|-----------------|
| **Latency** | ~10ms (ack) | ~15ms (prediction) |
| **CPU (server)** | 5% (CSV write) | 8% (prediction) |
| **Memory (server)** | 10 MB | 15 MB |
| **Disk I/O** | High (writing CSV) | None |
| **Network up** | 5.6 KB/s | 5.6 KB/s |
| **Network down** | 100 bytes/s | 500 bytes/s |
| **Predictions/sec** | 0 | 20 |
| **CSV rows/sec** | 20 | 0 |

## When to Use Each Mode

### Use Collection Mode When:
- 📊 Creating a new dataset
- 🔄 Adding more training data
- 🆕 Adding new activity types
- 🎯 Improving model accuracy
- 📈 Collecting data from different people

### Use Prediction Mode When:
- 🔴 Testing the system live
- 📱 Demonstrating the app
- 🧪 Validating model accuracy
- 🏃 Actual activity monitoring
- 🎮 Building an application feature

## Quick Reference

**Switch between modes:**
```bash
# Collection mode
python websocket_server.py --mode collect --data-dir my_data

# Prediction mode (rule-based)
python websocket_server.py --mode predict

# Prediction mode (ML model)
python websocket_server.py --mode predict --model my_model.pkl
```

**Both modes:**
- Use same WebSocket connection
- Run on same port (8080)
- Stream at same rate (20 Hz)
- Compatible with same mobile app (different screens)
- Can be switched by restarting server

**Key difference:**
- **Collection = Save data**
- **Prediction = Analyze data**
