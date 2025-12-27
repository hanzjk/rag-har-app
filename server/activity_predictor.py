"""
Activity Predictor Module
Handles activity prediction/classification based on sensor data.
Uses sliding window approach for temporal pattern recognition.
"""

import logging
from datetime import datetime, timezone
from typing import Dict, Any
from collections import deque
import statistics

logger = logging.getLogger(__name__)


class ActivityPredictor:
    """
    Activity prediction engine.
    Uses sliding window approach to analyze temporal patterns.
    Currently uses rule-based classification on windowed features.
    Can be extended to use ML models.
    """

    def __init__(self, window_size: int = 200, min_samples: int = 100, step_size: int = 50):
        """
        Initialize the activity predictor with sliding window.

        Args:
            window_size: Number of samples in the sliding window (default: 200 = 4 seconds at 50Hz)
            min_samples: Minimum samples needed before making predictions (default: 100 = 2 seconds)
            step_size: Number of samples between predictions (default: 50 = 1 second, 75% overlap)
        """
        self.window_size = window_size
        self.min_samples = min_samples
        self.step_size = step_size

        # Sliding window buffer (stores recent sensor readings)
        self.window = deque(maxlen=window_size)

        self.samples_received = 0
        self.samples_since_last_prediction = 0

        logger.info(
            f"Activity predictor initialized with sliding window "
            f"(window_size={window_size}, min_samples={min_samples}, step_size={step_size})"
        )

    def predict(self, sensor_data: dict) -> Dict[str, Any] | None:
        """
        Add sensor data to window and make prediction based on step size.

        Args:
            sensor_data: Dictionary containing sensor readings

        Returns:
            dict: Prediction with activity, confidence, and timestamp (None if not at step boundary)
        """
        # Add new sample to sliding window
        self._add_to_window(sensor_data)

        # Only make prediction every step_size samples
        if self.samples_since_last_prediction >= self.step_size:
            self.samples_since_last_prediction = 0  # Reset counter
            return self._predict_from_window()
        else:
            self.samples_since_last_prediction += 1
            return None  # No prediction this sample

    def _add_to_window(self, sensor_data: dict):
        """
        Add sensor reading to the sliding window buffer.

        Args:
            sensor_data: Dictionary containing sensor readings
        """
        try:
            accel = sensor_data['data']['accelerometer']
            gyro = sensor_data['data']['gyroscope']
            mag = sensor_data['data']['magnetometer']

            # Store flattened sensor reading
            sample = {
                'timestamp': sensor_data.get('timestamp'),
                'accel_x': accel['x'],
                'accel_y': accel['y'],
                'accel_z': accel['z'],
                'gyro_x': gyro['x'],
                'gyro_y': gyro['y'],
                'gyro_z': gyro['z'],
                'mag_x': mag['x'],
                'mag_y': mag['y'],
                'mag_z': mag['z'],
            }

            self.window.append(sample)
            self.samples_received += 1

            if self.samples_received == self.min_samples:
                logger.info(f"Window filled with {self.min_samples} samples, predictions now active")

        except Exception as e:
            logger.error(f"Error adding sample to window: {e}")

    def _predict_from_window(self) -> Dict[str, Any]:
        """
        Make prediction based on current sliding window.

        Returns:
            dict: Prediction with activity, confidence, and timestamp
        """
        # Need minimum samples before making predictions
        if len(self.window) < self.min_samples:
            return {
                "type": "activity_prediction",
                "activity": "initializing",
                "confidence": 0.0,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "window_size": len(self.window),
                "status": "buffering"
            }

        # Extract features from window
        features = self._extract_features()

        # Make prediction using rule-based or ML model
        return self._predict_rule_based_windowed(features)

    def _extract_features(self) -> Dict[str, float]:
        """
        Extract statistical features from the sliding window.

        Returns:
            dict: Extracted features (mean, std, min, max, magnitude stats)
        """
        # Convert window to lists for each sensor axis
        accel_x = [s['accel_x'] for s in self.window]
        accel_y = [s['accel_y'] for s in self.window]
        accel_z = [s['accel_z'] for s in self.window]

        gyro_x = [s['gyro_x'] for s in self.window]
        gyro_y = [s['gyro_y'] for s in self.window]
        gyro_z = [s['gyro_z'] for s in self.window]

        # Calculate magnitudes for each sample
        accel_magnitudes = [
            (s['accel_x']**2 + s['accel_y']**2 + s['accel_z']**2)**0.5
            for s in self.window
        ]

        gyro_magnitudes = [
            (s['gyro_x']**2 + s['gyro_y']**2 + s['gyro_z']**2)**0.5
            for s in self.window
        ]

        # Extract statistical features
        features = {
            # Accelerometer magnitude features
            'accel_mag_mean': statistics.mean(accel_magnitudes),
            'accel_mag_std': statistics.stdev(accel_magnitudes) if len(accel_magnitudes) > 1 else 0,
            'accel_mag_min': min(accel_magnitudes),
            'accel_mag_max': max(accel_magnitudes),

            # Gyroscope magnitude features
            'gyro_mag_mean': statistics.mean(gyro_magnitudes),
            'gyro_mag_std': statistics.stdev(gyro_magnitudes) if len(gyro_magnitudes) > 1 else 0,
            'gyro_mag_min': min(gyro_magnitudes),
            'gyro_mag_max': max(gyro_magnitudes),

            # Accelerometer axis features
            'accel_x_mean': statistics.mean(accel_x),
            'accel_y_mean': statistics.mean(accel_y),
            'accel_z_mean': statistics.mean(accel_z),
            'accel_x_std': statistics.stdev(accel_x) if len(accel_x) > 1 else 0,
            'accel_y_std': statistics.stdev(accel_y) if len(accel_y) > 1 else 0,
            'accel_z_std': statistics.stdev(accel_z) if len(accel_z) > 1 else 0,

            # Gyroscope axis features
            'gyro_x_mean': statistics.mean(gyro_x),
            'gyro_y_mean': statistics.mean(gyro_y),
            'gyro_z_mean': statistics.mean(gyro_z),
            'gyro_x_std': statistics.stdev(gyro_x) if len(gyro_x) > 1 else 0,
            'gyro_y_std': statistics.stdev(gyro_y) if len(gyro_y) > 1 else 0,
            'gyro_z_std': statistics.stdev(gyro_z) if len(gyro_z) > 1 else 0,
        }

        return features

    def _predict_rule_based_windowed(self, features: Dict[str, float]) -> Dict[str, Any]:
        """
        Rule-based activity prediction using windowed features.
        Uses temporal patterns (mean and std) for better accuracy.

        Args:
            features: Extracted features from sliding window

        Returns:
            dict: Prediction with activity, confidence, and timestamp
        """
        try:
            # Extract key features
            accel_mean = features['accel_mag_mean']
            accel_std = features['accel_mag_std']
            gyro_mean = features['gyro_mag_mean']
            gyro_std = features['gyro_mag_std']

            # Enhanced rule-based classification using temporal patterns
            # High std indicates periodic movement (walking/running)
            # Low std indicates static position (sitting/standing)

            # RUNNING: High acceleration, high variation, high rotation
            if accel_mean > 14 and accel_std > 2.0 and gyro_mean > 0.3:
                activity = "running"
                confidence = 0.90

            # WALKING: Moderate acceleration, moderate variation, moderate rotation
            elif accel_mean > 10.5 and accel_std > 0.8 and gyro_mean > 0.15:
                activity = "walking"
                confidence = 0.85

            # SITTING: Low acceleration (just gravity), very low variation, minimal rotation
            elif accel_mean < 10.5 and accel_std < 0.3 and gyro_mean < 0.05:
                activity = "sitting"
                confidence = 0.92

            # STANDING: Low-moderate acceleration, low variation, low rotation
            elif accel_mean < 11 and accel_std < 0.5 and gyro_mean < 0.1:
                activity = "standing"
                confidence = 0.80

            # Borderline cases - use additional features
            elif accel_std > 1.0:  # High variation suggests movement
                activity = "walking"
                confidence = 0.65
            else:  # Low variation suggests stationary
                activity = "standing"
                confidence = 0.60

            return {
                "type": "activity_prediction",
                "activity": activity,
                "confidence": confidence,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "window_size": len(self.window),
                "features": {
                    "accel_mean": round(accel_mean, 2),
                    "accel_std": round(accel_std, 2),
                    "gyro_mean": round(gyro_mean, 3),
                    "gyro_std": round(gyro_std, 3)
                }
            }

        except Exception as e:
            logger.error(f"Error predicting activity from window: {e}")
            return {
                "type": "activity_prediction",
                "activity": "unknown",
                "confidence": 0.0,
                "timestamp": datetime.now(timezone.utc).isoformat()
            }

    def reset_window(self):
        """Clear the sliding window buffer."""
        self.window.clear()
        self.samples_received = 0
        logger.info("Sliding window reset")

    def get_window_stats(self) -> Dict[str, Any]:
        """
        Get current window statistics.

        Returns:
            dict: Window statistics
        """
        return {
            "window_size": len(self.window),
            "max_window_size": self.window_size,
            "min_samples": self.min_samples,
            "samples_received": self.samples_received,
            "is_ready": len(self.window) >= self.min_samples
        }
