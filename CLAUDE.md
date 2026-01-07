# CLAUDE.md

Development guide for Claude Code when working with this RAG-HAR system.

## Project Overview

RAG-based Human Activity Recognition system with Flutter mobile app and Python WebSocket server.

**Mobile App**: Android app for sensor data collection and real-time activity recognition
**Server**: WebSocket server with RAG pipeline for activity classification using LLM reasoning

## Repository Structure

```
har-demo/
├── mobile/              # Flutter mobile app
│   ├── lib/
│   │   ├── models/     # SensorData, ActivityType
│   │   ├── providers/  # AppStateProvider, SensorDataProvider, ActivityProvider
│   │   ├── services/   # SensorService, WebSocketService, PermissionService
│   │   ├── screens/    # Data collection, Activity recognition, Settings
│   │   └── widgets/    # Reusable UI components
│   └── pubspec.yaml
│
├── server/             # Python WebSocket server + RAG pipeline
│   ├── websocket_server.py      # WebSocket handler
│   ├── data_collector.py        # Save labeled sensor data
│   ├── activity_predictor.py    # Sliding window + RAG classifier
│   ├── rag-har/                 # RAG pipeline
│   │   ├── preprocessing.py     # Train/test split
│   │   ├── features.py          # Statistical feature extraction
│   │   ├── timeseries_indexing.py  # Vector database indexing
│   │   ├── classifier.py        # RAG-based classifier
│   │   └── rag_pipeline.py      # End-to-end pipeline
│   └── requirements.txt
│
└── README.md
```

## Development Commands

### Server

```bash
cd server
pip install -r requirements.txt

# Set environment variables
export OPENAI_API_KEY="your-key"
export ZILLIZ_CLOUD_URI="your-uri"
export ZILLIZ_CLOUD_API_KEY="your-key"

python websocket_server.py  # Runs on ws://0.0.0.0:8000
```

### Mobile App

```bash
cd mobile
flutter pub get
flutter run
```

## Architecture

### State Management (Provider Pattern)
- `AppStateProvider` - WebSocket URL, connection state
- `SensorDataProvider` - Sensor collection, window-based buffering
- `ActivityProvider` - Activity predictions, history

### Services
- `SensorService` - Accelerometer + gyroscope at 50Hz
- `WebSocketService` - Bidirectional WebSocket communication
- `PermissionService` - Runtime sensor permissions

## WebSocket Protocol

### Client → Server

**Data Collection:**
```json
{
  "type": "collect_data",
  "subject_id": "subject0",
  "activity": "walking",
  "timestamp": "2025-01-05T10:30:45.123Z",
  "data": {
    "accelerometer": {"x": 0.123, "y": 9.81, "z": 0.045},
    "gyroscope": {"x": 0.001, "y": -0.002, "z": 0.0}
  }
}
```

**Stop Collection (triggers RAG pipeline):**
```json
{
  "type": "stop_collection",
  "timestamp": "2025-01-05T10:30:45.123Z"
}
```

**Activity Prediction:**
```json
{
  "type": "predict_activity",
  "timestamp": "2025-01-05T10:30:45.123Z",
  "data": {
    "accelerometer": {"x": 0.123, "y": 9.81, "z": 0.045},
    "gyroscope": {"x": 0.001, "y": -0.002, "z": 0.0}
  }
}
```

### Server → Client

**Activity Prediction:**
```json
{
  "type": "activity_prediction",
  "activity": "walking",
  "reasoning": "The acceleration patterns show periodic vertical oscillations...",
  "timestamp": "2025-01-05T10:30:45.678Z",
  "window_size": 200,
  "method": "rag_classifier"
}
```

## Supported Activities

- walking
- running
- sitting
- standing
- jumping
- lying_down

## RAG Pipeline

**Data Collection Flow:**
1. Mobile app sends labeled sensor data (`collect_data`)
2. Server saves to `collected_data/subject_timestamp/activity.csv`
3. Mobile sends `stop_collection` signal
4. Server runs RAG pipeline:
   - Preprocessing: Train/test split, windowing
   - Feature extraction: Statistical features with temporal segmentation
   - Indexing: Embed and store in Milvus/Zilliz
   - Ready for classification

**Activity Prediction Flow:**
1. Mobile sends 200 samples (4 seconds at 50Hz)
2. ActivityPredictor buffers samples
3. RAG Classifier:
   - Extract features (temporal segments: whole, start, mid, end)
   - Generate embeddings (OpenAI text-embedding-3-small)
   - Hybrid search in Milvus (retrieve top 10 similar samples)
   - LLM classification (GPT-5-mini with retrieved context)
4. Server sends prediction with reasoning

**Configuration:**
- Window size: 200 samples (4 seconds)
- Step size: 200 samples (non-overlapping)
- Retrieval: 15 samples per segment → 10 final
- Sensors: Accelerometer, Gyroscope (6 axes)

## Configuration

**Default WebSocket URL:** `ws://192.168.1.100:8000/ws`

**Android Emulator:** `ws://10.0.2.2:8000/ws`

**Physical Device:** `ws://YOUR_LOCAL_IP:8000/ws` (same network as server)

## Testing

**Data Collection Mode:**
1. Select activity label
2. Start collection (perform activity 10-20 seconds)
3. Stop (triggers RAG pipeline)

**Activity Recognition Mode:**
1. Start recognition
2. Perform activity
3. View prediction + LLM reasoning every 4 seconds
