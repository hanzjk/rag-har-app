# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a monorepo containing a complete human activity recognition system:

1. **Flutter Mobile App** (root directory): Android application for sensor data collection and activity recognition
2. **Python WebSocket Server** (`server/`): Backend server for receiving sensor data and sending activity predictions

### Mobile App

Android application for human activity recognition with two screens:

- **Data Collection Screen**: Extracts data from motion sensors and sends it to the server for dataset creation
- **Activity Recognition Screen**: Sends sensor data in real time and displays predicted activity on screen

### Server

Python WebSocket server that dynamically handles different message types:
- Receives sensor data from the mobile app
- Processes `collect_data` messages to save labeled data for ML training
- Processes `predict_activity` messages to perform real-time activity classification
- Supports both operations simultaneously for different clients

## Repository Structure

```
har-demo/
├── mobile/              # Flutter mobile application
│   ├── lib/            # Dart source code
│   │   ├── config/    # Constants and configuration
│   │   ├── models/    # Data models
│   │   ├── services/  # Business logic (sensors, WebSocket, permissions)
│   │   ├── providers/ # State management (Provider pattern)
│   │   ├── screens/   # UI screens
│   │   └── widgets/   # Reusable UI components
│   ├── android/       # Android platform code
│   ├── ios/           # iOS platform code
│   ├── test/          # Tests
│   └── pubspec.yaml   # Flutter dependencies
├── server/             # Python WebSocket server
│   ├── websocket_server.py
│   ├── requirements.txt
│   └── README.md
├── CLAUDE.md          # This file
└── README.md          # Project documentation
```

## Development Commands

### Server Commands

```bash
# Navigate to server directory
cd server

# Install Python dependencies
pip install -r requirements.txt

# Run the WebSocket server
python websocket_server.py

# Optional: specify custom data directory
python websocket_server.py --data-dir my_data
```

Server runs on `ws://0.0.0.0:8080` and handles both data collection and activity prediction dynamically based on message type. For detailed server documentation, see `server/README.md`.

### Mobile App Commands

All Flutter commands must be run from the `mobile/` directory:

```bash
# Navigate to mobile directory
cd mobile

# Get dependencies
flutter pub get

# Run the app
flutter run

# Run tests
flutter test

# Analyze code
flutter analyze

# Format code
dart format .

# Build for Android
flutter build apk
flutter build appbundle

# Build for iOS
flutter build ios
```

## Architecture

### State Management
The app uses Provider pattern for state management with three main providers:
- `AppStateProvider` - manages WebSocket URL, connection state, and demo mode
- `SensorDataProvider` - handles sensor data collection and streaming with different message types
- `ActivityProvider` - manages activity predictions and history

### Services Layer
- `SensorService` - aggregates accelerometer, gyroscope, and magnetometer data at 50Hz sampling rate
- `WebSocketService` - handles bidirectional WebSocket communication
- `PermissionService` - manages runtime sensor permissions

## WebSocket Message Format

### Client → Server

**Data Collection Message:**
```json
{
  "type": "collect_data",
  "timestamp": "2025-12-26T10:30:45.123Z",
  "activity": "walking",
  "data": {
    "accelerometer": {"x": 0.123, "y": 9.81, "z": 0.045},
    "gyroscope": {"x": 0.001, "y": -0.002, "z": 0.0},
    "magnetometer": {"x": 23.4, "y": -12.1, "z": 45.6}
  }
}
```

**Activity Recognition Message:**
```json
{
  "type": "predict_activity",
  "timestamp": "2025-12-26T10:30:45.123Z",
  "data": {
    "accelerometer": {"x": 0.123, "y": 9.81, "z": 0.045},
    "gyroscope": {"x": 0.001, "y": -0.002, "z": 0.0},
    "magnetometer": {"x": 23.4, "y": -12.1, "z": 45.6}
  }
}
```

### Server → Client

**Collection Acknowledgment:**
```json
{
  "type": "collection_ack",
  "samples_collected": 150,
  "activity": "walking",
  "timestamp": "2025-12-26T10:30:45.123Z"
}
```

**Activity Prediction:**
```json
{
  "type": "activity_prediction",
  "activity": "walking",
  "confidence": 0.92,
  "timestamp": "2025-12-26T10:30:45.123Z"
}
```

## Configuration

Default WebSocket URL: `ws://192.168.1.100:8080/ws`

The URL can be changed in the Settings screen and is persisted using SharedPreferences.

## Demo Mode

The app includes a Demo Mode for testing without physical sensors, ideal for simulators/emulators.

**Enabling Demo Mode:**
1. Open Settings screen
2. Toggle "Enable Demo Mode"
3. The app will restart to use simulated sensors

**Features:**
- Generates realistic sensor data patterns at 50 Hz for all three sensors (accelerometer, gyroscope, magnetometer)
- Activity selector in Data Collection screen to simulate different activities:
  - Walking: 2 Hz gait cycle with moderate amplitude
  - Running: 3 Hz gait cycle with higher amplitude
  - Sitting: Minimal movement, mostly gravity
  - Standing: Very minimal movement with micro-variations
- Realistic noise and patterns based on actual human motion physics
- Works on any emulator/simulator without needing physical sensors

**Use Cases:**
- Testing UI/UX flow
- Testing WebSocket server integration
- Demonstrating the app
- Development without physical Android device

## Supported Activities

- Walking
- Running
- Sitting
- Standing

## Full System Testing

### Quick Test (Demo Mode)

1. **Start the server:**
   ```bash
   cd server
   python websocket_server.py
   ```

2. **Run the mobile app:**
   ```bash
   cd mobile
   flutter run
   ```

3. **Find your local IP:**
   ```bash
   # macOS/Linux
   ifconfig | grep "inet " | grep -v 127.0.0.1

   # Windows
   ipconfig
   ```

4. **Configure the app:**
   - Settings → Set WebSocket URL to `ws://YOUR_IP:8080/ws`
   - Settings → Enable Demo Mode
   - Restart the app

5. **Test:**
   - Go to Activity Recognition mode
   - Select activity pattern (e.g., Walking)
   - Tap Start
   - Watch real-time predictions from the server

### Real Sensor Testing

1. Deploy app to physical Android device (USB or wireless debugging)
2. Ensure device is on same network as server
3. Configure WebSocket URL with server's local IP
4. Disable Demo Mode in settings
5. Perform actual activities and observe predictions

## Server Implementation Notes

The server uses a **message type-based architecture**:
- No startup mode configuration required
- Dynamically handles both `collect_data` and `predict_activity` message types
- Per-client instances of both DataCollector and ActivityPredictor
- Same client can switch between collection and prediction without disconnecting

The current prediction algorithm uses **rule-based classification** with **stepped windowing**:
- **Sampling rate:** 50 Hz (50 samples per second)
- **Window size:** 200 samples (4 seconds of data)
- **Step size:** 50 samples (predictions every 1 second)
- **Overlap:** 75% (150 samples overlap between consecutive windows)
- **Buffering:** 2 seconds (100 samples) before first prediction
- Calculates accelerometer and gyroscope magnitudes with statistical features
- Simple threshold-based activity detection
- ~75-90% confidence scores

**Prediction Timeline:**
- 0-2 seconds: Buffering (collecting minimum data)
- 2 seconds: First prediction (window has 100 samples)
- 3 seconds: Second prediction (window has 150 samples)
- 4 seconds: Third prediction (window full with 200 samples)
- 4+ seconds: Predictions every 1 second with full 4-second window

### Replacing with ML Model

To integrate a machine learning model:

1. Collect training data using Data Collection mode
2. Train model (TensorFlow, PyTorch, scikit-learn)
3. Update `predict_activity()` function in `websocket_server.py`
4. Load model at server startup

Example structure:
```python
import pickle
model = pickle.load(open('model.pkl', 'rb'))

def predict_activity(sensor_data):
    features = extract_features(sensor_data)
    prediction = model.predict([features])[0]
    confidence = model.predict_proba([features]).max()
    return {"activity": prediction, "confidence": confidence}
```
