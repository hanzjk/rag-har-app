# RAG-HAR: Human Activity Recognition with Retrieval-Augmented Generation

Real-time human activity recognition system using RAG-based classification with LLM reasoning.

## System Architecture

```
Flutter Mobile App
    ↓ WebSocket
Python Server (RAG-HAR Pipeline)
    ├─ Feature Extraction (temporal segmentation)
    ├─ Vector Search (Milvus/Zilliz)
    └─ LLM Classification (GPT-4o-mini)
    ↓ WebSocket
Mobile App (activity + reasoning)
```

## Project Structure

```
har-demo/
├── mobile/              # Flutter Android app
│   ├── lib/
│   │   ├── providers/  # State management (Provider pattern)
│   │   ├── services/   # Sensors, WebSocket, permissions
│   │   ├── screens/    # Data collection, Activity recognition, Settings
│   │   └── widgets/    # UI components
│   └── pubspec.yaml
│
├── server/             # Python WebSocket server + RAG pipeline
│   ├── websocket_server.py     # WebSocket handler
│   ├── data_collector.py       # Save labeled sensor data
│   ├── activity_predictor.py   # Sliding window + RAG classifier
│   ├── rag-har/                # RAG pipeline
│   │   ├── preprocessing.py    # Train/test split
│   │   ├── features.py         # Statistical feature extraction
│   │   ├── timeseries_indexing.py  # Vector database indexing
│   │   ├── classifier.py       # RAG-based classifier
│   │   └── rag_pipeline.py     # End-to-end pipeline
│   └── requirements.txt
│
└── CLAUDE.md          # Development guide
```

## Features

### Mobile App
- **Data Collection Mode**: Label and collect sensor data for training
  - 50Hz sampling (accelerometer, gyroscope)
  - Subject ID and activity labeling
  - CSV export with timestamps

- **Activity Recognition Mode**: Real-time prediction with explanation
  - Window-based collection (200 samples = 4 seconds)
  - Activity display with LLM reasoning
  - History tracking

- **Demo Mode**: Test without physical sensors (works on emulators)

### Server (RAG-HAR Pipeline)

**Data Collection:**
- Saves labeled sensor data to `collected_data/subject_timestamp/`
- Triggers RAG pipeline on `stop_collection` signal

**RAG Pipeline Stages:**
1. **Preprocessing**: Train/test split, windowing
2. **Feature Extraction**: Statistical features with temporal segmentation (whole, start, mid, end)
3. **Vector Indexing**: Embed and store in Milvus/Zilliz
4. **Classification**: Hybrid search + LLM reasoning

**Activity Prediction:**
- Real-time classification using RAG
- Returns activity label + reasoning explanation
- Non-overlapping 4-second windows

## Supported Activities

- Walking
- Running
- Sitting
- Standing
- Jumping
- Lying

## Quick Start

### 1. Server Setup

```bash
cd server

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export OPENAI_API_KEY="your-key"
export ZILLIZ_CLOUD_URI="your-uri"
export ZILLIZ_CLOUD_API_KEY="your-key"

# Run server
python websocket_server.py
```

Server runs on `ws://0.0.0.0:8000`

### 2. Mobile App Setup

```bash
cd mobile

# Install dependencies
flutter pub get

# Run app
flutter run
```

### 3. Configure Connection

**Android Emulator:**
- Settings → WebSocket URL: `ws://10.0.2.2:8000/ws`

**Physical Device:**
```bash
# Find your local IP
ifconfig | grep "inet " | grep -v 127.0.0.1

# In app settings
ws://YOUR_LOCAL_IP:8000/ws
```

## Usage

### Collect Training Data

1. Open app → Data Collection
2. Select activity label
3. Tap Start, perform activity for 10-20 seconds
4. Tap Stop (triggers RAG pipeline automatically)
5. Server processes and indexes data to vector database

### Real-Time Recognition

1. Open app → Activity Recognition
2. Tap Start
3. Perform activity
4. View prediction with LLM reasoning every 4 seconds

## WebSocket Protocol

### Client → Server

**Collect Data:**
```json
{
  "type": "collect_data",
  "subject_id": "subject0",
  "activity": "walking",
  "timestamp": "2025-01-05T10:30:45.123Z",
  "data": {
    "accelerometer": {"x": 0.123, "y": 9.81, "z": 0.045},
    "gyroscope": {"x": 0.001, "y": -0.002, "z": 0.0},
  }
}
```

**Stop Collection:**
```json
{
  "type": "stop_collection",
  "timestamp": "2025-01-05T10:30:45.123Z"
}
```

**Predict Activity:**
```json
{
  "type": "predict_activity",
  "timestamp": "2025-01-05T10:30:45.123Z",
  "data": {
    "accelerometer": {"x": 0.123, "y": 9.81, "z": 0.045},
    "gyroscope": {"x": 0.001, "y": -0.002, "z": 0.0},
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

## RAG Classification Details

**How it works:**

1. **Feature Extraction**: Split 4-second window into temporal segments (whole, start 33%, mid 33%, end 33%)
2. **Embedding**: Generate vector embeddings for each segment using OpenAI text-embedding-3-small
3. **Retrieval**: Hybrid search in Milvus for top 10 similar training samples (15 per segment → weighted reranking)
4. **Classification**: GPT-4o-mini analyzes retrieved examples and predicts activity with reasoning

**Why RAG?**
- ✅ Human-readable explanations for each prediction
- ✅ Semantic understanding vs pattern matching
- ✅ Add new activities without retraining (just update vector DB)
- ✅ Leverages LLM knowledge about physics and motion

## Technology Stack

- **Mobile**: Flutter, Provider, sensors_plus
- **Server**: Python, websockets, asyncio
- **RAG**: LangChain, OpenAI (embeddings + GPT-4o-mini)
- **Vector DB**: Milvus/Zilliz Cloud
- **Features**: pandas, numpy (statistical feature extraction)

## Development

For detailed development guide, see [CLAUDE.md](CLAUDE.md).

For server-specific documentation, see [server/README.md](server/README.md).
