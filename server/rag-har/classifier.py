"""
RAG-based Activity Classifier - Adapted to dataset-agnostic architecture.

Uses hybrid search with temporal segmentation (whole, start, mid, end) and
LLM-based classification for activity recognition.
"""

import os
import re
import time
import logging
from typing import Dict, List, Any

import pandas as pd
from langchain_openai import OpenAIEmbeddings
from pymilvus import MilvusClient, WeightedRanker, AnnSearchRequest, DataType
from openai import OpenAI
from pydantic import BaseModel
from dotenv import load_dotenv
import openai
from sklearn.metrics import f1_score

from feature_utils import FeatureExtractorUtils

load_dotenv()

# Suppress httpx logs
logging.getLogger("httpx").setLevel(logging.WARNING)

logger = logging.getLogger(__name__)


class ActivityPrediction(BaseModel):
    """Structured output for activity classification."""

    activity_label: str
    reasoning: str


class ActivityPredictionFast(BaseModel):
    """Structured output for fast activity classification (no reasoning)."""

    activity_label: str


def extract_sensor_sections(text: str) -> Dict[str, str]:
    """
    Extract sensor sections for temporal segments from description text.

    Args:
        text: File content as string

    Returns:
        Dict with structure: {'whole': ..., 'start': ..., 'mid': ..., 'end': ...}
    """
    segments = {"whole": {}, "start": {}, "mid": {}, "end": {}}

    # Split text by segment headers
    segment_pattern = r"\[(Whole|Start|Mid|End) Segment\](.*?)(?=\[(?:Whole|Start|Mid|End) Segment\]|$)"
    segment_matches = re.findall(segment_pattern, text, re.DOTALL)

    for segment_name, segment_content in segment_matches:
        segments[segment_name.lower()] = segment_content.strip()

    return segments


class RAGActivityClassifier:
    """
    RAG-based classifier using hybrid search and LLM.

    Architecture:
    1. Extract temporal segments (whole, start, mid, end)
    2. Generate embeddings for each segment
    3. Hybrid search in Milvus with multiple ANN requests
    4. LLM-based classification using retrieved samples
    5. Track RAG quality metrics
    """

    # Default collection name (shared data store)
    DEFAULT_COLLECTION_NAME = "har_demo_collection"
    # Prefix for user data stores
    USER_DATASTORE_PREFIX = "har_user_"

    def __init__(
        self,
        model: str = "gpt-5-mini",
        fewshot: int = 30,
        out_fewshot: int = 20,
    ):
        """
        Initialize RAG classifier.

        Args:
            model: LLM model name for classification
            fewshot: Number of samples to retrieve per segment
            out_fewshot: Final number of samples after reranking
        """
        # Hardcoded configuration for har_demo dataset
        self.dataset_name = "har_demo"
        self.collection_name = self.DEFAULT_COLLECTION_NAME
        self.valid_labels = [
            "walking",
            "running",
            "sitting",
            "standing",
            "jumping",
            "lying_down",
        ]
        self.statistics = ["mean", "std", "min", "max", "median", "p25", "p75"]
        self.sensor_columns = ["accel", "gyro"]

        self.model = model
        self.fewshot = fewshot
        self.out_fewshot = out_fewshot

        # Initialize OpenAI
        self.openai_api_key = os.environ.get("OPENAI_API_KEY")
        if not self.openai_api_key:
            raise ValueError("OPENAI_API_KEY environment variable not set")

        self.embeddings = OpenAIEmbeddings(
            api_key=self.openai_api_key, model="text-embedding-3-small"
        )
        self.openai_client = OpenAI(api_key=self.openai_api_key)

        # Initialize Milvus
        milvus_uri = os.environ.get("ZILLIZ_CLOUD_URI")
        milvus_token = os.environ.get("ZILLIZ_CLOUD_API_KEY")

        if not milvus_uri or not milvus_token:
            raise ValueError(
                "ZILLIZ_CLOUD_URI and ZILLIZ_CLOUD_API_KEY environment variables must be set"
            )

        self.milvus_client = MilvusClient(uri=milvus_uri, token=milvus_token)

        logger.info(f"RAG Classifier initialized for dataset: {self.dataset_name}")
        logger.info(
            f"Collection: {self.collection_name}, Valid labels: {self.valid_labels}"
        )
        logger.info(
            f"LLM Model: {self.model}, Retrieval: {self.fewshot} per segment → {self.out_fewshot} final samples"
        )

        print(f"Initialized RAG Classifier for dataset: {self.dataset_name}")
        print(f"Collection: {self.collection_name}")
        print(f"Valid labels: {self.valid_labels}")
        print(f"LLM Model: {self.model}")
        print(
            f"Retrieval: {self.fewshot} per segment → {self.out_fewshot} final samples"
        )

    # ==================== Data Store Management ====================

    def set_collection(self, collection_name: str) -> bool:
        """
        Switch to a different collection (data store).

        Args:
            collection_name: Name of the collection to switch to

        Returns:
            True if collection exists and was switched, False otherwise
        """
        collections = self.milvus_client.list_collections()
        if collection_name not in collections:
            logger.warning(f"Collection {collection_name} does not exist")
            return False

        self.collection_name = collection_name
        logger.info(f"Switched to collection: {collection_name}")
        return True

    def create_datastore(self, name: str) -> Dict[str, Any]:
        """
        Create a new user data store (Milvus collection).

        Args:
            name: User-friendly name for the data store

        Returns:
            Dict with success status and collection details
        """
        # Generate collection name from user-provided name
        # Sanitize name: lowercase, replace spaces with underscores, remove special chars
        sanitized_name = re.sub(r'[^a-z0-9_]', '', name.lower().replace(' ', '_'))
        collection_name = f"{self.USER_DATASTORE_PREFIX}{sanitized_name}"

        # Check if collection already exists
        collections = self.milvus_client.list_collections()
        if collection_name in collections:
            logger.warning(f"Data store '{name}' already exists")
            return {
                "success": False,
                "error": f"Data store '{name}' already exists",
                "collection_name": collection_name,
            }

        try:
            # Create schema matching the default collection
            schema = MilvusClient.create_schema(
                auto_id=False,
                enable_dynamic_field=False,
            )
            schema.add_field(
                field_name="text",
                datatype=DataType.VARCHAR,
                is_primary=True,
                max_length=100,
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
                max_length=10000,
            )
            schema.add_field(
                field_name="stats_end_text",
                datatype=DataType.VARCHAR,
                max_length=10000,
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

            # Create index params
            index_params = self.milvus_client.prepare_index_params()
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

            # Create the collection
            self.milvus_client.create_collection(
                collection_name=collection_name,
                metric_type="COSINE",
                schema=schema,
                index_params=index_params,
            )

            logger.info(f"Created data store: {name} (collection: {collection_name})")
            return {
                "success": True,
                "name": name,
                "collection_name": collection_name,
                "sample_count": 0,
            }

        except Exception as e:
            logger.error(f"Error creating data store: {e}", exc_info=True)
            return {
                "success": False,
                "error": str(e),
            }

    def delete_datastore(self, collection_name: str) -> Dict[str, Any]:
        """
        Delete a user data store.

        Args:
            collection_name: Name of the collection to delete

        Returns:
            Dict with success status
        """
        # Prevent deleting the default collection
        if collection_name == self.DEFAULT_COLLECTION_NAME:
            logger.warning("Cannot delete the default data store")
            return {
                "success": False,
                "error": "Cannot delete the default data store",
            }

        # Check if collection exists
        collections = self.milvus_client.list_collections()
        if collection_name not in collections:
            logger.warning(f"Data store {collection_name} does not exist")
            return {
                "success": False,
                "error": f"Data store does not exist",
            }

        try:
            self.milvus_client.drop_collection(collection_name)
            logger.info(f"Deleted data store: {collection_name}")

            # If we were using this collection, switch back to default
            if self.collection_name == collection_name:
                self.collection_name = self.DEFAULT_COLLECTION_NAME
                logger.info(f"Switched back to default collection")

            return {
                "success": True,
                "deleted_collection": collection_name,
            }

        except Exception as e:
            logger.error(f"Error deleting data store: {e}", exc_info=True)
            return {
                "success": False,
                "error": str(e),
            }

    def list_datastores(self) -> Dict[str, Any]:
        """
        List all available data stores (collections).

        Returns:
            Dict with list of data stores and their stats
        """
        try:
            collections = self.milvus_client.list_collections()
            datastores = []

            for coll_name in collections:
                # Check if it's a HAR-related collection
                if coll_name == self.DEFAULT_COLLECTION_NAME or coll_name.startswith(self.USER_DATASTORE_PREFIX):
                    try:
                        # Get collection stats
                        stats = self.milvus_client.get_collection_stats(coll_name)
                        sample_count = stats.get("row_count", 0)
                    except Exception:
                        sample_count = 0

                    # Extract user-friendly name
                    if coll_name == self.DEFAULT_COLLECTION_NAME:
                        display_name = "Default (shared)"
                        is_default = True
                    else:
                        # Remove prefix to get user name
                        display_name = coll_name[len(self.USER_DATASTORE_PREFIX):].replace('_', ' ').title()
                        is_default = False

                    datastores.append({
                        "name": display_name,
                        "collection_name": coll_name,
                        "sample_count": sample_count,
                        "is_default": is_default,
                        "is_active": coll_name == self.collection_name,
                    })

            # Sort: default first, then by name
            datastores.sort(key=lambda x: (not x["is_default"], x["name"]))

            return {
                "success": True,
                "datastores": datastores,
                "active_collection": self.collection_name,
            }

        except Exception as e:
            logger.error(f"Error listing data stores: {e}", exc_info=True)
            return {
                "success": False,
                "error": str(e),
                "datastores": [],
            }

    def get_current_datastore(self) -> Dict[str, Any]:
        """
        Get info about the currently active data store.

        Returns:
            Dict with current data store info
        """
        try:
            stats = self.milvus_client.get_collection_stats(self.collection_name)
            sample_count = stats.get("row_count", 0)
        except Exception:
            sample_count = 0

        is_default = self.collection_name == self.DEFAULT_COLLECTION_NAME

        if is_default:
            display_name = "Default (shared)"
        else:
            display_name = self.collection_name[len(self.USER_DATASTORE_PREFIX):].replace('_', ' ').title()

        return {
            "name": display_name,
            "collection_name": self.collection_name,
            "sample_count": sample_count,
            "is_default": is_default,
        }

    # ==================== End Data Store Management ====================

    # Note: _split_temporal_segments and _compute_stats removed - using FeatureExtractorUtils instead

    def _generate_feature_description(self, df: pd.DataFrame) -> str:
        """
        Generate feature description from a DataFrame, matching the format
        used in training (with temporal segmentation).

        Uses FeatureExtractorUtils for consistent feature extraction with training pipeline.

        Args:
            df: Window DataFrame with columns like accel_x, accel_y, accel_z, etc.

        Returns:
            Formatted feature description string
        """
        # Split into temporal segments using shared utility (same as training)
        segments = FeatureExtractorUtils.split_temporal_segments(df)

        # Sensor metadata: (name, unit)
        sensor_metadata = {
            "accel": ("Acceleration", "m/s²"),
            "gyro": ("Gyroscope", "rad/s"),
        }

        # Segment name mapping
        segment_names = {
            "whole": "Whole Segment",
            "start": "Start Segment",
            "middle": "Mid Segment",
            "end": "End Segment",
        }

        description_parts = []

        for segment_key in ["whole", "start", "middle", "end"]:
            segment_df = segments[segment_key]
            segment_name = segment_names[segment_key]
            description_parts.append(f"[{segment_name}]")

            # Process each sensor
            for prefix in self.sensor_columns:
                sensor_name, unit = sensor_metadata[prefix]
                axes = ["x", "y", "z"]

                # Per-axis features using shared utility (handles NaN consistently)
                for axis_idx, axis in enumerate(axes, start=1):
                    col_name = f"{prefix}_{axis}"
                    if col_name in segment_df.columns:
                        stats_dict = FeatureExtractorUtils.compute_stats(
                            segment_df[col_name], self.statistics
                        )
                        stats_str = ", ".join(
                            [f"{k}={v:.3f}" for k, v in stats_dict.items()]
                        )
                        description_parts.append(
                            f"  {sensor_name} (axis {axis_idx}, {unit}): {stats_str}"
                        )

            description_parts.append("")  # Empty line after each segment

        return "\n".join(description_parts)

    def classify_dataframe(self, df: pd.DataFrame, fast_inference: bool = False) -> Dict:
        """
        Classify a DataFrame containing sensor data directly.

        Args:
            df: DataFrame with sensor columns (accel_x, accel_y, accel_z, gyro_x, etc.)
            fast_inference: If True, use faster inference with simpler prompts

        Returns:
            Dict with prediction and metadata
        """
        logger.info(f"Starting classification for {len(df)} sensor samples (fast_inference={fast_inference})")

        # Generate feature description from the raw dataframe
        logger.info("Generating feature description from raw sensor data")
        content = self._generate_feature_description(df)

        # Extract temporal segments
        logger.info("Extracting temporal segments (whole, start, mid, end)")
        segments = extract_sensor_sections(content)
        whole_stats = segments["whole"]
        start_stats = segments["start"]
        mid_stats = segments["mid"]
        end_stats = segments["end"]

        # Generate embeddings for each segment
        logger.info("Generating embeddings for 4 temporal segments")
        stats_emb = self.embeddings.embed_query(str(whole_stats))
        start_stats_emb = self.embeddings.embed_query(str(start_stats))
        mid_stats_emb = self.embeddings.embed_query(str(mid_stats))
        end_stats_emb = self.embeddings.embed_query(str(end_stats))
        logger.info("Embeddings generated successfully")

        # Create ANN search requests for each segment
        req_1 = AnnSearchRequest(
            anns_field="activity_stats_emb",
            data=[stats_emb],
            limit=self.fewshot,
            param={"metric_type": "COSINE", "params": {"nprobe": 10}},
        )
        req_2 = AnnSearchRequest(
            anns_field="activity_stats_start_emb",
            data=[start_stats_emb],
            limit=self.fewshot,
            param={"metric_type": "COSINE", "params": {"nprobe": 10}},
        )
        req_3 = AnnSearchRequest(
            anns_field="activity_stats_mid_emb",
            data=[mid_stats_emb],
            limit=self.fewshot,
            param={"metric_type": "COSINE", "params": {"nprobe": 10}},
        )
        req_4 = AnnSearchRequest(
            anns_field="activity_stats_end_emb",
            data=[end_stats_emb],
            limit=self.fewshot,
            param={"metric_type": "COSINE", "params": {"nprobe": 10}},
        )

        # Hybrid search with weighted ranker
        logger.info(
            f"Performing hybrid search in Milvus: {self.fewshot} samples per segment → "
            f"{self.out_fewshot} final samples (weighted ranker: 0.25/0.25/0.25/0.25)"
        )
        docs = self.milvus_client.hybrid_search(
            collection_name=self.collection_name,
            output_fields=[
                "text",
                "timeseries_metadata",
                "stats_whole_text",
                "stats_start_text",
                "stats_mid_text",
                "stats_end_text",
            ],
            reqs=[req_1, req_2, req_3, req_4],
            limit=self.out_fewshot,
            ranker=WeightedRanker(0.25, 0.25, 0.25, 0.25),
        )
        logger.info(f"Hybrid search completed, processing retrieved documents")

        # Process retrieved documents
        retrieved_labels = []
        sections = []
        for doc in docs:
            for hit in doc:
                entity = hit.entity
                whole_data = entity["stats_whole_text"]

                # Extract activity label from metadata
                metadata = entity.get("timeseries_metadata", {})
                if isinstance(metadata, dict):
                    sample_label = metadata.get("activity_id") or metadata.get(
                        "activity", "unknown"
                    )
                else:
                    sample_label = "unknown"

                retrieved_labels.append(sample_label)
                sections.append(
                    f"Activity Label: {sample_label}\n\n"
                    f"[Whole Segment]:\n{whole_data}\n"
                    f"[Start Segment]:\n{entity['stats_start_text']}\n"
                    f"[Mid Segment]:\n{entity['stats_mid_text']}\n"
                    f"[End Segment]:\n{entity['stats_end_text']}\n"
                )

        # Analyze retrieval quality
        label_counts = pd.Series(retrieved_labels).value_counts()
        logger.info(
            f"Retrieved {len(retrieved_labels)} samples. "
            f"Label distribution: {dict(label_counts)}"
        )

        # DEBUG: Log candidate statistics summary
        # logger.info(f"=== CANDIDATE STATISTICS (first 200 chars) ===")
        # logger.info(f"{whole_stats[:200]}...")
        # logger.info(f"=== END CANDIDATE STATISTICS ===")

        # Construct prompt for LLM
        retrieved_data = "\n\n".join(sections)
        classes_str = str(self.valid_labels)

        if fast_inference:
            # Fast inference: simpler prompt for quicker responses
            system_prompt = f"""Use semantic similarity to compare the candidate statistics with the retrieved samples and output the activity label that maximizes similarity; respond with only the class label from {classes_str}."""
            logger.info("Using FAST inference system prompt")
        else:
            # Standard inference: detailed prompt with explanation rules
            system_prompt = f"""Use semantic similarity to compare the candidate statistics with the retrieved samples and output the activity label that maximizes similarity; respond with only the class label from {classes_str}.
        Provide a short explanation (2–3 sentences) using ONLY human-friendly motion descriptions.
Explanation rules:
- Use only: movement intensity (low/moderate/high), rhythm (steady/repeating/irregular), phone rotation (stable/some/frequent), and overall body movement.
- Do NOT mention statistics, axes, gravity alignment, standard deviation, mean, variance, frequency, "near zero", or any numbers.
- Do NOT copy phrases from the input; translate them into everyday language.
- Keep it suitable for a mobile UI.
"""
            logger.info("Using STANDARD inference system prompt")
        
        
        series = (
            f"[Whole Segment]:\n{whole_stats}\n"
            f"[Start Segment]:\n{start_stats}\n"
            f"[Mid Segment]:\n{mid_stats}\n"
            f"[End Segment]:\n{end_stats}\n"
        )

        user_prompt = f"""\n You are given summary statistics for sensor data across temporal segments for labeled samples and one unlabeled candidate.\n\n--- CANDIDATE ---\n{series}\n\n--- LABELED SAMPLES ---\n{retrieved_data}\n"""

        # Call LLM with retry logic
        logger.info(
            f"Calling LLM ({self.model}) for classification with retrieved context (fast_inference={fast_inference})"
        )
        success = False
        retry_count = 0

        # Choose response format based on fast_inference
        response_format = ActivityPredictionFast if fast_inference else ActivityPrediction

        while not success:
            try:
                response = self.openai_client.beta.chat.completions.parse(
                    model=self.model,
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt},
                    ],
                    response_format=response_format,
                )
                prediction = response.choices[0].message.parsed.activity_label
                reasoning = getattr(response.choices[0].message.parsed, 'reasoning', None)
                success = True
                logger.info(
                    f"LLM response received: {prediction}" + (f" with reasoning: {reasoning}" if reasoning else " (no reasoning)")
                )
            except openai.RateLimitError:
                retry_count += 1
                logger.warning(
                    f"Rate limit reached (retry {retry_count}). Waiting 65 seconds..."
                )
                print("Rate limit reached. Waiting 65 seconds...")
                time.sleep(65)
            except Exception as e:
                retry_count += 1
                logger.warning(
                    f"OpenAI API error (retry {retry_count}): {e}. Waiting 10 seconds..."
                )
                print(f"OpenAI API error: {e}. Waiting 10 seconds...")
                time.sleep(10)

        # Display results
        retrieved_labels_display = [str(label) for label in retrieved_labels]

        print(f"\n{'='*70}")
        print(f"Real-time Classification")
        print(f"Retrieved classes: {retrieved_labels_display}")  # Show all
        print(f"LLM Prediction: {prediction}")
        print(f"{'='*70}")

        result = {
            "prediction": prediction,
            "reasoning": reasoning,
            "fast_inference": fast_inference,
            "retrieved_labels": list(set(retrieved_labels)),
            "num_retrieved": len(retrieved_labels),
            "feature_description": content,
        }
        logger.info(
            f"Returning classification result with {result['num_retrieved']} retrieved samples"
        )
        return result

    def predict_from_window(self, window_data: list, fast_inference: bool = False) -> Dict[str, Any]:
        """
        Simplified prediction method for real-time use in activity_predictor.

        Args:
            window_data: List of sensor reading dicts with keys:
                        accel_x, accel_y, accel_z, gyro_x, gyro_y, gyro_z
            fast_inference: If True, use faster inference with simpler prompts

        Returns:
            Dict with 'activity' (predicted label) and 'confidence' (float)
        """
        try:
            logger.info(f"predict_from_window called with {len(window_data)} samples (fast_inference={fast_inference})")

            # Convert window data to DataFrame
            df = pd.DataFrame(window_data)
            logger.info(f"Converted to DataFrame with shape {df.shape}")

            # Use classify_dataframe method
            result = self.classify_dataframe(df, fast_inference=fast_inference)

            # Get prediction from result
            prediction = result["prediction"]
            reasoning = result.get("reasoning")

            logger.info(f"Final result: {prediction} with reasoning: {reasoning}")

            return {"activity": prediction, "reasoning": reasoning}
        except Exception as e:
            logger.error(f"Error in predict_from_window: {e}", exc_info=True)
            return {"activity": "unknown"}

    def evaluate_on_test_set(self) -> Dict[str, Any]:
        """
        Evaluate classifier on all test set description files.
        Processes all files in features/test/descriptions/ session folders.

        Returns:
            Dict with accuracy, confusion matrix, and detailed results
        """
        from pathlib import Path
        from tqdm import tqdm

        # Auto-generate paths
        base_path = Path(__file__).parent.parent
        test_descriptions_dir = (
            base_path
            / "output"
            / self.dataset_name
            / "features"
            / "test"
            / "descriptions"
        )
        test_windows_dir = (
            base_path / "output" / self.dataset_name / "train-test-splits" / "test"
        )

        logger.info("=" * 80)
        logger.info("EVALUATING CLASSIFIER ON TEST SET")
        logger.info("=" * 80)
        logger.info(f"Test descriptions: {test_descriptions_dir}")
        logger.info(f"Test windows: {test_windows_dir}")
        logger.info("")

        if not test_descriptions_dir.exists():
            logger.error(
                f"Test descriptions directory not found: {test_descriptions_dir}"
            )
            return {"error": "Test descriptions directory not found"}

        # Collect all test files from session folders
        test_files = []
        for session_dir in test_descriptions_dir.iterdir():
            if not session_dir.is_dir():
                continue

            session_files = list(session_dir.glob("*.txt"))
            test_files.extend(session_files)

        if not test_files:
            logger.error(f"No test description files found in {test_descriptions_dir}")
            return {"error": "No test files found"}

        logger.info(f"Found {len(test_files)} test samples to evaluate")
        logger.info("")

        # Process each test file
        results = []
        correct = 0
        total = 0

        for file_path in tqdm(test_files, desc="Evaluating test samples"):
            try:
                # Parse filename: session_id_window_0_activity_walking_stats.txt
                base = file_path.name
                m = re.match(
                    r"(.+)_window_(\d+)_activity_([A-Za-z0-9_-]+)_stats\.txt", base
                )
                if not m:
                    logger.warning(f"Could not parse filename: {base}")
                    continue

                session_id, window_id, true_activity = m.groups()

                # Find corresponding CSV window file
                # Path: test/session_id/activity/session_id_window_0_activity.csv
                csv_file = (
                    test_windows_dir
                    / session_id
                    / true_activity
                    / f"{session_id}_window_{window_id}_{true_activity}.csv"
                )

                if not csv_file.exists():
                    logger.warning(f"CSV file not found: {csv_file}")
                    continue

                # Load window data
                df = pd.read_csv(csv_file)

                # Classify
                result = self.classify_dataframe(df)
                prediction = result["prediction"]
                reasoning = result.get("reasoning")

                # Check if correct
                is_correct = prediction.lower() == true_activity.lower()
                if is_correct:
                    correct += 1
                total += 1

                results.append(
                    {
                        "session_id": session_id,
                        "window_id": window_id,
                        "true_label": true_activity,
                        "prediction": prediction,
                        "correct": is_correct,
                        "retrieved_labels": result.get("retrieved_labels", []),
                        "num_retrieved": result.get("num_retrieved", 0),
                    }
                )

                logger.info(
                    f"Sample {total}: True={true_activity}, Pred={prediction}, Reasoning={reasoning} - "
                    f"Correct={is_correct}, Retrieved={result.get('num_retrieved', 0)} samples"
                )

            except Exception as e:
                logger.error(f"Error processing file {file_path}: {e}")
                continue

        # Calculate metrics
        accuracy = correct / total if total > 0 else 0.0

        # Confusion matrix
        confusion_matrix = {}
        for r in results:
            true = r["true_label"]
            pred = r["prediction"]
            key = f"{true} -> {pred}"
            confusion_matrix[key] = confusion_matrix.get(key, 0) + 1

        # Calculate F1 scores
        y_true = [r["true_label"] for r in results]
        y_pred = [r["prediction"] for r in results]
        f1_weighted = f1_score(y_true, y_pred, average="weighted")

        # Per-class metrics (accuracy and F1)
        per_class_metrics = {}
        for label in self.valid_labels:
            class_results = [r for r in results if r["true_label"] == label]
            if class_results:
                class_correct = sum(1 for r in class_results if r["correct"])
                class_accuracy = class_correct / len(class_results)

                # Calculate per-class F1 score
                class_f1 = f1_score(
                    y_true, y_pred, labels=[label], average="macro", zero_division=0
                )

                per_class_metrics[label] = {
                    "accuracy": class_accuracy,
                    "f1": class_f1,
                }

        # Final report
        logger.info("")
        logger.info("=" * 80)
        logger.info("TEST SET EVALUATION RESULTS")
        logger.info("=" * 80)
        logger.info(f"Total samples: {total}")
        logger.info(f"Correct: {correct}")
        logger.info(f"Overall Accuracy: {accuracy:.2%}")
        logger.info(f"F1 Score (weighted): {f1_weighted:.2%}")
        logger.info("")
        logger.info("Per-class metrics:")
        logger.info(f"{'Activity':<15} {'Accuracy':<10} {'F1 Score':<10}")
        logger.info("-" * 38)
        for label in sorted(per_class_metrics.keys()):
            metrics = per_class_metrics[label]
            logger.info(
                f"{label:<15} "
                f"{metrics['accuracy']:<10.2%} "
                f"{metrics['f1']:<10.2%}"
            )
        logger.info("")
        logger.info("Confusion matrix (true -> predicted):")
        for key, count in sorted(confusion_matrix.items()):
            logger.info(f"  {key}: {count}")
        logger.info("=" * 80)

        return {
            "accuracy": accuracy,
            "f1_weighted": f1_weighted,
            "total_samples": total,
            "correct_samples": correct,
            "per_class_metrics": per_class_metrics,
            "confusion_matrix": confusion_matrix,
            "detailed_results": results,
        }


def main():
    """
    Main function to run classifier evaluation on test set.
    """
    import logging

    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(levelname)s - %(message)s",
        datefmt="%H:%M:%S",
    )

    print("=" * 80)
    print("RAG-BASED ACTIVITY CLASSIFIER - TEST SET EVALUATION")
    print("=" * 80)
    print("")

    # Initialize classifier
    print("Initializing RAG classifier...")
    classifier = RAGActivityClassifier(
        model="gpt-5-mini",
        fewshot=15,
        out_fewshot=10,
    )
    print("")

    # Run evaluation
    print("Starting test set evaluation...")
    print("")
    results = classifier.evaluate_on_test_set()

    # Save results to file
    if "error" not in results:
        from pathlib import Path
        import json

        output_dir = Path(__file__).parent.parent / "output" / "har_demo"
        output_dir.mkdir(parents=True, exist_ok=True)

        results_file = output_dir / "test_evaluation_results.json"

        # Convert detailed results to serializable format
        serializable_results = {
            "accuracy": results["accuracy"],
            "f1_weighted": results["f1_weighted"],
            "total_samples": results["total_samples"],
            "correct_samples": results["correct_samples"],
            "per_class_metrics": results["per_class_metrics"],
            "confusion_matrix": results["confusion_matrix"],
        }

        with open(results_file, "w") as f:
            json.dump(serializable_results, f, indent=2)

        print("")
        print(f"Results saved to: {results_file}")
        print("")
        print("=" * 80)
        print("EVALUATION COMPLETE")
        print("=" * 80)
    else:
        print(f"Error: {results['error']}")


if __name__ == "__main__":
    main()
