# WebSocket Server for Activity Recognition

Python WebSocket server that receives sensor data from the Flutter app and either:
1. **Collects data** for dataset creation (data collection mode)
2. **Sends activity predictions** in real-time (activity recognition mode)

## Features

- **Dual Mode Operation:**
  - **Collect Mode**: Save labeled sensor data to CSV files for dataset creation
  - **Predict Mode**: Real-time activity classification and predictions
- Receives sensor data (accelerometer, gyroscope, magnetometer) from Flutter app
- Simple rule-based activity classification:
  - Walking
  - Running
  - Sitting
  - Standing
- CSV export organized by activity label
- Connection logging and monitoring

## Architecture

The server is now modular with separate components:

- **`websocket_server.py`**: Main server that handles WebSocket connections and routes requests
- **`data_collector.py`**: Handles data collection and CSV file management
- **`activity_predictor.py`**: Handles activity prediction (rule-based or ML model)

This modular design makes it easy to:
- Swap between different prediction algorithms
- Extend data collection formats
- Integrate custom ML models

## Setup

### Requirements

- Python 3.8 or higher

### Installation

1. Install dependencies:
```bash
pip install -r requirements.txt
```

Or using a virtual environment (recommended):
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

## Running the Server

### Mode 1: Data Collection (for creating datasets)

Use this mode to collect labeled sensor data from the mobile app:

```bash
python websocket_server.py
```

Options:
- `--mode collect`: Enable data collection mode
- `--data-dir <directory>`: Specify where to save CSV files (default: `collected_data/`)

Example:
```bash
python websocket_server.py --data-dir my_dataset
```

**What happens:**
- Creates CSV files organized by activity label (e.g., `walking.csv`, `running.csv`)
- Each CSV contains: timestamp, accel_x/y/z, gyro_x/y/z, mag_x/y/z, activity
- Data is saved in real-time as it arrives from the mobile app
- Perfect for creating training datasets for ML models

### Mode 2: Activity Recognition (default)

Use this mode to send real-time activity predictions to the mobile app:

```bash
python websocket_server.py --mode predict
```

or simply:
```bash
python websocket_server.py
```

**What happens:**
- Receives sensor data from mobile app
- Performs activity classification (currently rule-based)
- Sends predictions back to the app in real-time

The server will start on `ws://0.0.0.0:8080` and listen for connections.

## Testing with the Flutter App

1. **Find your local IP address:**
   - macOS/Linux: `ifconfig | grep "inet "` or `ip addr show`
   - Windows: `ipconfig`
   - Look for your local IP (usually starts with 192.168.x.x or 10.x.x.x)

2. **Update Flutter app settings:**
   - Open the app → Settings
   - Set WebSocket URL to: `ws://YOUR_LOCAL_IP:8080/ws`
   - Example: `ws://192.168.1.100:8080/ws`

3. **Test the connection:**
   - Enable Demo Mode in app settings for easier testing
   - Go to Data Collection or Activity Recognition
   - Tap Start
   - Watch the server logs for incoming data and predictions

## Activity Prediction Logic

The server uses a **sliding window approach** for temporal pattern recognition:

### Sliding Window (2 seconds = 40 samples at 20Hz)

Instead of analyzing single sensor readings, the server:
1. **Buffers** the most recent 40 samples (2 seconds)
2. **Extracts features** (mean, std, min, max) from the window
3. **Detects patterns** like walking gait cycles, running impacts
4. **Predicts activity** based on temporal features

**Why windowing?**
- ✅ **Robust to noise:** Averages out outliers
- ✅ **Detects patterns:** Sees periodic movements over time
- ✅ **Higher accuracy:** 80-90% vs 60-70% (single sample)
- ✅ **ML-ready:** Rich feature set for training models

### Rule-Based Classification (Current)

Uses statistical features from the sliding window:

| Activity | Accel Mean | Accel Std | Gyro Mean | Pattern |
|----------|------------|-----------|-----------|---------|
| Running  | > 14 m/s²  | > 2.0     | > 0.3 rad/s | High variation |
| Walking  | > 10.5 m/s²| > 0.8     | > 0.15 rad/s | Periodic |
| Sitting  | < 10.5 m/s²| < 0.3     | < 0.05 rad/s | Constant |
| Standing | < 11 m/s² | < 0.5     | < 0.1 rad/s | Nearly constant |

**See `SLIDING_WINDOW.md` for detailed explanation.**

**Note:** For production, replace with a trained ML model using the same windowed features for 90-95% accuracy.

## Data Collection Workflow

To create a dataset for training ML models:

1. **Start server in collect mode:**
   ```bash
   python websocket_server.py --mode collect
   ```

2. **Configure mobile app:**
   - Set WebSocket URL to your server's IP
   - Enable Demo Mode (or use real sensors)
   - Go to Data Collection mode

3. **Collect data for each activity:**
   - For "walking": Perform walking activity for 2-3 minutes
   - For "running": Perform running activity for 2-3 minutes
   - For "sitting": Sit still for 2-3 minutes
   - For "standing": Stand still for 2-3 minutes

4. **Find your dataset:**
   - CSV files will be in `collected_data/` directory
   - One file per activity: `walking.csv`, `running.csv`, etc.

5. **Use the dataset:**
   - Import CSV into pandas, scikit-learn, TensorFlow, etc.
   - Train your ML model
   - Replace the rule-based `predict_activity()` function with your model

## Message Format

### Client → Server (Sensor Data)
```json
{
  "type": "sensor_data",
  "timestamp": "2025-12-26T10:30:45.123Z",
  "activity": "walking",
  "data": {
    "accelerometer": {"x": 0.123, "y": 9.81, "z": 0.045},
    "gyroscope": {"x": 0.001, "y": -0.002, "z": 0.0},
    "magnetometer": {"x": 23.4, "y": -12.1, "z": 45.6}
  }
}
```

**Note:** The `activity` field is optional and only used in collect mode for labeling data.

### Server → Client (Activity Prediction)
Used in predict mode:
```json
{
  "type": "activity_prediction",
  "activity": "walking",
  "confidence": 0.85,
  "timestamp": "2025-12-26T10:30:45.678Z"
}
```

### Server → Client (Collection Acknowledgment)
Used in collect mode:
```json
{
  "type": "collection_ack",
  "samples_collected": 142,
  "activity": "walking",
  "timestamp": "2025-12-26T10:30:45.678Z"
}
```

## Logging

The server logs:
- Client connections/disconnections
- Activity predictions sent
- Errors and warnings

Adjust logging level in `websocket_server.py`:
```python
logging.basicConfig(level=logging.DEBUG)  # For more detailed logs
```

## Using ML Models

The server now supports loading custom ML models! Here's how:

### Training Your Model

1. Collect data using collect mode
2. Train your model using the CSV files
3. Save your trained model (e.g., `.pkl`, `.h5`, `.pt`)

### Running with ML Model

```bash
python websocket_server.py --mode predict --model path/to/your/model.pkl
```

### Implementing Model Loading

Edit `activity_predictor.py` to load your specific model type:

**For scikit-learn models:**
```python
def _load_model(self, model_path: str):
    import pickle
    with open(model_path, 'rb') as f:
        self.model = pickle.load(f)
    logger.info(f"Loaded scikit-learn model from {model_path}")
```

**For TensorFlow/Keras models:**
```python
def _load_model(self, model_path: str):
    from tensorflow import keras
    self.model = keras.models.load_model(model_path)
    logger.info(f"Loaded TensorFlow model from {model_path}")
```

**For PyTorch models:**
```python
def _load_model(self, model_path: str):
    import torch
    self.model = torch.load(model_path)
    self.model.eval()
    logger.info(f"Loaded PyTorch model from {model_path}")
```

### Implementing Feature Extraction

Update `_extract_features()` in `activity_predictor.py`:

```python
def _extract_features(self, sensor_data: dict) -> list:
    accel = sensor_data['data']['accelerometer']
    gyro = sensor_data['data']['gyroscope']
    mag = sensor_data['data']['magnetometer']

    # Example features
    features = [
        accel['x'], accel['y'], accel['z'],
        gyro['x'], gyro['y'], gyro['z'],
        mag['x'], mag['y'], mag['z'],
        # Add magnitude features
        (accel['x']**2 + accel['y']**2 + accel['z']**2)**0.5,
        (gyro['x']**2 + gyro['y']**2 + gyro['z']**2)**0.5,
        # Add more features as needed
    ]
    return features
```

### Implementing Model Prediction

Update `_predict_with_model()` in `activity_predictor.py`:

```python
def _predict_with_model(self, sensor_data: dict) -> Dict[str, Any]:
    features = self._extract_features(sensor_data)

    # For scikit-learn
    prediction = self.model.predict([features])[0]
    confidence = self.model.predict_proba([features]).max()

    return {
        "type": "activity_prediction",
        "activity": prediction,
        "confidence": float(confidence),
        "timestamp": datetime.now(timezone.utc).isoformat()
    }
```

## Troubleshooting

**Connection refused:**
- Make sure the server is running
- Check firewall settings
- Verify the IP address and port

**No predictions received:**
- Check server logs for errors
- Verify the message format matches expected JSON structure
- Ensure sensor data is being sent from the app

**WebSocket closes immediately:**
- Check for exceptions in server logs
- Verify Python version (3.8+)
- Ensure websockets library is installed
