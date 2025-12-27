# Human Activity Recognition System

A complete system for collecting sensor data and recognizing human activities, consisting of a Flutter mobile app and a Python WebSocket server.

## 🏗️ Project Structure

```
har-demo/
├── mobile/                          # Flutter mobile application
│   ├── lib/                        # Dart source code
│   │   ├── config/                # Constants and configuration
│   │   ├── models/                # Data models (SensorData, ActivityType)
│   │   ├── providers/             # State management (Provider pattern)
│   │   │   ├── app_state_provider.dart
│   │   │   ├── sensor_data_provider.dart
│   │   │   └── activity_provider.dart
│   │   ├── screens/               # UI screens
│   │   │   ├── home_screen.dart
│   │   │   ├── data_collection_screen.dart
│   │   │   ├── activity_recognition_screen.dart
│   │   │   └── settings_screen.dart
│   │   ├── services/              # Business logic
│   │   │   ├── sensor_service.dart
│   │   │   ├── demo_sensor_service.dart
│   │   │   ├── websocket_service.dart
│   │   │   └── permission_service.dart
│   │   ├── widgets/               # Reusable UI components
│   │   └── main.dart              # App entry point
│   ├── android/                   # Android platform code
│   │   └── app/src/main/
│   │       ├── AndroidManifest.xml
│   │       └── res/xml/
│   │           └── network_security_config.xml  # WebSocket cleartext config
│   ├── ios/                       # iOS platform code
│   ├── test/                      # Tests
│   └── pubspec.yaml               # Flutter dependencies
│
├── server/                         # Python WebSocket server
│   ├── websocket_server.py        # Main server (handles connections, routing)
│   ├── data_collector.py          # Data collection and CSV storage
│   ├── activity_predictor.py      # Activity prediction (sliding window + rules)
│   ├── requirements.txt           # Python dependencies
│   ├── collected_data/            # CSV files organized by activity
│   │   ├── walking.csv
│   │   ├── running.csv
│   │   ├── sitting.csv
│   │   └── standing.csv
│   ├── venv/                      # Python virtual environment (gitignored)
│   └── README.md                  # Server documentation
│
│
├── CLAUDE.md                      # Development guide for Claude Code
└── README.md                      # This file
```

## 📱 Mobile App (Flutter)

Android application for human activity recognition with two modes:

### Features
- **Data Collection Mode**: Stream sensor data to server for ML training datasets
  - Collect labeled data at 50Hz sampling rate
  - Export to CSV files organized by activity
  - Real-time packet counter and duration tracking
- **Activity Recognition Mode**: Real-time activity prediction display
  - Buffering indicator during initialization (~2 seconds)
  - Live activity display with confidence percentage
  - Activity history with timestamps
  - Smooth transitions between activities
- **Demo Mode**: Test without physical sensors (perfect for emulators)
  - Realistic sensor data simulation
  - Activity pattern selector (Walking/Running/Sitting/Standing)
  - Works on any emulator without hardware sensors
- **Sensors**: Accelerometer, Gyroscope, Magnetometer (50Hz sampling)
- **State Management**: Provider pattern for reactive UI updates
- **WebSocket**: Persistent connection with reconnection handling

### Supported Activities
- Walking
- Running
- Sitting
- Standing

### Quick Start

1. **Navigate to mobile directory:**
```bash
cd mobile
```

2. **Install dependencies:**
```bash
flutter pub get
```

3. **Run the app:**
```bash
flutter run
```

4. **Enable Demo Mode (optional):**
   - Settings → Enable Demo Mode
   - Restart app
   - Test on any emulator/simulator

For detailed Flutter development commands, see [CLAUDE.md](CLAUDE.md).

## 🖥️ WebSocket Server (Python)

Python server that receives sensor data and sends back activity predictions.

### Quick Start

1. **Navigate to server directory:**
```bash
cd server
```

2. **Install dependencies:**
```bash
pip install -r requirements.txt
```

3. **Run the server:**
```bash
python websocket_server.py
```

Server starts on `ws://0.0.0.0:8080`

For detailed server documentation, see [server/README.md](server/README.md).


## 🚀 Full System Setup

### 1. Start the Server

```bash
# Terminal 1
cd server
pip install -r requirements.txt
python websocket_server.py
```

### 2. Configure the App

**For Android Emulator:**
- Settings → Set WebSocket URL to `ws://10.0.2.2:8080/ws`
- The emulator uses `10.0.2.2` as an alias for the host machine's `localhost`

**For Physical Android Device:**
Find your local IP address:
- **macOS/Linux:** `ifconfig | grep "inet "` or `hostname -I`
- **Windows:** `ipconfig`

In the Flutter app:
- Settings → Set WebSocket URL to `ws://YOUR_LOCAL_IP:8080/ws`
- Example: `ws://192.168.1.100:8080/ws`
- Ensure device is on the same WiFi network as the server

### 3. Run the App

```bash
# Terminal 2
cd mobile
flutter pub get
flutter run
```

### 4. Test the System

**Option A: Demo Mode (Recommended for testing)**
1. Settings → Enable Demo Mode
2. Go to Data Collection or Activity Recognition
3. Select activity pattern (Walking/Running/Sitting/Standing)
4. Tap Start
5. Watch predictions in real-time

**Option B: Real Sensors**
1. Deploy to physical Android device
2. Go to Activity Recognition mode
3. Tap Start
4. Perform activities and see predictions

## 📊 Data Flow

```
Mobile App (Sensors at 50Hz)
    ↓ [WebSocket]
Python Server (Sliding Window + Prediction)
    ↓ [WebSocket]
Mobile App (Display Activity & History)
```

### Message Format

**Client → Server (Data Collection):**
```json
{
  "type": "collect_data",
  "timestamp": "2025-12-27T10:30:45.123Z",
  "activity": "walking",
  "data": {
    "accelerometer": {"x": 0.123, "y": 9.81, "z": 0.045},
    "gyroscope": {"x": 0.001, "y": -0.002, "z": 0.0},
    "magnetometer": {"x": 23.4, "y": -12.1, "z": 45.6}
  }
}
```

**Client → Server (Activity Recognition):**
```json
{
  "type": "predict_activity",
  "timestamp": "2025-12-27T10:30:45.123Z",
  "data": {
    "accelerometer": {"x": 0.123, "y": 9.81, "z": 0.045},
    "gyroscope": {"x": 0.001, "y": -0.002, "z": 0.0},
    "magnetometer": {"x": 23.4, "y": -12.1, "z": 45.6}
  }
}
```

**Server → Client (Collection Acknowledgment):**
```json
{
  "type": "collection_ack",
  "samples_collected": 150,
  "activity": "walking",
  "timestamp": "2025-12-27T10:30:45.678Z"
}
```

**Server → Client (Activity Prediction):**
```json
{
  "type": "activity_prediction",
  "activity": "walking",
  "confidence": 0.85,
  "timestamp": "2025-12-27T10:30:45.678Z",
  "window_size": 200
}
```

## 🧪 Development Workflow

### Testing Without Physical Device

1. Enable Demo Mode in the app
2. Run on emulator/simulator
3. Demo Mode generates realistic sensor patterns
4. Server receives simulated data and sends predictions

### Testing With Physical Device

1. Connect Android device via USB
2. Run `flutter run`
3. Phone must be on same network as server
4. Use server's local IP address in app settings
```
echo "Your WebSocket URL is: ws://$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1):8000/ws"
```

## 🛠️ Technology Stack

**Current Implementation:**
- **Mobile:** Flutter (Dart), Provider pattern
- **Server:** Python with `websockets`, asyncio
- **Communication:** WebSocket protocol (bidirectional)
- **State Management:** Provider pattern
- **Sensors:** sensors_plus package (50Hz sampling)
- **Data Storage:** CSV files (activity-organized)




