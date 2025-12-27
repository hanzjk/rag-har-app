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
from pymilvus import MilvusClient, WeightedRanker, AnnSearchRequest
from openai import OpenAI
from pydantic import BaseModel
from dotenv import load_dotenv
import openai

load_dotenv()

# Suppress httpx logs
logging.getLogger("httpx").setLevel(logging.WARNING)

logger = logging.getLogger(__name__)


class ActivityPrediction(BaseModel):
    """Structured output for activity classification."""

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
        self.collection_name = "har_demo_collection"
        self.valid_labels = ["walking", "running", "sitting", "standing"]
        self.statistics = ["mean", "std", "min", "max", "median", "p25", "p75"]
        self.sensor_columns = ["accel", "gyro", "mag"]

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

    def _split_temporal_segments(self, df: pd.DataFrame) -> Dict[str, pd.DataFrame]:
        """
        Split window into temporal segments: whole, start, middle, end.

        Args:
            df: Window DataFrame

        Returns:
            Dict with keys 'whole', 'start', 'middle', 'end'
        """
        total_len = len(df)
        segment_size = total_len // 3

        return {
            "whole": df,
            "start": df.iloc[:segment_size],
            "middle": df.iloc[segment_size : 2 * segment_size],
            "end": df.iloc[2 * segment_size :],
        }

    def _compute_stats(
        self, series: pd.Series, stats_list: List[str]
    ) -> Dict[str, float]:
        """
        Compute statistical features for a series.

        Args:
            series: Data series
            stats_list: List of statistics to compute

        Returns:
            Dict of computed statistics
        """
        stats = {}
        for stat in stats_list:
            if stat == "mean":
                stats["mean"] = series.mean()
            elif stat == "std":
                stats["std"] = series.std()
            elif stat == "min":
                stats["min"] = series.min()
            elif stat == "max":
                stats["max"] = series.max()
            elif stat == "median":
                stats["median"] = series.median()
            elif stat == "p25":
                stats["p25"] = series.quantile(0.25)
            elif stat == "p75":
                stats["p75"] = series.quantile(0.75)
        return stats

    def _generate_feature_description(self, df: pd.DataFrame) -> str:
        """
        Generate feature description from a DataFrame, matching the format
        used in training (with temporal segmentation).

        Args:
            df: Window DataFrame with columns like accel_x, accel_y, accel_z, etc.

        Returns:
            Formatted feature description string
        """
        # Split into temporal segments
        segments = self._split_temporal_segments(df)

        # Sensor metadata: (name, unit)
        sensor_metadata = {
            "accel": ("Acceleration", "m/s²"),
            "gyro": ("Gyroscope", "rad/s"),
            "mag": ("Magnetometer", "μT"),
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

                # Per-axis features
                for axis_idx, axis in enumerate(axes, start=1):
                    col_name = f"{prefix}_{axis}"
                    if col_name in segment_df.columns:
                        stats_dict = self._compute_stats(
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

    def classify_dataframe(self, df: pd.DataFrame) -> Dict:
        """
        Classify a DataFrame containing sensor data directly.

        Args:
            df: DataFrame with sensor columns (accel_x, accel_y, accel_z, gyro_x, etc.)

        Returns:
            Dict with prediction and metadata
        """
        logger.info(f"Starting classification for {len(df)} sensor samples")

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

        # Construct prompt for LLM
        retrieved_data = "\n\n".join(sections)
        classes_str = str(self.valid_labels)

        system_prompt = f"""You are a multi-class activity classifier using statistical summaries of tri-axis accelerometer, gyroscope, and magnetometer sensors.

INSTRUCTIONS:
1. Classify the CANDIDATE into exactly ONE class from CLASSES
2. Use the retrieved samples as REFERENCE PATTERNS.

CLASSES = {classes_str}

"""
        series = (
            f"[Whole Segment]:\n{whole_stats}\n"
            f"[Start Segment]:\n{start_stats}\n"
            f"[Mid Segment]:\n{mid_stats}\n"
            f"[End Segment]:\n{end_stats}\n"
        )

        user_prompt = f"""\n--- CANDIDATE ---\n{series}\n\n--- LABELED SAMPLES ---\n{retrieved_data}\n"""

        # Call LLM with retry logic
        logger.info(
            f"Calling LLM ({self.model}) for classification with retrieved context"
        )
        success = False
        retry_count = 0
        while not success:
            try:
                response = self.openai_client.beta.chat.completions.parse(
                    model=self.model,
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt},
                    ],
                    response_format=ActivityPrediction,
                )
                prediction = response.choices[0].message.parsed.activity_label
                success = True
                logger.info(f"LLM response received: {prediction}")
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
            "retrieved_labels": list(set(retrieved_labels)),
            "num_retrieved": len(retrieved_labels),
            "feature_description": content,
        }
        logger.info(
            f"Returning classification result with {result['num_retrieved']} retrieved samples"
        )
        return result

    def predict_from_window(self, window_data: list) -> Dict[str, Any]:
        """
        Simplified prediction method for real-time use in activity_predictor.

        Args:
            window_data: List of sensor reading dicts with keys:
                        accel_x, accel_y, accel_z, gyro_x, gyro_y, gyro_z, mag_x, mag_y, mag_z

        Returns:
            Dict with 'activity' (predicted label) and 'confidence' (float)
        """
        try:
            logger.info(f"predict_from_window called with {len(window_data)} samples")

            # Convert window data to DataFrame
            df = pd.DataFrame(window_data)
            logger.info(f"Converted to DataFrame with shape {df.shape}")

            # Use classify_dataframe method
            result = self.classify_dataframe(df)

            # Get prediction from result
            prediction = result["prediction"]

            logger.info(f"Final result: {prediction}")

            return {"activity": prediction}

        except Exception as e:
            logger.error(f"Error in predict_from_window: {e}", exc_info=True)
            return {"activity": "unknown"}
