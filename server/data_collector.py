"""
Data Collector Module
Handles collection and storage of sensor data to CSV files for dataset creation.
"""

import csv
import logging
from pathlib import Path
from datetime import datetime, timezone

logger = logging.getLogger(__name__)


class DataCollector:
    """Handles data collection and storage for dataset creation"""

    def __init__(self, data_dir: str = 'collected_data', subject_id: str = None):
        """
        Initialize data collector with subject-specific folder.

        Args:
            data_dir: Base directory for collected data
            subject_id: Subject identifier (defaults to 'subject0')
        """
        if subject_id is None:
            subject_id = 'subject0'

        # Create timestamped subject folder
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        subject_folder_name = f"{subject_id}_{timestamp}"

        self.data_dir = Path(data_dir) / subject_folder_name
        self.data_dir.mkdir(parents=True, exist_ok=True)

        self.subject_id = subject_id
        self.subject_folder_name = subject_folder_name
        self.csv_files = {}
        self.csv_writers = {}

        logger.info(f"Data collector initialized for subject: {subject_folder_name}")
        logger.info(f"Data directory: {self.data_dir}")

    def save_sensor_data(self, sensor_data: dict, activity_label: str = None) -> bool:
        """
        Save sensor data to CSV file organized by activity.

        Args:
            sensor_data: Dictionary containing sensor data
            activity_label: Optional activity label for the data

        Returns:
            bool: True if successful, False otherwise
        """
        try:
            # Use activity label from data or default to 'unlabeled'
            activity = activity_label or sensor_data.get('activity', 'unlabeled')

            # Create activity-specific file if it doesn't exist
            if activity not in self.csv_files:
                filename = self.data_dir / f"{activity}.csv"
                file_exists = filename.exists()

                # Open file in append mode
                self.csv_files[activity] = open(filename, 'a', newline='')

                # Create CSV writer
                fieldnames = [
                    'timestamp',
                    'accel_x', 'accel_y', 'accel_z',
                    'gyro_x', 'gyro_y', 'gyro_z',
                    'activity'
                ]
                self.csv_writers[activity] = csv.DictWriter(
                    self.csv_files[activity],
                    fieldnames=fieldnames
                )

                # Write header if new file
                if not file_exists:
                    self.csv_writers[activity].writeheader()
                    logger.info(f"Created new CSV file: {filename}")

            # Extract sensor values
            accel = sensor_data['data']['accelerometer']
            gyro = sensor_data['data']['gyroscope']

            # Write row
            row = {
                'timestamp': sensor_data.get('timestamp', datetime.now(timezone.utc).isoformat()),
                'accel_x': accel['x'],
                'accel_y': accel['y'],
                'accel_z': accel['z'],
                'gyro_x': gyro['x'],
                'gyro_y': gyro['y'],
                'gyro_z': gyro['z'],
                'activity': activity
            }

            self.csv_writers[activity].writerow(row)
            self.csv_files[activity].flush()  # Ensure data is written immediately

            return True
        except Exception as e:
            logger.error(f"Error saving sensor data: {e}")
            return False

    def get_stats(self) -> dict:
        """
        Get statistics about collected data.

        Returns:
            dict: Statistics including activities and file sizes
        """
        stats = {
            'activities': list(self.csv_files.keys()),
            'total_activities': len(self.csv_files),
            'data_dir': str(self.data_dir),
            'subject_id': self.subject_id,
            'subject_folder': self.subject_folder_name
        }
        return stats

    def get_subject_folder_name(self) -> str:
        """
        Get the subject folder name.

        Returns:
            str: Subject folder name (e.g., 'subject0_20260104_153045')
        """
        return self.subject_folder_name

    def close_all(self):
        """Close all open CSV files"""
        for activity, file in self.csv_files.items():
            file.close()
            logger.info(f"Closed CSV file for activity: {activity}")
        logger.info(f"All CSV files closed for subject: {self.subject_folder_name}")
