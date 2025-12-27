# Activity Prediction Flow

## Overview: How Activity Recognition Works

```
Mobile App              WebSocket                Server
┌──────────┐           ┌─────────┐          ┌────────────────┐
│ Sensors  │─streaming─▶│  Live   │─receive─▶│ Predict        │
│ (20 Hz)  │   JSON     │ Channel │   JSON   │ Activity       │
└──────────┘            └─────────┘          └────┬───────────┘
                              ▲                    │
                              │                    │
                              └──── send back ─────┘
                                   prediction
```

## Key Difference: Collection vs Prediction

### Data Collection Mode

```
Mobile App: "Here's sensor data + label 'walking'"
Server:     "Thanks, saved to walking.csv"
           (no prediction, just storage)
```

### Prediction Mode (Activity Recognition)

```
Mobile App: "Here's sensor data (no label)"
Server:     *analyzes data*
           "I think you're walking (80% confident)"
Mobile App: *displays "Walking 80%" on screen*
```

## Step-by-Step Prediction Flow

### 1. User Opens Activity Recognition Screen

**Mobile App:**

- User navigates to "Activity Recognition" tab
- User taps "Start"
- App connects to WebSocket server
- Sensors start streaming at 20 Hz

**No activity label is sent** (we want the server to predict it!)

### 2. Mobile App Sends Sensor Data

**Packet sent (no 'activity' field):**

```json
{
  "type": "sensor_data",
  "timestamp": "2025-12-26T10:30:45.123Z",
  "data": {
    "accelerometer": { "x": 0.245, "y": 9.812, "z": 0.123 },
    "gyroscope": { "x": 0.012, "y": -0.023, "z": 0.005 },
    "magnetometer": { "x": 23.4, "y": -12.1, "z": 45.6 }
  }
}
```

**Notice:** No `"activity"` field (unlike collection mode)

### 3. Server Receives Data

**File: `server/websocket_server.py:48`**

```python
async for message in websocket:  # ← Continuous stream
    data = json.loads(message)   # ← Parse JSON

    if data.get("type") == "sensor_data":

        if SERVER_MODE == "predict":
            # Activity recognition mode

            # Predict activity using ActivityPredictor
            prediction = activity_predictor.predict(data)
            #    ↑
            # This is where the magic happens!

            # Send prediction back to client
            await websocket.send(json.dumps(prediction))

            logger.info(f"Sent prediction: {prediction['activity']} ({prediction['confidence']:.0%})")
```

### 4. ActivityPredictor Analyzes the Data

**File: `server/activity_predictor.py:25`**

```python
def predict(self, sensor_data: dict) -> Dict[str, Any]:
    """
    Main prediction method.
    Currently uses rule-based classification.
    """
    return self._predict_rule_based(sensor_data)
    #      ↑
    # Calls the rule-based algorithm
```

### 5. Classification

**UI displays:**

```
┌─────────────────────────┐
│   Activity Recognition  │
├─────────────────────────┤
│                         │
│         🚶               │
│                         │
│       Walking           │
│         80%             │
│                         │
└─────────────────────────┘
```

## Prediction Frequency and Latency

### Processing Pipeline Timing

```
Mobile App    Network    Server Processing      Network    Mobile App
  (0ms)      (5-10ms)      (1-2ms)             (5-10ms)     (1ms)
    │            │             │                   │           │
    ▼            ▼             ▼                   ▼           ▼
  Send  ──────▶ WiFi ───────▶ Predict ──────────▶ WiFi ─────▶ Display
 packet                      activity                        on screen

Total latency: ~12-23ms (very fast!)
```

### Prediction Rate

- **Sensor data sent:** 20 Hz (20 times/second)
- **Predictions made:** 20 Hz (one per packet)
- **Predictions displayed:** 20 Hz (smooth, real-time)

**Result:** Almost instant feedback! User sees activity update in real-time as they move.
