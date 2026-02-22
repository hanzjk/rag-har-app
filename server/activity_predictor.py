"""
Activity Predictor Module
Handles activity prediction/classification based on sensor data.
Uses sliding window approach with RAG-based classifier.
"""

import logging
import math
import uuid
import asyncio
from datetime import datetime, timezone
from typing import Dict, Any, Optional, Tuple
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
        min_samples: int = 200,
        step_size: int = 200,
    ):
        """
        Initialize the activity predictor with overlapping windows (50% overlap).

        Args:
            classifier: RAGActivityClassifier instance (optional, for real predictions)
            window_size: Number of samples in the sliding window (default: 200 = 4 seconds at 50Hz)
            min_samples: Minimum samples needed before making predictions (default: 200 = 4 seconds, same as window)
            step_size: Number of samples between predictions (default: 200 = 4 seconds, non-overlapping windows)
        """
        self.classifier = classifier
        self.window_size = window_size
        self.min_samples = min_samples
        self.step_size = step_size

        # Sliding window buffer (stores recent sensor readings)
        self.window = deque(maxlen=window_size)

        self.samples_received = 0
        self.samples_since_last_prediction = 0

        if classifier:
            logger.info(
                f"Activity predictor initialized with RAG classifier "
                f"(window_size={window_size}, min_samples={min_samples}, step_size={step_size})"
            )
        else:
            logger.warning(
                f"Activity predictor initialized WITHOUT classifier - predictions will fail! "
                f"(window_size={window_size}, min_samples={min_samples}, step_size={step_size})"
            )

    def predict(self, sensor_data: dict, fast_inference: bool = False) -> Dict[str, Any] | None:
        """
        Add sensor data to window and make prediction based on step size.

        Args:
            sensor_data: Dictionary containing sensor readings
            fast_inference: If True, use faster inference with simpler prompts

        Returns:
            dict: Prediction with activity, confidence, and timestamp (None if not at step boundary)
        """
        # Store fast_inference flag for use in prediction
        self._fast_inference = fast_inference

        # Add new sample to sliding window
        self._add_to_window(sensor_data)

        # Increment counter first
        self.samples_since_last_prediction += 1

        # Only make prediction every step_size samples
        if self.samples_since_last_prediction >= self.step_size:
            logger.info(
                f"Step boundary reached ({self.step_size} samples). "
                f"Window: {len(self.window)}/{self.window_size} samples. Making prediction... "
                f"(fast_inference={fast_inference})"
            )
            self.samples_since_last_prediction = 0  # Reset counter
            return self._predict_from_window()
        else:
            logger.debug(
                f"Buffering sample {self.samples_since_last_prediction}/{self.step_size}. "
                f"Window: {len(self.window)}/{self.window_size}"
            )
            return None  # No prediction this sample

    def capture_window(self, sensor_data: dict) -> Optional[Tuple[str, list]]:
        """
        Add sensor data to window and capture completed windows for async prediction.

        This method is NON-BLOCKING - it captures the window and returns immediately.
        The caller is responsible for submitting the window for async prediction.

        Args:
            sensor_data: Dictionary containing sensor readings

        Returns:
            Tuple of (window_id, window_data) when a complete window is ready,
            None otherwise (still buffering)
        """
        # Add new sample to sliding window
        self._add_to_window(sensor_data)

        # Increment counter
        self.samples_since_last_prediction += 1

        # Check if we have a complete window at step boundary
        if self.samples_since_last_prediction >= self.step_size:
            if len(self.window) >= self.min_samples:
                # Generate unique window ID
                window_id = str(uuid.uuid4())[:8]
                # Capture window data (copy since window will continue to be used)
                window_data = list(self.window)
                self.samples_since_last_prediction = 0

                logger.info(
                    f"Window {window_id} captured with {len(window_data)} samples"
                )
                return (window_id, window_data)
            else:
                # Not enough samples yet, reset counter
                self.samples_since_last_prediction = 0
                logger.warning(
                    f"Step boundary reached but insufficient samples: "
                    f"{len(self.window)}/{self.min_samples}"
                )
                return None
        return None

    async def predict_async(
        self, window_id: str, window_data: list, fast_inference: bool = False
    ) -> Dict[str, Any]:
        """
        Async prediction method for parallel processing.

        Args:
            window_id: Unique identifier for this window
            window_data: List of sensor reading dicts
            fast_inference: If True, use faster inference

        Returns:
            Prediction dict with window_id for correlation
        """
        if not self.classifier:
            logger.error(f"No classifier available for window {window_id}")
            return {
                "type": "activity_prediction",
                "window_id": window_id,
                "activity": "error",
                "error": "RAG classifier not initialized",
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }

        try:
            logger.info(
                f"Starting async prediction for window {window_id} "
                f"({len(window_data)} samples, fast_inference={fast_inference})"
            )

            # Use the classifier's async method
            result = await self.classifier.predict_from_window_async(
                window_data, fast_inference=fast_inference
            )

            logger.info(f"Async prediction complete for window {window_id}: {result['activity']}")

            return {
                "type": "activity_prediction",
                "window_id": window_id,
                "activity": result["activity"],
                "reasoning": result.get("reasoning"),
                "fast_inference": fast_inference,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "window_size": len(window_data),
                "method": "rag_classifier",
            }

        except Exception as e:
            logger.error(
                f"Error in async prediction for window {window_id}: {e}",
                exc_info=True
            )
            return {
                "type": "activity_prediction",
                "window_id": window_id,
                "activity": "unknown",
                "error": str(e),
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }

    def _add_to_window(self, sensor_data: dict):
        """
        Add sensor reading to the sliding window buffer.

        Args:
            sensor_data: Dictionary containing sensor readings
        """
        try:
            accel = sensor_data["data"]["accelerometer"]
            gyro = sensor_data["data"]["gyroscope"]

            # Validate no NaN/None values (critical for feature extraction consistency)
            values = [
                accel["x"],
                accel["y"],
                accel["z"],
                gyro["x"],
                gyro["y"],
                gyro["z"],
            ]
            if any(
                v is None or (isinstance(v, float) and math.isnan(v)) for v in values
            ):
                logger.warning("Skipping sample with NaN/None values")
                return

            # Log timing for first few samples to verify 50Hz sampling
            if self.samples_received < 5:
                logger.info(
                    f"Sample {self.samples_received}: timestamp={sensor_data.get('timestamp')}"
                )

            # Store flattened sensor reading
            sample = {
                "timestamp": sensor_data.get("timestamp"),
                "accel_x": accel["x"],
                "accel_y": accel["y"],
                "accel_z": accel["z"],
                "gyro_x": gyro["x"],
                "gyro_y": gyro["y"],
                "gyro_z": gyro["z"],
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
                "window_data": list(self.window),  # Include partial window
            }

        # Use RAG classifier (required)
        if not self.classifier:
            logger.error("No RAG classifier available - cannot make predictions")
            return {
                "type": "activity_prediction",
                "activity": "error",
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "error": "RAG classifier not initialized",
            }

        fast_inference = getattr(self, '_fast_inference', False)
        logger.info(f"Using RAG-based classifier for prediction (fast_inference={fast_inference})")
        return self._predict_with_rag_classifier(fast_inference=fast_inference)

    def _predict_with_rag_classifier(self, fast_inference: bool = False) -> Dict[str, Any]:
        """
        Predict activity using RAG-based classifier.

        Args:
            fast_inference: If True, use faster inference with simpler prompts

        Returns:
            dict: Prediction with activity, confidence, timestamp, and window data
        """
        try:
            # Convert window deque to list of dicts for classifier
            window_data = list(self.window)
            logger.info(f"Invoking RAG classifier with {len(window_data)} samples (fast_inference={fast_inference})")

            # Call classifier's predict_from_window method
            result = self.classifier.predict_from_window(window_data, fast_inference=fast_inference)

            logger.info(f"RAG prediction complete: {result['activity']}")

            return {
                "type": "activity_prediction",
                "activity": result["activity"],
                "reasoning": result.get("reasoning"),
                "fast_inference": fast_inference,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "window_size": len(self.window),
                "method": "rag_classifier",
                "window_data": window_data,  # Include window for logging
            }

        except Exception as e:
            logger.error(f"Error predicting with RAG classifier: {e}", exc_info=True)
            return {
                "type": "activity_prediction",
                "activity": "unknown",
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "error": str(e),
                "window_data": list(self.window),  # Include window even on error
            }

    def reset_window(self):
        """Clear the sliding window buffer."""
        self.window.clear()
        self.samples_received = 0
        logger.info("Sliding window reset")

    def reset_prediction_counter(self):
        """Reset the sample counter for step-based predictions."""
        self.samples_since_last_prediction = 0
        logger.info("Prediction counter reset")

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
