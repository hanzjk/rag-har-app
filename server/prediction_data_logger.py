"""
Prediction Data Logger
Saves prediction windows to CSV files for debugging and analysis.
Controlled by SAVE_PREDICTION_WINDOWS environment variable.
"""

import csv
import os
import logging
from pathlib import Path
from datetime import datetime

logger = logging.getLogger(__name__)


class PredictionDataLogger:
    """Logs prediction windows when SAVE_PREDICTION_WINDOWS is enabled."""

    def __init__(self, data_dir: str = 'collected_data_predict_mode'):
        """
        Initialize prediction data logger.

        Args:
            data_dir: Base directory for saving prediction windows
        """
        # Check if logging is enabled via environment variable
        self.enabled = os.getenv('SAVE_PREDICTION_WINDOWS', 'false').lower() == 'true'

        if not self.enabled:
            logger.info("Prediction window logging is DISABLED (set SAVE_PREDICTION_WINDOWS=true to enable)")
            return

        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(exist_ok=True)

        # Create session folder with timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.session_folder = self.data_dir / f"session_{timestamp}"
        self.session_folder.mkdir(exist_ok=True)

        self.window_count = 0

        logger.info(f"✓ Prediction window logging ENABLED")
        logger.info(f"  Saving to: {self.session_folder}")

    def log_prediction_window(self, window_data: list, prediction: dict) -> bool:
        """
        Save prediction window to CSV file.

        Args:
            window_data: List of sensor reading dicts (the 200-sample window)
            prediction: Prediction result with activity label

        Returns:
            True if saved successfully, False otherwise
        """
        if not self.enabled:
            return False

        try:
            predicted_activity = prediction.get('activity', 'unknown')
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")[:-3]  # milliseconds

            # Filename: timestamp_window_N_activity.csv
            filename = self.session_folder / f"{timestamp}_window_{self.window_count:04d}_{predicted_activity}.csv"

            # CSV fieldnames
            fieldnames = [
                'sample_index',
                'timestamp',
                'accel_x', 'accel_y', 'accel_z',
                'gyro_x', 'gyro_y', 'gyro_z',
                'mag_x', 'mag_y', 'mag_z',
                'predicted_activity'
            ]

            # Write window to CSV
            with open(filename, 'w', newline='') as csv_file:
                writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
                writer.writeheader()

                for idx, sample in enumerate(window_data):
                    row = {
                        'sample_index': idx,
                        'timestamp': sample.get('timestamp', ''),
                        'accel_x': sample['accel_x'],
                        'accel_y': sample['accel_y'],
                        'accel_z': sample['accel_z'],
                        'gyro_x': sample['gyro_x'],
                        'gyro_y': sample['gyro_y'],
                        'gyro_z': sample['gyro_z'],
                        'mag_x': sample['mag_x'],
                        'mag_y': sample['mag_y'],
                        'mag_z': sample['mag_z'],
                        'predicted_activity': predicted_activity
                    }
                    writer.writerow(row)

            self.window_count += 1

            if self.window_count % 10 == 0:  # Log every 10 windows
                logger.info(f"Saved {self.window_count} prediction windows to {self.session_folder.name}")

            return True

        except Exception as e:
            logger.error(f"Error saving prediction window: {e}")
            return False

    def close(self):
        """Clean up and log summary."""
        if self.enabled and self.window_count > 0:
            logger.info(f"Prediction logger closed. Total windows saved: {self.window_count}")
            logger.info(f"Location: {self.session_folder}")
