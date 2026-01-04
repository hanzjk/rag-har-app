"""
Test Data Logger Module
Logs prediction windows during testing sessions to timestamped CSV files.
Only logs when predictions are made (at step boundaries).
"""

import csv
import logging
from pathlib import Path
from datetime import datetime

logger = logging.getLogger(__name__)


class TestDataLogger:
    """Logs sliding window data and predictions during testing sessions"""

    def __init__(self, data_dir: str = 'test_data'):
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(exist_ok=True)

        # Store session ID for naming individual window files
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")

        # Define fieldnames (used when creating each window file)
        self.fieldnames = [
            'window_id',
            'sample_index_in_window',
            'timestamp',
            'accel_x', 'accel_y', 'accel_z',
            'gyro_x', 'gyro_y', 'gyro_z',
            'mag_x', 'mag_y', 'mag_z',
            'predicted_activity',
            'window_size'
        ]

        self.window_count = 0
        logger.info(f"Test data logger initialized. Session ID: {self.session_id}")

    def log_prediction_window(self, window_data: list, prediction: dict) -> bool:
        """
        Log the entire sliding window that was used for prediction.
        Creates a separate CSV file for each window.

        Args:
            window_data: List of sensor reading dicts (the sliding window)
            prediction: Prediction result from classifier

        Returns:
            bool: True if successful, False otherwise
        """
        try:
            predicted_activity = prediction.get('activity', 'unknown')
            window_size = len(window_data)

            # Create separate filename for this window
            filename = self.data_dir / f"test_window_{self.session_id}_w{self.window_count:03d}.csv"

            # Open new file and write this window's data
            with open(filename, 'w', newline='') as csv_file:
                csv_writer = csv.DictWriter(csv_file, fieldnames=self.fieldnames)
                csv_writer.writeheader()

                # Log each sample in the window
                for idx, sample in enumerate(window_data):
                    row = {
                        'window_id': self.window_count,
                        'sample_index_in_window': idx,
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
                        'predicted_activity': predicted_activity,
                        'window_size': window_size
                    }

                    csv_writer.writerow(row)

            self.window_count += 1
            logger.info(f"Logged prediction window #{self.window_count} to: {filename.name}")
            logger.info(f"  Window: {window_size} samples, Predicted: {predicted_activity}")

            return True
        except Exception as e:
            logger.error(f"Error logging prediction window: {e}")
            return False

    def get_stats(self) -> dict:
        """
        Get statistics about logged test data.

        Returns:
            dict: Statistics including window count and file path
        """
        return {
            'filename': str(self.filename),
            'windows_logged': self.window_count,
            'data_dir': str(self.data_dir)
        }

    def close(self):
        """Clean up logger resources"""
        logger.info(f"Test data logger closed. Total windows logged: {self.window_count}")
        logger.info(f"Session ID: {self.session_id}, Files saved to: {self.data_dir}")
