"""
Time Series Indexing for HAR Demo
Creates embeddings and indexes time series data to Milvus vector database.
Supports both creating new collections and adding data to existing ones.
"""

import argparse
import glob
import os
import re
import concurrent.futures
import time
import logging
from pathlib import Path
from typing import Dict, List

from tqdm import tqdm
from langchain_openai import OpenAIEmbeddings
from pymilvus import MilvusClient, DataType
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Suppress httpx logs
logging.getLogger("httpx").setLevel(logging.WARNING)

# HAR Demo Configuration (hardcoded)
DATASET_NAME = "har_demo"
COLLECTION_NAME = f"{DATASET_NAME}_collection"

# Path to track indexed sessions
BASE_PATH = Path(__file__).parent.parent
OUTPUT_BASE = BASE_PATH / "output" / DATASET_NAME
PROCESSED_INDEXING_FILE = OUTPUT_BASE / "processed_indexing_sessions.txt"

# gRPC limits
GRPC_TARGET = 38 * 1024 * 1024  # stay under ~48 MiB per RPC
MAX_ROWS = 500  # secondary guard


def get_indexed_sessions() -> set:
    """
    Load the list of sessions that have already been indexed to Milvus.

    Returns:
        Set of indexed session folder names
    """
    if not PROCESSED_INDEXING_FILE.exists():
        return set()

    with open(PROCESSED_INDEXING_FILE, 'r') as f:
        return set(line.strip() for line in f if line.strip())


def mark_sessions_as_indexed(session_folders: List[str]):
    """
    Mark sessions as indexed to Milvus.

    Args:
        session_folders: List of session folder names
    """
    PROCESSED_INDEXING_FILE.parent.mkdir(parents=True, exist_ok=True)

    with open(PROCESSED_INDEXING_FILE, 'a') as f:
        for session in session_folders:
            f.write(f"{session}\n")

    logger.info(f"Marked {len(session_folders)} sessions as indexed")


def _utf8_len(x):
    """Calculate UTF-8 length of a value."""
    if x is None:
        return 0
    if isinstance(x, (bytes, bytearray)):
        return len(x)
    if isinstance(x, str):
        return len(x.encode("utf-8"))
    return len(str(x).encode("utf-8"))


def _estimate_row_bytes(row: dict) -> int:
    """Estimate the size of a row in bytes for gRPC budgeting."""
    # 4 vectors * 1536 * 4 bytes
    vec_bytes = (
        sum(
            (
                len(row.get(k) or [])
                for k in (
                    "activity_stats_emb",
                    "activity_stats_start_emb",
                    "activity_stats_mid_emb",
                    "activity_stats_end_emb",
                )
            )
        )
        * 4
    )
    str_bytes = sum(
        _utf8_len(row.get(k))
        for k in (
            "text",
            "timeseries_metadata",
            "stats_whole_text",
            "stats_start_text",
            "stats_mid_text",
            "stats_end_text",
        )
    )
    return vec_bytes + str_bytes + 256  # small overhead


def init_milvus_client():
    """Initialize Milvus client with environment credentials."""
    client = MilvusClient(
        uri=os.environ.get("ZILLIZ_CLOUD_URI"),
        token=os.environ.get("ZILLIZ_CLOUD_API_KEY"),
        grpc_channel_options=[
            ("grpc.max_send_message_length", 128 * 1024 * 1024),
            ("grpc.max_receive_message_length", 128 * 1024 * 1024),
        ],
    )
    logger.info("Milvus client initialized.")
    return client


def init_embeddings():
    """Initialize OpenAI embeddings model."""
    return OpenAIEmbeddings(
        model="text-embedding-3-small",
        api_key=os.environ.get("OPENAI_API_KEY")
    )


def create_collection(milvus_client: MilvusClient) -> bool:
    """
    Create Milvus collection if it doesn't exist.

    Returns:
        True if collection was created, False if it already existed
    """
    collections = milvus_client.list_collections()

    if COLLECTION_NAME in collections:
        logger.info(f"Collection {COLLECTION_NAME} already exists")
        return False

    schema = MilvusClient.create_schema(
        auto_id=False,
        enable_dynamic_field=False,
    )
    schema.add_field(
        field_name="text",
        datatype=DataType.VARCHAR,
        is_primary=True,
        max_length=100,  # Increased to accommodate session_id_w0_activity format
    )
    schema.add_field(
        field_name="timeseries_metadata",
        datatype=DataType.JSON,
        max_length=10000,
    )
    schema.add_field(
        field_name="stats_whole_text",
        datatype=DataType.VARCHAR,
        max_length=10000,
    )
    schema.add_field(
        field_name="stats_start_text",
        datatype=DataType.VARCHAR,
        max_length=10000,
    )
    schema.add_field(
        field_name="stats_mid_text",
        datatype=DataType.VARCHAR,
        max_length=10000
    )
    schema.add_field(
        field_name="stats_end_text",
        datatype=DataType.VARCHAR,
        max_length=10000
    )
    schema.add_field(
        field_name="activity_stats_emb",
        datatype=DataType.FLOAT_VECTOR,
        dim=1536,
    )
    schema.add_field(
        field_name="activity_stats_start_emb",
        datatype=DataType.FLOAT_VECTOR,
        dim=1536,
    )
    schema.add_field(
        field_name="activity_stats_mid_emb",
        datatype=DataType.FLOAT_VECTOR,
        dim=1536,
    )
    schema.add_field(
        field_name="activity_stats_end_emb",
        datatype=DataType.FLOAT_VECTOR,
        dim=1536,
    )

    index_params = milvus_client.prepare_index_params()
    index_params.add_index(
        field_name="activity_stats_emb",
        index_type="AUTOINDEX",
        metric_type="COSINE",
    )
    index_params.add_index(
        field_name="activity_stats_start_emb",
        index_type="AUTOINDEX",
        metric_type="COSINE",
    )
    index_params.add_index(
        field_name="activity_stats_mid_emb",
        index_type="AUTOINDEX",
        metric_type="COSINE",
    )
    index_params.add_index(
        field_name="activity_stats_end_emb",
        index_type="AUTOINDEX",
        metric_type="COSINE",
    )

    milvus_client.create_collection(
        collection_name=COLLECTION_NAME,
        metric_type="COSINE",
        schema=schema,
        index_params=index_params,
    )
    logger.info(f"Created collection: {COLLECTION_NAME}")
    return True


def embed_with_retry(embed_model, text: str, max_retries: int = 3) -> List[float]:
    """Embed a single text with retry logic for connection errors."""
    for attempt in range(max_retries):
        try:
            return embed_model.embed_query(str(text))
        except Exception as e:
            if attempt == max_retries - 1:  # Last attempt
                raise e
            time.sleep(60)  # Simple 60 second delay between retries


def embed_batch(embed_model, texts_batch):
    """Process a batch of texts to embed."""
    results = []
    for text in texts_batch:
        results.append(embed_with_retry(embed_model, text))
    return results


def parallel_embed(embed_model, texts_list, max_workers=10, batch_size=20):
    """Embed a list of texts in parallel using concurrent.futures while maintaining order."""
    batches = [
        texts_list[i : i + batch_size]
        for i in range(0, len(texts_list), batch_size)
    ]
    results = [None] * len(batches)  # Pre-allocate results array to maintain order

    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Submit all batches and store future-to-index mapping
        future_to_index = {
            executor.submit(embed_batch, embed_model, batch): i
            for i, batch in enumerate(batches)
        }

        # Process results while maintaining order
        for future in tqdm(
            concurrent.futures.as_completed(future_to_index),
            total=len(batches),
            desc="Embedding batches",
        ):
            batch_index = future_to_index[future]
            try:
                batch_results = future.result()
                results[batch_index] = batch_results  # Store in correct position
            except Exception as e:
                logger.error(f"Error processing batch {batch_index}: {e}")
                # Add None results to maintain order
                results[batch_index] = [None] * len(batches[batch_index])

    # Flatten results while maintaining order
    flattened_results = []
    for batch_result in results:
        if batch_result is not None:
            flattened_results.extend(batch_result)
        else:
            flattened_results.extend([None] * batch_size)  # Maintain length

    return flattened_results


def extract_sensor_sections(text):
    """
    Given the file content as a string, extract each sensor section for all segments.
    Returns a dict with structure:
    {
        'whole': {content for whole segment},
        'start': {content for start segment},
        'mid': {content for mid segment},
        'end': {content for end segment}
    }
    """
    segments = {"whole": "", "start": "", "mid": "", "end": ""}

    # Split text by segment headers
    segment_pattern = r"\[(Whole|Start|Mid|End) Segment\](.*?)(?=\[(?:Whole|Start|Mid|End) Segment\]|$)"
    segment_matches = re.findall(segment_pattern, text, re.DOTALL)

    for segment_name, segment_content in segment_matches:
        segments[segment_name.lower()] = segment_content.strip()

    return segments


def extract_and_embed_data(embed_model, descriptions_dir: str, sessions_to_index: set = None) -> List[Dict]:
    """
    Extract multivariate time series data and create embeddings.
    Only processes files from sessions in sessions_to_index (if provided).

    Args:
        embed_model: OpenAI embeddings model
        descriptions_dir: Directory containing session-based description folders
        sessions_to_index: Set of session IDs to index (None = all sessions)

    Returns:
        List of data dictionaries with embeddings
    """
    logger.info(f"Extracting and processing {DATASET_NAME} time series data...")

    # Prepare data for embedding
    stats_to_embed = []
    start_stats_to_embed = []
    mid_stats_to_embed = []
    end_stats_to_embed = []
    metadata_list = []

    logger.info(f"Processing {DATASET_NAME} time series for embedding...")

    descriptions_path = Path(descriptions_dir)

    # Iterate over session folders
    file_list = []
    if descriptions_path.exists():
        for session_dir in descriptions_path.iterdir():
            if not session_dir.is_dir():
                continue

            session_id = session_dir.name

            # Skip if not in sessions_to_index
            if sessions_to_index is not None and session_id not in sessions_to_index:
                continue

            # Collect all .txt files from this session folder
            session_files = list(session_dir.glob("*.txt"))
            file_list.extend(session_files)

    if not file_list:
        logger.warning(f"No description files found in {descriptions_dir}")
        return []

    logger.info(f"Found {len(file_list)} description files to process")

    for file_path in file_list:
        try:
            base = os.path.basename(file_path)
            # Filename pattern: session_id_window_0_activity_walking_stats.txt
            m = re.match(r"(.+)_window_(\d+)_activity_([A-Za-z0-9_-]+)_stats\.txt", base)
            if not m:
                logger.warning(f"Filename not matched: {base}")
                continue
            session_id, window_id, activity_id = m.groups()

            with open(file_path, "r") as f:
                content = f.read()

            # Extract sensor sections
            logger.debug(
                f"Extracting stat descriptions for session:{session_id} window:{window_id} activity:{activity_id}"
            )
            sensors = extract_sensor_sections(content)
            stats_to_embed.append(sensors["whole"])
            start_stats_to_embed.append(sensors["start"])
            mid_stats_to_embed.append(sensors["mid"])
            end_stats_to_embed.append(sensors["end"])

            metadata_list.append(
                {
                    "dataset": DATASET_NAME,
                    "session_id": session_id,
                    "window_id": window_id,
                    "activity_id": activity_id,
                    "stats_whole_text": sensors["whole"],
                    "stats_start_text": sensors["start"],
                    "stats_mid_text": sensors["mid"],
                    "stats_end_text": sensors["end"],
                }
            )
        except Exception as e:
            logger.error(f"Error processing file {file_path}: {e}")
            continue

    if not metadata_list:
        logger.warning("No valid data extracted from description files")
        return []

    # Process embeddings in parallel
    logger.info(f"Creating embeddings for {len(metadata_list)} time series...")
    stats_embedded_values = parallel_embed(
        embed_model, stats_to_embed, max_workers=10, batch_size=20
    )
    start_stats_embedded_values = parallel_embed(
        embed_model, start_stats_to_embed, max_workers=10, batch_size=20
    )
    mid_stats_embedded_values = parallel_embed(
        embed_model, mid_stats_to_embed, max_workers=10, batch_size=20
    )
    end_stats_embedded_values = parallel_embed(
        embed_model, end_stats_to_embed, max_workers=10, batch_size=20
    )

    # Create the final data list with proper metadata-embedding association
    data_list = []
    for i, metadata in enumerate(metadata_list):
        # Include session_id in primary key to prevent duplicates
        text_id = f"{metadata['session_id']}_w{metadata['window_id']}_{metadata['activity_id']}"
        data_list.append(
            {
                "text": text_id,
                "text_id": text_id,
                "stats_whole_text": metadata["stats_whole_text"],
                "stats_start_text": metadata["stats_start_text"],
                "stats_mid_text": metadata["stats_mid_text"],
                "stats_end_text": metadata["stats_end_text"],
                "activity_stats_emb": stats_embedded_values[i],
                "activity_stats_start_emb": start_stats_embedded_values[i],
                "activity_stats_mid_emb": mid_stats_embedded_values[i],
                "activity_stats_end_emb": end_stats_embedded_values[i],
                "dataset": metadata["dataset"],
                "session_id": metadata["session_id"],
                "window_id": metadata["window_id"],
                "activity_id": metadata["activity_id"],
            }
        )

    logger.info(
        f"Successfully processed {len(data_list)} time series data points"
    )

    return data_list


def prepare_data_for_milvus(data_list: List[Dict]) -> List[Dict]:
    """Convert data list to format expected by Milvus."""
    milvus_data = []
    for d in data_list:
        milvus_data.append(
            {
                "text": d["text_id"],
                "timeseries_metadata": {
                    "dataset": d["dataset"],
                    "session_id": d["session_id"],
                    "window_id": d["window_id"],
                    "activity_id": d["activity_id"],
                },
                "stats_whole_text": d.get("stats_whole_text", ""),
                "stats_start_text": d.get("stats_start_text", ""),
                "stats_mid_text": d.get("stats_mid_text", ""),
                "stats_end_text": d.get("stats_end_text", ""),
                "activity_stats_emb": d["activity_stats_emb"],
                "activity_stats_start_emb": d["activity_stats_start_emb"],
                "activity_stats_mid_emb": d["activity_stats_mid_emb"],
                "activity_stats_end_emb": d["activity_stats_end_emb"],
            }
        )
    return milvus_data


def insert_data_to_milvus(milvus_client: MilvusClient, rows: List[Dict]):
    """Insert data into Milvus collection with batching for large payloads."""
    if not rows:
        logger.warning("No data to insert into Milvus")
        return

    total, batch, batch_bytes = 0, [], 0
    try:
        for r in rows:
            sz = _estimate_row_bytes(r)

            # flush if this row would push us over the target or max rows
            if batch and (batch_bytes + sz > GRPC_TARGET or len(batch) >= MAX_ROWS):
                milvus_client.insert(
                    collection_name=COLLECTION_NAME, data=batch
                )
                total += len(batch)
                logger.info(f"Inserted {len(batch)} docs (Total: {total})")
                batch, batch_bytes = [], 0

            # if one row itself is big, send it alone
            if sz > GRPC_TARGET and not batch:
                milvus_client.insert(
                    collection_name=COLLECTION_NAME, data=[r]
                )
                total += 1
                logger.info(f"Inserted 1 large doc (Total: {total})")
            else:
                batch.append(r)
                batch_bytes += sz

        if batch:
            milvus_client.insert(
                collection_name=COLLECTION_NAME, data=batch
            )
            total += len(batch)
            logger.info(f"Inserted {len(batch)} docs (Total: {total})")

        logger.info(
            f"Successfully inserted {total} documents into collection: {COLLECTION_NAME}"
        )
    except Exception as e:
        logger.error(f"Error inserting documents into Milvus: {e}")
        raise


def index_data(force_recreate: bool = False) -> int:
    """
    Main function to index time series data to Milvus.
    Only indexes NEW sessions that haven't been indexed yet.

    Args:
        force_recreate: If True, drop and recreate the collection (clears tracking file)

    Returns:
        Number of documents indexed
    """
    # Auto-generate descriptions directory path
    base_path = Path(__file__).parent.parent
    descriptions_dir = base_path / "output" / DATASET_NAME / "features" / "train" / "descriptions"

    logger.info("=" * 80)
    logger.info("TIME SERIES INDEXING")
    logger.info("=" * 80)
    logger.info(f"Dataset: {DATASET_NAME}")
    logger.info(f"Descriptions directory: {descriptions_dir}")
    logger.info(f"Force recreate: {force_recreate}")
    logger.info("=" * 80)
    logger.info("")

    # Initialize clients
    milvus_client = init_milvus_client()
    embed_model = init_embeddings()

    # Handle force recreate
    if force_recreate and COLLECTION_NAME in milvus_client.list_collections():
        logger.warning(f"Dropping existing collection: {COLLECTION_NAME}")
        milvus_client.drop_collection(COLLECTION_NAME)
        # Clear tracking file when recreating collection
        if PROCESSED_INDEXING_FILE.exists():
            logger.warning(f"Clearing indexing tracking file")
            PROCESSED_INDEXING_FILE.unlink()

    # Create collection if it doesn't exist
    created = create_collection(milvus_client)
    if created:
        logger.info("New collection created - will index all data")
    else:
        logger.info("Collection exists - will add new data only")

    # Get already indexed sessions
    indexed_sessions = get_indexed_sessions()

    # Find all session folders in descriptions directory
    all_sessions = set()
    if descriptions_dir.exists():
        for session_dir in descriptions_dir.iterdir():
            if session_dir.is_dir():
                all_sessions.add(session_dir.name)

    # Determine new sessions to index
    new_sessions = all_sessions - indexed_sessions

    if not new_sessions:
        logger.info(f"All {len(all_sessions)} sessions already indexed to Milvus")
        logger.info("No new data to index")
        return 0

    logger.info(f"Found {len(all_sessions)} total session folders in descriptions")
    logger.info(f"Already indexed: {len(indexed_sessions)} sessions")
    logger.info(f"New sessions to index: {len(new_sessions)}")
    for session in sorted(new_sessions):
        logger.info(f"  - {session}")

    # Extract and embed data (only for new sessions)
    data_list = extract_and_embed_data(embed_model, str(descriptions_dir), sessions_to_index=new_sessions)

    if not data_list:
        logger.warning("No data to index")
        return 0

    # Prepare for Milvus
    milvus_data = prepare_data_for_milvus(data_list)

    # Insert into Milvus
    insert_data_to_milvus(milvus_client, milvus_data)

    # Mark sessions as indexed
    mark_sessions_as_indexed(list(new_sessions))

    logger.info("")
    logger.info("=" * 80)
    logger.info(f"✓ Indexing complete!")
    logger.info(f"✓ {len(data_list)} time series documents indexed")
    logger.info(f"✓ {len(new_sessions)} new sessions added to Milvus")
    logger.info(f"✓ Collection: {COLLECTION_NAME}")
    logger.info("=" * 80)

    return len(data_list)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Index HAR time series data to Milvus vector database"
    )
    parser.add_argument(
        "--force-recreate",
        action="store_true",
        help="Drop and recreate the collection (clears all existing data and tracking file)"
    )
    args = parser.parse_args()

    index_data(force_recreate=args.force_recreate)
