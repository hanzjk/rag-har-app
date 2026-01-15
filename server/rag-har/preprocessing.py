"""
HAR Demo Dataset Preprocessing
Handles CSV files from server/collected_data/

Preprocessing for HAR Demo:
- Session-based tracking (each subject_timestamp folder is a unique session)
- No normalization (raw sensor values preserved for RAG/LLM classification)
- Fixed window size: 200 samples (4 seconds at 50Hz)
- 50% overlap (100 sample step)
- No filtering needed (high-quality mobile sensor data)
"""

from pathlib import Path
from typing import Dict, List, Tuple
import pandas as pd
import logging
import random

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# HAR Demo Configuration (hardcoded)
DATASET_NAME = "har_demo"
BASE_PATH = Path(__file__).parent.parent / "collected_data"
OUTPUT_BASE = Path(__file__).parent.parent / "output" / DATASET_NAME
ACTIVITIES = ["walking", "sitting", "standing", "jumping", "lying_down", "running"]
WINDOW_SIZE = 200  # 4 seconds at 50Hz
STEP_SIZE = 100    # 50% overlap
TEST_RATIO = 0.3   # 10% test data
PROCESSED_SESSIONS_FILE = OUTPUT_BASE / "processed_sessions.txt"


def get_processed_sessions() -> set:
    """
    Load the list of already processed sessions.

    Returns:
        Set of processed session folder names (e.g., 'subject0_20260104_153045')
    """
    if not PROCESSED_SESSIONS_FILE.exists():
        return set()

    with open(PROCESSED_SESSIONS_FILE, 'r') as f:
        return set(line.strip() for line in f if line.strip())


def mark_sessions_as_processed(session_folders: List[str]):
    """
    Mark sessions as processed by adding them to the processed sessions file.

    Args:
        session_folders: List of session folder names
    """
    PROCESSED_SESSIONS_FILE.parent.mkdir(parents=True, exist_ok=True)

    with open(PROCESSED_SESSIONS_FILE, 'a') as f:
        for session in session_folders:
            f.write(f"{session}\n")

    logger.info(f"Marked {len(session_folders)} sessions as processed")


def load_raw_data() -> Tuple[Dict[str, pd.DataFrame], List[str]]:
    """
    Load raw CSV data from collected_data directory.
    Only loads NEW sessions that haven't been processed yet.
    Handles session-based folder structure: collected_data/subject0_20260104_153045/walking.csv

    Returns:
        Tuple of (data dict mapping activity to DataFrames, list of new session folder names)
    """
    base_path = BASE_PATH

    # Find all session folders (subject_timestamp pattern)
    all_session_folders = [f for f in base_path.iterdir() if f.is_dir() and f.name.startswith('subject')]

    if not all_session_folders:
        logger.warning(f"No session folders found in {base_path}")
        return {}, []

    # Get already processed sessions
    processed_sessions = get_processed_sessions()

    # Filter to only new sessions
    new_session_folders = [f for f in all_session_folders if f.name not in processed_sessions]

    if not new_session_folders:
        logger.info(f"All {len(all_session_folders)} sessions have already been processed")
        return {}, []

    logger.info(f"Found {len(all_session_folders)} total sessions")
    logger.info(f"Already processed: {len(processed_sessions)} sessions")
    logger.info(f"New sessions to process: {len(new_session_folders)}")
    for folder in new_session_folders:
        logger.info(f"  - {folder.name}")

    # Collect data by activity, keeping session info
    data = {activity: [] for activity in ACTIVITIES}

    for session_folder in new_session_folders:
        session_name = session_folder.name
        logger.info(f"Loading data from {session_name}...")

        for activity in ACTIVITIES:
            activity_file = session_folder / f"{activity}.csv"

            if activity_file.exists():
                df = pd.read_csv(activity_file)

                # Omit first and last 8 seconds (400 samples at 50Hz)
                # This removes setup/transition artifacts at activity boundaries
                samples_to_omit = 400
                if len(df) > 2 * samples_to_omit:
                    df = df.iloc[samples_to_omit:-samples_to_omit].reset_index(drop=True)
                    logger.info(f"  {session_name}/{activity}.csv: {len(df)} samples (after omitting first/last 8s)")
                else:
                    logger.warning(f"  {session_name}/{activity}.csv: {len(df)} samples - too short to omit edges, skipping file")
                    continue

                # Add session identifier column
                df['session_id'] = session_name
                data[activity].append(df)
            else:
                logger.debug(f"  {session_name}/{activity}.csv: not found")

    # Combine data from all sessions for each activity
    combined_data = {}
    for activity, dfs in data.items():
        if dfs:
            combined_df = pd.concat(dfs, ignore_index=True)
            combined_data[activity] = combined_df
            logger.info(f"Combined {activity}: {len(combined_df)} samples from {len(dfs)} sessions")
        else:
            logger.debug(f"No data found for activity: {activity}")

    new_session_names = [f.name for f in new_session_folders]
    return combined_data, new_session_names


def segment_windows(data: Dict[str, pd.DataFrame]) -> List[Dict]:
    """Segment data into 200-sample windows with 50% overlap, maintaining session structure."""
    windows = []

    for activity, df in data.items():
        # Group by session to create windows per session
        sessions = df['session_id'].unique()

        for session_id in sessions:
            session_df = df[df['session_id'] == session_id].reset_index(drop=True)
            num_windows = (len(session_df) - WINDOW_SIZE) // STEP_SIZE + 1
            window_id = 0

            for i in range(num_windows):
                start_idx = i * STEP_SIZE
                end_idx = start_idx + WINDOW_SIZE

                if end_idx > len(session_df):
                    break

                window_data = session_df.iloc[start_idx:end_idx].copy()

                windows.append({
                    'window_id': window_id,
                    'activity': activity,
                    'session_id': session_id,
                    'data': window_data,
                    'start_index': start_idx,
                    'end_index': end_idx,
                    'num_samples': len(window_data)
                })

                window_id += 1

            logger.info(f"  {session_id}/{activity}: {num_windows} windows")

    return windows


def split_train_test(windows: List[Dict]) -> Tuple[List[Dict], List[Dict]]:
    """
    Split windows into train and test sets.
    Takes 10% from each activity for testing.
    """
    # Group windows by activity
    windows_by_activity = {}
    for window in windows:
        activity = window['activity']
        if activity not in windows_by_activity:
            windows_by_activity[activity] = []
        windows_by_activity[activity].append(window)

    train_windows = []
    test_windows = []

    # Split each activity
    for activity, activity_windows in windows_by_activity.items():
        # Shuffle to ensure random split
        random.shuffle(activity_windows)

        # Calculate split point
        n_test = max(1, int(len(activity_windows) * TEST_RATIO))
        n_train = len(activity_windows) - n_test

        # Split
        train_windows.extend(activity_windows[:n_train])
        test_windows.extend(activity_windows[n_train:])

        logger.info(f"  {activity}: {n_train} train, {n_test} test")

    return train_windows, test_windows


def save_windows(windows: List[Dict], output_path: Path, split_name: str) -> Path:
    """
    Save windows as CSV files maintaining session structure.
    CSV structure: train/session_id/activity/session_id_window_0_activity.csv
    """
    split_dir = output_path / split_name
    split_dir.mkdir(exist_ok=True)

    for window in windows:
        session_id = window['session_id']
        activity = window['activity']
        window_id = window['window_id']

        # Create session/activity folder structure
        activity_dir = split_dir / session_id / activity
        activity_dir.mkdir(parents=True, exist_ok=True)

        # Filename includes session_id
        csv_file = activity_dir / f"{session_id}_window_{window_id}_{activity}.csv"
        window['data'].to_csv(csv_file, index=False)

    logger.info(f"  Saved {len(windows)} {split_name} CSV files to {split_dir}")

    return split_dir


def save_summary(train_windows: List[Dict], test_windows: List[Dict], output_path: Path, new_sessions: List[str]):
    """Save preprocessing summary with train/test split information."""
    summary_file = output_path / 'preprocessing_summary.txt'

    # Count activities for train
    train_activity_counts = {}
    for window in train_windows:
        activity = window['activity']
        train_activity_counts[activity] = train_activity_counts.get(activity, 0) + 1

    # Count activities for test
    test_activity_counts = {}
    for window in test_windows:
        activity = window['activity']
        test_activity_counts[activity] = test_activity_counts.get(activity, 0) + 1

    # Count sessions
    train_sessions = set(w['session_id'] for w in train_windows)
    test_sessions = set(w['session_id'] for w in test_windows)

    mode = 'a' if summary_file.exists() else 'w'
    with open(summary_file, mode) as f:
        if mode == 'w':
            f.write("HAR Demo Preprocessing Summary\n")
            f.write("="*40 + "\n\n")

        f.write(f"\n--- Session Batch ({len(new_sessions)} new sessions) ---\n")
        f.write(f"Sessions processed: {', '.join(new_sessions)}\n\n")
        f.write(f"Total windows: {len(train_windows) + len(test_windows)}\n")
        f.write(f"Train windows: {len(train_windows)} (from {len(train_sessions)} sessions)\n")
        f.write(f"Test windows: {len(test_windows)} (from {len(test_sessions)} sessions)\n")
        f.write(f"Test ratio: 10%\n\n")
        f.write(f"Window size: {WINDOW_SIZE} samples (4 seconds)\n")
        f.write(f"Step size: {STEP_SIZE} samples (50% overlap)\n")
        f.write(f"Sampling rate: 50 Hz\n")
        f.write(f"Normalization: None (raw sensor values)\n\n")

        f.write("Train windows per activity:\n")
        for activity, count in sorted(train_activity_counts.items()):
            f.write(f"  {activity}: {count}\n")

        f.write("\nTest windows per activity:\n")
        for activity, count in sorted(test_activity_counts.items()):
            f.write(f"  {activity}: {count}\n")
        f.write("\n")

    logger.info(f"  Appended summary to {summary_file}")


def preprocess() -> str:
    """
    Run HAR Demo preprocessing pipeline.
    Only processes NEW sessions that haven't been processed before.

    Returns:
        Path to train-test-splits directory
    """
    logger.info("="*60)
    logger.info("HAR DEMO PREPROCESSING")
    logger.info("="*60)
    logger.info("Dataset: Clean mobile sensor data")
    logger.info("Sensors: Accelerometer, Gyroscope (50Hz)")
    logger.info("Normalization: None (raw sensor values preserved)")
    logger.info(f"Window size: {WINDOW_SIZE} samples (4 seconds)")
    logger.info(f"Overlap: 50% ({STEP_SIZE} sample step)")
    logger.info("")

    output_path = OUTPUT_BASE
    output_path.mkdir(parents=True, exist_ok=True)

    # Step 1: Load data (only new sessions)
    logger.info("Step 1: Loading raw data (new sessions only)...")
    data, new_session_names = load_raw_data()

    if not data or not new_session_names:
        logger.warning("No new sessions to preprocess")
        # Return existing path even if no new data
        train_test_dir = output_path / 'train-test-splits'
        return str(train_test_dir) if train_test_dir.exists() else ""

    # Step 2: Segment into windows
    logger.info("Step 2: Segmenting into windows...")
    windows = segment_windows(data)

    # Step 3: Train/Test split
    logger.info("Step 3: Splitting train/test (10% test per activity)...")
    train_windows, test_windows = split_train_test(windows)

    # Step 4: Save windows
    logger.info("Step 4: Saving windows...")
    train_test_dir = output_path / 'train-test-splits'
    train_test_dir.mkdir(exist_ok=True)

    save_windows(train_windows, train_test_dir, split_name='train')
    save_windows(test_windows, train_test_dir, split_name='test')

    # Save summary
    save_summary(train_windows, test_windows, output_path, new_session_names)

    # Mark sessions as processed
    mark_sessions_as_processed(new_session_names)

    logger.info("")
    logger.info(f"✓ Train: {len(train_windows)} windows")
    logger.info(f"✓ Test: {len(test_windows)} windows")
    logger.info(f"✓ Output: {train_test_dir}")

    return str(train_test_dir)


if __name__ == '__main__':
    preprocess()
