"""
RAG-HAR Pipeline Orchestrator
Coordinates the preprocessing, feature extraction, and indexing pipeline
for collected sensor data.
"""

import argparse
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


def run_rag_pipeline(force_recreate: bool = False, collection_name: str = None):
    """
    Run the complete RAG-HAR pipeline:
    1. Preprocess data (windowing and train/test split)
    2. Extract features (statistical descriptions)
    3. Index to vector database

    Data is expected to already be organized in subject folders:
    collected_data/subject0_20260104_153045/walking.csv, etc.

    Args:
        force_recreate: If True, drop and recreate the vector database collection
        collection_name: Optional collection name to use (defaults to har_demo_collection)

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
        num_indexed = timeseries_indexing.index_data(force_recreate=force_recreate, collection_name=collection_name)

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


def run_pipeline_async(force_recreate: bool = False, collection_name: str = None):
    """
    Run the RAG-HAR pipeline asynchronously in a separate thread.
    This allows the websocket server to continue handling connections
    while the pipeline runs.

    Args:
        force_recreate: If True, drop and recreate the vector database collection
        collection_name: Optional collection name to use (defaults to har_demo_collection)

    Returns:
        Thread object
    """
    import threading

    thread = threading.Thread(
        target=run_rag_pipeline,
        args=(force_recreate, collection_name),
        daemon=True
    )
    thread.start()
    logger.info(f"RAG-HAR pipeline started in background thread (collection: {collection_name or 'default'})")

    return thread


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description="Run the complete RAG-HAR pipeline (preprocess, extract features, index)"
    )
    parser.add_argument(
        "--force-recreate",
        action="store_true",
        help="Drop and recreate the vector database collection (clears all existing data)"
    )
    args = parser.parse_args()

    # Run pipeline directly
    result = run_rag_pipeline(force_recreate=args.force_recreate)
    if result['success']:
        logger.info("Pipeline completed successfully!")
    else:
        logger.error(f"Pipeline failed: {result['error']}")
