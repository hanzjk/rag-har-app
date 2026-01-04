"""
HAR Demo Feature Extraction
Extracts statistical features from preprocessed windows with temporal segmentation.
"""

import numpy as np
import pandas as pd
from pathlib import Path
from typing import Dict, List, Tuple
import logging
from tqdm import tqdm
from feature_utils import FeatureExtractorUtils

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# HAR Demo Configuration (hardcoded)
DATASET_NAME = "har_demo"
SENSOR_COLUMNS = ['accel', 'gyro']
STATISTICS = ['mean', 'std', 'min', 'max', 'median', 'p25', 'p75']
PER_AXIS = True

# Path to track processed sessions
BASE_PATH = Path(__file__).parent.parent
OUTPUT_BASE = BASE_PATH / "output" / DATASET_NAME


def get_processed_sessions(split_name: str) -> set:
    """
    Load the list of sessions that have already had features extracted for a specific split.

    Args:
        split_name: 'train' or 'test'

    Returns:
        Set of processed session folder names
    """
    processed_file = OUTPUT_BASE / f"processed_features_sessions_{split_name}.txt"

    if not processed_file.exists():
        return set()

    with open(processed_file, 'r') as f:
        return set(line.strip() for line in f if line.strip())


def mark_sessions_as_processed(session_folders: List[str], split_name: str):
    """
    Mark sessions as having features extracted for a specific split.

    Args:
        session_folders: List of session folder names
        split_name: 'train' or 'test'
    """
    processed_file = OUTPUT_BASE / f"processed_features_sessions_{split_name}.txt"
    processed_file.parent.mkdir(parents=True, exist_ok=True)

    with open(processed_file, 'a') as f:
        for session in session_folders:
            f.write(f"{session}\n")

    logger.info(f"Marked {len(session_folders)} sessions as feature-processed for {split_name} split")


def load_windows_from_csv(windows_dir: str, sessions_to_process: set = None) -> List[Dict]:
    """
    Load windows from organized CSV directory structure.
    Only loads windows from sessions in sessions_to_process (if provided).

    Expected structure: session_id/activity/session_id_window_0_activity.csv

    Args:
        windows_dir: Path to csv_windows directory
        sessions_to_process: Set of session IDs to process (None = all sessions)

    Returns:
        List of window dictionaries
    """
    windows_path = Path(windows_dir)
    windows = []

    # Walk through session/activity folders
    for session_dir in sorted(windows_path.iterdir()):
        if not session_dir.is_dir():
            continue

        session_id = session_dir.name

        # Skip if not in sessions_to_process
        if sessions_to_process is not None and session_id not in sessions_to_process:
            continue

        for activity_dir in sorted(session_dir.iterdir()):
            if not activity_dir.is_dir():
                continue

            activity = activity_dir.name

            # Load all CSV files in this activity folder
            for csv_file in sorted(activity_dir.glob("*.csv")):
                # Parse filename: subject0_20260104_153045_window_0_walking.csv
                filename = csv_file.stem
                parts = filename.split('_')

                # Extract window_id (it's after "window_")
                try:
                    window_idx = parts.index('window') + 1
                    window_id = int(parts[window_idx])
                except (ValueError, IndexError):
                    logger.warning(f"Could not parse window_id from {filename}, skipping")
                    continue

                # Load CSV data
                df = pd.read_csv(csv_file)

                windows.append({
                    'window_id': window_id,
                    'activity': activity,
                    'session_id': session_id,
                    'data': df
                })

    return windows


def extract_segmented_features(df: pd.DataFrame, activity: str) -> Tuple[np.ndarray, str]:
    """
    Extract features with temporal segmentation.

    Args:
        df: Window DataFrame
        activity: Activity label

    Returns:
        Tuple of (feature_vector, description_text)
    """
    utils = FeatureExtractorUtils()

    # Split into temporal segments
    segments = utils.split_temporal_segments(df)

    # Sensor metadata: (full_name, unit)
    sensor_metadata = {
        'accel': ('Acceleration', 'm/s²'),
        'gyro': ('Gyroscope', 'rad/s'),
    }

    # Segment name mapping
    segment_names = {
        'whole': 'Whole Segment',
        'start': 'Start Segment',
        'middle': 'Mid Segment',
        'end': 'End Segment'
    }

    all_features = []
    description_parts = []

    for segment_key in ['whole', 'start', 'middle', 'end']:
        segment_df = segments[segment_key]
        segment_name = segment_names[segment_key]
        description_parts.append(f"[{segment_name}]")
        segment_features = []

        # Process each sensor
        for prefix in SENSOR_COLUMNS:
            sensor_name, unit = sensor_metadata[prefix]
            axes = ['x', 'y', 'z']

            # Per-axis features
            if PER_AXIS:
                for axis_idx, axis in enumerate(axes, start=1):
                    col_name = f'{prefix}_{axis}'
                    if col_name in segment_df.columns:
                        stats_dict = utils.compute_stats(segment_df[col_name], STATISTICS)
                        segment_features.extend(stats_dict.values())

                        stats_str = ', '.join([f"{k}={v:.3f}" for k, v in stats_dict.items()])
                        description_parts.append(f"  {sensor_name} (axis {axis_idx}, {unit}): {stats_str}")

        all_features.extend(segment_features)
        description_parts.append("")  # Empty line after each segment

    description_text = "\n".join(description_parts)
    return np.array(all_features), description_text


def extract_features_for_split(split_name: str) -> Tuple[str, List[str]]:
    """
    Extract features for a specific split (train or test).
    Only processes NEW sessions that haven't been feature-extracted yet.

    Args:
        split_name: 'train' or 'test'

    Returns:
        Tuple of (path to descriptions directory, list of new session names processed)
    """
    logger.info(f"Extracting features for {split_name.upper()} set...")

    # Auto-generate paths
    base_path = Path(__file__).parent.parent
    windows_dir = base_path / "output" / DATASET_NAME / "train-test-splits" / split_name
    output_dir = base_path / "output" / DATASET_NAME / "features" / split_name

    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    # Get already processed sessions for this specific split
    processed_sessions = get_processed_sessions(split_name)

    # Find all session folders in this split
    windows_path = Path(windows_dir)
    all_sessions = set()
    if windows_path.exists():
        all_sessions = {d.name for d in windows_path.iterdir() if d.is_dir()}

    # Determine new sessions
    new_sessions = all_sessions - processed_sessions

    if not new_sessions:
        logger.info(f"All {len(all_sessions)} sessions in {split_name} split already have features extracted")
        descriptions_base_dir = output_path / 'descriptions'
        return str(descriptions_base_dir) if descriptions_base_dir.exists() else "", []

    logger.info(f"Found {len(all_sessions)} total sessions in {split_name} split")
    logger.info(f"Already feature-processed in {split_name}: {len(processed_sessions)} sessions")
    logger.info(f"New sessions to extract features in {split_name}: {len(new_sessions)}")
    for session in sorted(new_sessions):
        logger.info(f"  - {session}")

    # Load windows only from new sessions
    logger.info(f"Loading windows from {windows_dir} (new sessions only)")
    windows = load_windows_from_csv(str(windows_dir), sessions_to_process=new_sessions)

    if not windows:
        logger.warning(f"No windows found for new sessions in {split_name} split")
        descriptions_base_dir = output_path / 'descriptions'
        return str(descriptions_base_dir) if descriptions_base_dir.exists() else "", []

    logger.info(f"Loaded {len(windows)} windows from new sessions")

    # Process windows
    all_features = []
    descriptions_base_dir = output_path / 'descriptions'
    descriptions_base_dir.mkdir(exist_ok=True)

    for window in tqdm(windows, desc=f"Extracting {split_name} features"):
        window_id = window['window_id']
        activity = window['activity']
        session_id = window['session_id']
        df = window['data']

        # Extract features with temporal segmentation
        features, description = extract_segmented_features(df, activity)

        all_features.append({
            'window_id': window_id,
            'activity': activity,
            'session_id': session_id,
            'features': features
        })

        # Save description in session-based folder structure
        session_descriptions_dir = descriptions_base_dir / session_id
        session_descriptions_dir.mkdir(exist_ok=True)
        desc_file = session_descriptions_dir / f"{session_id}_window_{window_id}_activity_{activity}_stats.txt"
        with open(desc_file, 'w') as f:
            f.write(description)

    logger.info(f"Saved {len(all_features)} {split_name} descriptions to {descriptions_base_dir}")

    # Save summary (append mode for incremental updates)
    save_summary(all_features, output_path, split_name, new_sessions=list(new_sessions))

    # Mark sessions as feature-processed for this split
    mark_sessions_as_processed(list(new_sessions), split_name)

    return str(descriptions_base_dir), list(new_sessions)


def extract_features() -> Dict[str, str]:
    """
    Extract features from all windows (both train and test).
    Only processes NEW sessions that haven't been feature-extracted yet.

    Returns:
        Dict with paths to train and test descriptions directories
    """
    logger.info("=" * 60)
    logger.info("HAR Demo Feature Extraction")
    logger.info("=" * 60)
    logger.info("Sensors: accel_x/y/z, gyro_x/y/z")
    logger.info("Temporal segmentation: whole, start, mid, end")
    logger.info("")

    # Extract features for train split
    train_descriptions_dir, train_new_sessions = extract_features_for_split('train')

    # Extract features for test split
    test_descriptions_dir, test_new_sessions = extract_features_for_split('test')

    logger.info("")
    logger.info("=" * 60)
    logger.info("✓ Feature extraction complete!")
    logger.info(f"  Train descriptions: {train_descriptions_dir}")
    logger.info(f"  Test descriptions: {test_descriptions_dir}")
    logger.info(f"  New sessions processed: {len(set(train_new_sessions) | set(test_new_sessions))}")
    logger.info("=" * 60)

    return {
        'train': train_descriptions_dir,
        'test': test_descriptions_dir
    }


def save_summary(all_features: List[Dict], output_path: Path, split_name: str = '', new_sessions: List[str] = None):
    """
    Save feature extraction summary.
    Appends incremental batch info if new_sessions provided.

    Args:
        all_features: List of feature dictionaries
        output_path: Path to output directory
        split_name: 'train' or 'test'
        new_sessions: List of new session names processed (for append mode)
    """
    summary_file = output_path / 'feature_summary.txt'

    activity_counts = {}
    for item in all_features:
        activity = item['activity']
        activity_counts[activity] = activity_counts.get(activity, 0) + 1

    feature_dim = len(all_features[0]['features']) if all_features else 0

    # Use append mode if this is an incremental update
    mode = 'a' if summary_file.exists() and new_sessions else 'w'

    with open(summary_file, mode) as f:
        if mode == 'w':
            # First time - write header
            f.write(f"HAR Demo Feature Extraction Summary ({split_name})\n")
            f.write("="*40 + "\n\n")
        else:
            # Append mode - write batch header
            f.write(f"\n--- Feature Batch ({len(new_sessions)} new sessions) ---\n")
            f.write(f"Sessions processed: {', '.join(new_sessions)}\n\n")

        f.write(f"Total windows: {len(all_features)}\n")
        f.write(f"Feature dimension: {feature_dim}\n")
        f.write(f"Temporal segments: whole, start, mid, end\n")
        f.write(f"Sensors: {', '.join(SENSOR_COLUMNS)}\n\n")
        f.write("Windows per activity:\n")
        for activity, count in sorted(activity_counts.items()):
            f.write(f"  {activity}: {count}\n")
        f.write("\n")

    logger.info(f"{'Appended' if mode == 'a' else 'Saved'} {split_name} summary to {summary_file}")


if __name__ == '__main__':
    extract_features()
