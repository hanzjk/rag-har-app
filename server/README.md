# WebSocket Server for RAG-Based Activity Recognition

Python WebSocket server for Human Activity Recognition (HAR) with two modes:
1. **Data Collection** - Saves labeled sensor data to CSV files
2. **Activity Prediction** - Real-time classification using RAG (Retrieval-Augmented Generation)

## Features

- **Dual-mode operation:** Collect labeled data or predict activities in real-time
- **RAG-based classification:** Uses LLM with hybrid vector search (Milvus + OpenAI)
- **Automatic pipeline:** Preprocessing → Feature extraction → Vector indexing
- **Session-based tracking:** Incremental updates, no duplicate processing
- **Supported activities:** Walking, running, sitting, standing, jumping, lying

## Architecture

```
server/
├── websocket_server.py       # WebSocket server (handles connections)
├── data_collector.py          # Saves sensor data to CSV
├── activity_predictor.py      # Real-time prediction wrapper
└── rag-har/                   # RAG-HAR pipeline
    ├── rag_pipeline.py        # Pipeline orchestrator
    ├── preprocessing.py       # Windowing & train/test split
    ├── features.py            # Statistical feature extraction
    ├── timeseries_indexing.py # Vector database indexing
    └── classifier.py          # RAG classifier & evaluation
```

## Setup

### Requirements

- Python 3.8+
- OpenAI API key
- Milvus/Zilliz Cloud account

### Installation

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Create `.env` file:
```bash
OPENAI_API_KEY=your_openai_api_key
ZILLIZ_CLOUD_URI=your_milvus_uri
ZILLIZ_CLOUD_API_KEY=your_milvus_api_key
```

## Running the Server

Start the WebSocket server:
```bash
python websocket_server.py
```

The server starts on `ws://0.0.0.0:8000` and handles both data collection and prediction.

### Connect from Mobile App

1. Find your local IP: `ifconfig | grep "inet "` (macOS/Linux) or `ipconfig` (Windows)
2. In the Flutter app → Settings → Set WebSocket URL to: `ws://YOUR_IP:8000/ws`
3. Example: `ws://192.168.1.100:8000/ws`

## Workflow

### 1. Collect Data

Mobile app sends `collect_data` messages → Server saves to `collected_data/subject0_TIMESTAMP/activity.csv`

When collection stops, the RAG-HAR pipeline runs automatically:
- **Preprocessing**: Segments data into 200-sample windows (4s at 50Hz), 50% overlap
- **Feature Extraction**: Computes statistical features (mean, std, min, max, etc.) for temporal segments
- **Indexing**: Creates embeddings and stores in Milvus vector database

### 2. Predict Activity

Mobile app sends `predict_activity` messages → Server uses RAG classifier:
- Extracts features from sensor window
- Performs hybrid search in Milvus (retrieves 15 similar samples per temporal segment)
- LLM classifies activity based on retrieved context

## Message Format

### Client → Server (Data Collection)
```json
{
  "type": "collect_data",
  "timestamp": "2026-01-04T10:30:45.123Z",
  "activity": "walking",
  "subject_id": "subject0",
  "data": {
    "accelerometer": {"x": 0.123, "y": 9.81, "z": 0.045},
    "gyroscope": {"x": 0.001, "y": -0.002, "z": 0.0},
    "magnetometer": {"x": 23.4, "y": -12.1, "z": 45.6}
  }
}
```

### Client → Server (Prediction)
```json
{
  "type": "predict_activity",
  "timestamp": "2026-01-04T10:30:45.123Z",
  "data": {
    "accelerometer": {"x": 0.123, "y": 9.81, "z": 0.045},
    "gyroscope": {"x": 0.001, "y": -0.002, "z": 0.0},
    "magnetometer": {"x": 23.4, "y": -12.1, "z": 45.6}
  }
}
```

### Server → Client (Prediction Response)
```json
{
  "type": "activity_prediction",
  "activity": "walking",
  "timestamp": "2026-01-04T10:30:45.678Z"
}
```

## Running Pipeline Manually

Process collected data:
```bash
cd rag-har
python rag_pipeline.py
```

Evaluate classifier on test set:
```bash
cd rag-har
python classifier.py
```

Results saved to `output/har_demo/test_evaluation_results.json`

## Data Organization

```
collected_data/
└── subject0_20260104_153045/    # Session folder
    ├── walking.csv
    ├── sitting.csv
    └── running.csv

output/har_demo/
├── train-test-splits/
│   ├── train/
│   │   └── subject0_20260104_153045/
│   │       └── walking/
│   │           └── subject0_20260104_153045_window_0_walking.csv
│   └── test/
├── features/
│   ├── train/descriptions/
│   │   └── subject0_20260104_153045/
│   │       └── subject0_20260104_153045_window_0_activity_walking_stats.txt
│   └── test/descriptions/
├── processed_sessions.txt                     # Tracks preprocessing
├── processed_features_sessions_train.txt      # Tracks feature extraction (train)
├── processed_features_sessions_test.txt       # Tracks feature extraction (test)
└── processed_indexing_sessions.txt            # Tracks vector indexing
```

## Troubleshooting

**Connection refused:**
- Check server is running
- Verify IP address and port
- Check firewall settings

**RAG classifier fails to initialize:**
- Verify `.env` file exists with correct API keys
- Check OpenAI and Milvus credentials

**No predictions received:**
- Check server logs for errors
- Ensure sensor data format matches expected JSON structure
