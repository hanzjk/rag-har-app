"""
Activity Predictor Module
Handles activity prediction/classification based on sensor data.
Uses sliding window approach with RAG-based classifier.
"""

import logging
from datetime import datetime, timezone
from typing import Dict, Any, Optional
from collections import deque
import pandas as pd

logger = logging.getLogger(__name__)


class ActivityPredictor:
    """
    Activity prediction engine.
    Uses sliding window approach with RAG-based classifier for activity recognition.
    """

    def __init__(
        self,
        classifier=None,
        window_size: int = 200,
        min_samples: int = 100,
        step_size: int = 50,
    ):
        """
        Initialize the activity predictor with sliding window.

        Args:
            classifier: RAGActivityClassifier instance (optional, for real predictions)
            window_size: Number of samples in the sliding window (default: 200 = 4 seconds at 50Hz)
            min_samples: Minimum samples needed before making predictions (default: 100 = 2 seconds)
            step_size: Number of samples between predictions (default: 50 = 1 second, 75% overlap)
        """
        self.classifier = classifier
        self.window_size = window_size
        self.min_samples = min_samples
        self.step_size = step_size

        # Sliding window buffer (stores recent sensor readings)
        self.window = deque(maxlen=window_size)

        self.samples_received = 0
        self.samples_since_last_prediction = 0

        mode = "RAG-based" if classifier else "mock"
        logger.info(
            f"Activity predictor initialized with {mode} classification "
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
            logger.info(
                f"Step boundary reached ({self.step_size} samples). "
                f"Window: {len(self.window)}/{self.window_size} samples. Making prediction..."
            )
            self.samples_since_last_prediction = 0  # Reset counter
            return self._predict_from_window()
        else:
            self.samples_since_last_prediction += 1
            logger.debug(
                f"Buffering sample {self.samples_since_last_prediction}/{self.step_size}. "
                f"Window: {len(self.window)}/{self.window_size}"
            )
            return None  # No prediction this sample

    def _add_to_window(self, sensor_data: dict):
        """
        Add sensor reading to the sliding window buffer.

        Args:
            sensor_data: Dictionary containing sensor readings
        """
        try:
            accel = sensor_data["data"]["accelerometer"]
            gyro = sensor_data["data"]["gyroscope"]
            mag = sensor_data["data"]["magnetometer"]

            # Store flattened sensor reading
            sample = {
                "timestamp": sensor_data.get("timestamp"),
                "accel_x": accel["x"],
                "accel_y": accel["y"],
                "accel_z": accel["z"],
                "gyro_x": gyro["x"],
                "gyro_y": gyro["y"],
                "gyro_z": gyro["z"],
                "mag_x": mag["x"],
                "mag_y": mag["y"],
                "mag_z": mag["z"],
            }

            self.window.append(sample)
            self.samples_received += 1

            if self.samples_received == self.min_samples:
                logger.info(
                    f"Window filled with {self.min_samples} samples, predictions now active"
                )

        except Exception as e:
            logger.error(f"Error adding sample to window: {e}")

    def _predict_from_window(self) -> Dict[str, Any]:
        """
        Make prediction based on current sliding window using RAG classifier.

        Returns:
            dict: Prediction with activity, confidence, and timestamp
        """
        # Need minimum samples before making predictions
        if len(self.window) < self.min_samples:
            logger.warning(
                f"Insufficient samples for prediction: {len(self.window)}/{self.min_samples}. "
                f"Status: buffering"
            )
            return {
                "type": "activity_prediction",
                "activity": "initializing",
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "window_size": len(self.window),
                "status": "buffering",
            }

        # Use RAG classifier if available
        if self.classifier:
            logger.info("Using RAG-based classifier for prediction")
            return self._predict_with_rag_classifier()
        else:
            # Fallback for testing without classifier
            logger.error("no RAG classifier available")
            return self._predict_mock()

    def _predict_with_rag_classifier(self) -> Dict[str, Any]:
        """
        Predict activity using RAG-based classifier.

        Returns:
            dict: Prediction with activity, confidence, and timestamp
        """
        try:
            # Convert window deque to list of dicts for classifier
            window_data = list(self.window)
            logger.info(f"Invoking RAG classifier with {len(window_data)} samples")

            # Call classifier's predict_from_window method
            result = self.classifier.predict_from_window(window_data)

            logger.info(f"RAG prediction complete: {result['activity']}")

            return {
                "type": "activity_prediction",
                "activity": result["activity"],
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "window_size": len(self.window),
                "method": "rag_classifier",
            }

        except Exception as e:
            logger.error(f"Error predicting with RAG classifier: {e}")
            return {
                "type": "activity_prediction",
                "activity": "unknown",
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "error": str(e),
            }

    def _predict_mock(self) -> Dict[str, Any]:
        """
        Mock prediction for testing without classifier.
        Returns a simple response based on window state.

        Returns:
            dict: Mock prediction with activity and timestamp
        """
        logger.info(f"Mock prediction generated: walking")
        return {
            "type": "activity_prediction",
            "activity": "walking",  # Mock activity
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "window_size": len(self.window),
            "method": "mock",
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
            "is_ready": len(self.window) >= self.min_samples,
        }
