"""
RAG-HAR Pipeline Orchestrator
Coordinates the preprocessing, feature extraction, and indexing pipeline
for collected sensor data.
"""

import os
import sys
import logging
from pathlib import Path

# Add rag-har directory to Python path
rag_har_path = os.path.join(os.path.dirname(__file__), 'rag-har')
sys.path.insert(0, rag_har_path)

# Import rag-har modules
import preprocessing
import features
import timeseries_indexing

logger = logging.getLogger(__name__)


def run_rag_pipeline():
    """
    Run the complete RAG-HAR pipeline:
    1. Preprocess data (windowing and train/test split)
    2. Extract features (statistical descriptions)
    3. Index to vector database

    Data is expected to already be organized in subject folders:
    collected_data/subject0_20260104_153045/walking.csv, etc.

    Returns:
        Dict with pipeline results
    """
    logger.info("=" * 80)
    logger.info("STARTING RAG-HAR PIPELINE")
    logger.info("=" * 80)

    try:
        # Step 1: Preprocess
        logger.info("Step 1: Running preprocessing...")
        train_test_dir = preprocessing.preprocess()

        if not train_test_dir:
            raise Exception("Preprocessing failed - no data to process")

        # Step 2: Extract features
        logger.info("Step 2: Extracting features...")
        descriptions_dirs = features.extract_features()

        if not descriptions_dirs or not descriptions_dirs.get('train'):
            raise Exception("Feature extraction failed - no features generated")

        # Step 3: Index to vector database (train data only)
        logger.info("Step 3: Indexing to vector database...")
        num_indexed = timeseries_indexing.index_data(force_recreate=False)

        logger.info("=" * 80)
        logger.info("RAG-HAR PIPELINE COMPLETED SUCCESSFULLY")
        logger.info("=" * 80)
        logger.info(f"Windows indexed: {num_indexed}")
        logger.info(f"Train descriptions: {descriptions_dirs['train']}")
        logger.info(f"Test descriptions: {descriptions_dirs['test']}")
        logger.info("=" * 80)

        return {
            "success": True,
            "num_windows": num_indexed,
            "train_descriptions_dir": descriptions_dirs['train'],
            "test_descriptions_dir": descriptions_dirs['test']
        }

    except Exception as e:
        logger.error(f"RAG-HAR pipeline failed: {e}", exc_info=True)
        return {
            "success": False,
            "error": str(e)
        }


def run_pipeline_async():
    """
    Run the RAG-HAR pipeline asynchronously in a separate thread.
    This allows the websocket server to continue handling connections
    while the pipeline runs.

    Returns:
        Thread object
    """
    import threading

    thread = threading.Thread(
        target=run_rag_pipeline,
        daemon=True
    )
    thread.start()
    logger.info("RAG-HAR pipeline started in background thread")

    return thread


if __name__ == '__main__':
    # Run pipeline directly
    result = run_rag_pipeline()
    if result['success']:
        logger.info("Pipeline completed successfully!")
    else:
        logger.error(f"Pipeline failed: {result['error']}")
