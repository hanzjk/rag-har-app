# Human Activity Recognition System

A complete system for collecting sensor data and recognizing human activities, consisting of a Flutter mobile app and a Python WebSocket server.

## 🏗️ Project Structure

```
har-demo/
├── mobile/              # Flutter mobile application
│   ├── lib/            # Dart source code
│   ├── android/        # Android platform code
│   ├── ios/            # iOS platform code
│   ├── pubspec.yaml    # Flutter dependencies
│   └── ...             # Other Flutter files
├── server/              # Python WebSocket server
│   ├── websocket_server.py
│   ├── requirements.txt
│   └── README.md
├── CLAUDE.md           # Development guide
└── README.md           # This file
```

## 📱 Mobile App (Flutter)

Android application for human activity recognition with two modes:

### Features
- **Data Collection Mode**: Stream sensor data to server for training
- **Activity Recognition Mode**: Real-time activity prediction display
- **Demo Mode**: Test without physical sensors (perfect for emulators)
- **Sensors**: Accelerometer, Gyroscope, Magnetometer

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

Find your local IP address:
- **macOS/Linux:** `ifconfig | grep "inet "` or `hostname -I`
- **Windows:** `ipconfig`

In the Flutter app:
- Settings → Set WebSocket URL to `ws://YOUR_LOCAL_IP:8080/ws`
- Example: `ws://192.168.1.100:8080/ws`

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
Mobile App (Sensors)
    ↓ [WebSocket]
Python Server (Prediction Logic)
    ↓ [WebSocket]
Mobile App (Display Activity)
```

### Message Format

**Client → Server:**
```json
{
  "type": "sensor_data",
  "timestamp": "2025-12-26T10:30:45.123Z",
  "data": {
    "accelerometer": {"x": 0.123, "y": 9.81, "z": 0.045},
    "gyroscope": {"x": 0.001, "y": -0.002, "z": 0.0},
    "magnetometer": {"x": 23.4, "y": -12.1, "z": 45.6}
  }
}
```

**Server → Client:**
```json
{
  "type": "activity_prediction",
  "activity": "walking",
  "confidence": 0.85,
  "timestamp": "2025-12-26T10:30:45.678Z"
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

## 🛠️ Technology Stack

- **Mobile:** Flutter (Dart)
- **Server:** Python with `websockets`
- **Communication:** WebSocket protocol
- **State Management:** Provider pattern
- **Sensors:** sensors_plus package

## 📝 Next Steps

1. **Improve Predictions:** Replace rule-based logic with ML model
   - Collect training data using Data Collection mode
   - Train model (scikit-learn, TensorFlow, PyTorch)
   - Integrate model into server

2. **Add More Activities:** Extend classification
   - Cycling
   - Climbing stairs
   - Lying down

3. **Data Storage:** Save collected data for analysis
   - SQLite database
   - CSV export
   - Cloud storage

4. **UI/UX Enhancements:**
   - Charts and visualizations
   - Activity history graphs
   - Statistics dashboard

## 📄 Documentation

- [CLAUDE.md](CLAUDE.md) - Development guide for Flutter app
- [server/README.md](server/README.md) - Server documentation

## 📱 Screenshots

*(Add screenshots of your app here)*

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly (both Demo Mode and real sensors)
5. Submit a pull request

## 📜 License

*(Add your license here)*
