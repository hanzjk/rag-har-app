#!/usr/bin/env python3
"""
WebSocket Server for Human Activity Recognition
Receives sensor data from Flutter app and either:
1. Collects data for dataset creation (data collection mode)
2. Sends back activity predictions (activity recognition mode)
"""

import asyncio
import json
import logging
import argparse
import os
import sys
from datetime import datetime, timezone
from typing import Set, Optional, Dict
import websockets

from data_collector import DataCollector
from activity_predictor import ActivityPredictor
from prediction_data_logger import PredictionDataLogger

from rag_har_pipeline import run_pipeline_async

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

# Store connected clients
connected_clients: Set = set()

# Global data directory (will be set in main)
data_dir: str = "collected_data"

# Global classifier instance (shared across clients if enabled)
global_classifier = None


async def handle_client(websocket):
    """Handle a client connection"""
    try:
        client_id = f"{websocket.remote_address[0]}:{websocket.remote_address[1]}"
        connected_clients.add(websocket)
        logger.info(
            f"🟢 Client connected: {client_id} (Total: {len(connected_clients)})"
        )
    except Exception as e:
        logger.error(f"❌ Error in handle_client setup: {e}")
        return

    sample_count = 0

    # Create per-client instances
    # Pass global classifier to predictor (may be None for mock mode)
    client_predictor = ActivityPredictor(classifier=global_classifier)
    client_collector = None  # Will be created on first collect_data message
    client_prediction_logger = (
        PredictionDataLogger()
    )  # Logs prediction windows if enabled
    mode = "RAG-based" if global_classifier else "mock"
    logger.info(f"Created {mode} predictor for client: {client_id}")

    # Track if we're in an active prediction session
    prediction_session_active = False

    # Parallel prediction support
    prediction_semaphore = asyncio.Semaphore(3)  # Max 3 concurrent predictions
    pending_tasks: Set[asyncio.Task] = set()

    async def process_prediction_async(window_id: str, window_data: list, fast_inference: bool, collection_start_time: str = None):
        """Process a single prediction asynchronously."""
        async with prediction_semaphore:
            logger.info(f"Starting prediction for window {window_id} (collection_start_time: {collection_start_time})")
            prediction = await client_predictor.predict_async(
                window_id, window_data, fast_inference, collection_start_time
            )

            # Log prediction window if enabled
            if prediction.get("activity") not in ["error", "unknown"]:
                client_prediction_logger.log_prediction_window(window_data, prediction)

            try:
                # Send prediction back (order may vary due to async)
                await websocket.send(json.dumps(prediction))
                logger.info(
                    f"Sent prediction for window {window_id}: {prediction['activity']}"
                )
            except websockets.exceptions.ConnectionClosed:
                logger.info(
                    f"Client {client_id} disconnected while sending prediction {window_id}"
                )

    try:
        async for message in websocket:
            try:
                # Parse incoming message
                data = json.loads(message)
                message_type = data.get("type")
                timestamp = data.get("timestamp", "unknown")

                if message_type == "collect_data":
                    # Data collection mode
                    # Create collector on first collect_data message
                    if client_collector is None:
                        subject_id = data.get("subject_id", "subject0")
                        client_collector = DataCollector(
                            data_dir, subject_id=subject_id
                        )
                        logger.info(
                            f"Created data collector for {client_collector.get_subject_folder_name()}"
                        )

                    activity = data.get("activity", "unlabeled")
                    success = client_collector.save_sensor_data(data, activity)

                    if success:
                        sample_count += 1
                        if sample_count % 20 == 0:  # Log every 20 samples
                            logger.info(
                                f"Collected {sample_count} samples for activity: {activity}"
                            )

                        # Send acknowledgment back to client
                        response = {
                            "type": "collection_ack",
                            "samples_collected": sample_count,
                            "activity": activity,
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                        }
                        await websocket.send(json.dumps(response))

                elif message_type == "stop_collection":
                    # Stop collection and run RAG-HAR pipeline
                    logger.info(f"Received stop_collection signal from {client_id}")
                    logger.info(f"Total samples collected: {sample_count}")

                    if client_collector is None:
                        logger.warning(
                            "No data collector exists - no data was collected"
                        )
                        error_response = {
                            "type": "stop_collection_ack",
                            "samples_collected": 0,
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                            "message": "No data was collected",
                        }
                        await websocket.send(json.dumps(error_response))
                        continue

                    # Get subject folder name before closing
                    subject_folder_name = client_collector.get_subject_folder_name()

                    # Close all CSV files
                    client_collector.close_all()

                    # Send acknowledgment
                    response = {
                        "type": "stop_collection_ack",
                        "samples_collected": sample_count,
                        "subject_folder": subject_folder_name,
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                        "message": "Data collection stopped. Starting RAG-HAR pipeline...",
                    }
                    await websocket.send(json.dumps(response))

                    # Run RAG-HAR pipeline in background
                    # Use the currently selected collection from the classifier
                    current_collection = None
                    if global_classifier:
                        current_datastore = global_classifier.get_current_datastore()
                        current_collection = current_datastore.get("collection_name")
                    logger.info(f"Starting RAG-HAR pipeline for {subject_folder_name} (collection: {current_collection or 'default'})")
                    try:
                        pipeline_thread = run_pipeline_async(collection_name=current_collection)
                        logger.info(f"RAG-HAR pipeline started in background")

                        # Send pipeline started notification
                        pipeline_response = {
                            "type": "pipeline_started",
                            "subject_folder": subject_folder_name,
                            "collection_name": current_collection,
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                            "message": f"RAG-HAR pipeline is processing your data in the background (collection: {current_collection or 'default'})",
                        }
                        await websocket.send(json.dumps(pipeline_response))
                    except Exception as e:
                        logger.error(
                            f"Failed to start RAG-HAR pipeline: {e}", exc_info=True
                        )
                        error_response = {
                            "type": "pipeline_error",
                            "error": str(e),
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                        }
                        await websocket.send(json.dumps(error_response))

                    # Reset sample count and collector for this client
                    sample_count = 0
                    client_collector = None

                elif message_type == "predict_activity":
                    # Activity recognition mode - continuous collection with async predictions
                    logger.debug(
                        f"Received prediction request from {client_id} at {timestamp}"
                    )

                    # Reset prediction counter if starting a new session
                    if not prediction_session_active:
                        logger.info(f"Starting new prediction session for {client_id}")
                        client_predictor.reset_prediction_counter()
                        prediction_session_active = True

                    # Extract fast_inference flag from the message
                    fast_inference = data.get("fast_inference", False)

                    # Capture window (non-blocking) - returns (window_id, data, collection_start_time) when ready
                    result = client_predictor.capture_window(data)

                    if result is not None:
                        window_id, window_data, collection_start_time = result

                        # Send immediate acknowledgment that window was received
                        ack = {
                            "type": "window_received",
                            "window_id": window_id,
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                        }
                        await websocket.send(json.dumps(ack))
                        logger.info(f"Window {window_id} acknowledged, starting async prediction (collection_start_time: {collection_start_time})")

                        # Start async prediction (fire and forget)
                        task = asyncio.create_task(
                            process_prediction_async(window_id, window_data, fast_inference, collection_start_time)
                        )
                        pending_tasks.add(task)
                        task.add_done_callback(pending_tasks.discard)

                elif message_type == "create_datastore":
                    # Create a new user data store
                    if global_classifier is None:
                        response = {
                            "type": "datastore_error",
                            "error": "Classifier not initialized",
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                        }
                    else:
                        name = data.get("name", "")
                        if not name:
                            response = {
                                "type": "datastore_error",
                                "error": "Name is required",
                                "timestamp": datetime.now(timezone.utc).isoformat(),
                            }
                        else:
                            result = global_classifier.create_datastore(name)
                            response = {
                                "type": "datastore_created",
                                "timestamp": datetime.now(timezone.utc).isoformat(),
                                **result,
                            }
                    await websocket.send(json.dumps(response))
                    logger.info(f"Create datastore request from {client_id}: {data.get('name', '')}")

                elif message_type == "delete_datastore":
                    # Delete a user data store
                    if global_classifier is None:
                        response = {
                            "type": "datastore_error",
                            "error": "Classifier not initialized",
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                        }
                    else:
                        collection_name = data.get("collection_name", "")
                        if not collection_name:
                            response = {
                                "type": "datastore_error",
                                "error": "Collection name is required",
                                "timestamp": datetime.now(timezone.utc).isoformat(),
                            }
                        else:
                            result = global_classifier.delete_datastore(collection_name)
                            response = {
                                "type": "datastore_deleted",
                                "timestamp": datetime.now(timezone.utc).isoformat(),
                                **result,
                            }
                    await websocket.send(json.dumps(response))
                    logger.info(f"Delete datastore request from {client_id}: {data.get('collection_name', '')}")

                elif message_type == "list_datastores":
                    # List all available data stores
                    if global_classifier is None:
                        response = {
                            "type": "datastore_error",
                            "error": "Classifier not initialized",
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                        }
                    else:
                        result = global_classifier.list_datastores()
                        response = {
                            "type": "datastores_list",
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                            **result,
                        }
                    await websocket.send(json.dumps(response))
                    logger.info(f"List datastores request from {client_id}")

                elif message_type == "set_datastore":
                    # Switch to a different data store
                    if global_classifier is None:
                        response = {
                            "type": "datastore_error",
                            "error": "Classifier not initialized",
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                        }
                    else:
                        collection_name = data.get("collection_name", "")
                        if not collection_name:
                            response = {
                                "type": "datastore_error",
                                "error": "Collection name is required",
                                "timestamp": datetime.now(timezone.utc).isoformat(),
                            }
                        else:
                            success = global_classifier.set_collection(collection_name)
                            if success:
                                current = global_classifier.get_current_datastore()
                                response = {
                                    "type": "datastore_switched",
                                    "timestamp": datetime.now(timezone.utc).isoformat(),
                                    "success": True,
                                    **current,
                                }
                            else:
                                response = {
                                    "type": "datastore_error",
                                    "error": f"Data store not found: {collection_name}",
                                    "timestamp": datetime.now(timezone.utc).isoformat(),
                                    "success": False,
                                }
                    await websocket.send(json.dumps(response))
                    logger.info(f"Set datastore request from {client_id}: {data.get('collection_name', '')}")

                elif message_type == "get_current_datastore":
                    # Get current active data store info
                    if global_classifier is None:
                        response = {
                            "type": "datastore_error",
                            "error": "Classifier not initialized",
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                        }
                    else:
                        current = global_classifier.get_current_datastore()
                        response = {
                            "type": "current_datastore",
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                            **current,
                        }
                    await websocket.send(json.dumps(response))
                    logger.info(f"Get current datastore request from {client_id}")

                elif message_type == "ping":
                    # Keep-alive ping - just acknowledge
                    pass

                else:
                    logger.warning(
                        f"Unknown message type from {client_id}: {message_type}"
                    )

            except json.JSONDecodeError as e:
                logger.error(f"Invalid JSON from {client_id}: {e}")
            except Exception as e:
                logger.error(f"Error processing message from {client_id}: {e}")

    except websockets.exceptions.ConnectionClosed:
        logger.info(f"Client disconnected: {client_id}")
        if sample_count > 0:
            logger.info(f"Total samples collected from {client_id}: {sample_count}")
    finally:
        # Cancel all pending prediction tasks
        if pending_tasks:
            logger.info(f"Cancelling {len(pending_tasks)} pending predictions for {client_id}")
            for task in pending_tasks:
                task.cancel()

        # Clean up per-client resources
        logger.info(f"Cleaning up resources for client: {client_id}")
        client_predictor.reset_window()
        if client_collector is not None:
            client_collector.close_all()
        client_prediction_logger.close()
        connected_clients.remove(websocket)
        logger.info(f"Client removed: {client_id} (Total: {len(connected_clients)})")


async def main():
    """Start the WebSocket server"""
    host = "0.0.0.0"  # Listen on all interfaces
    port = 8000  # Changed from 8000 to avoid firewall issues

    logger.info("=" * 60)
    logger.info(f"Starting WebSocket server on ws://{host}:{port}")
    logger.info(f"Data will be saved to: {data_dir}")
    logger.info("Ready to handle both data collection and activity prediction")

    # Show accessible URLs
    import socket

    try:
        hostname = socket.gethostname()
        local_ip = socket.gethostbyname(hostname)
        logger.info(f"📱 Connect from mobile app using: ws://{local_ip}:{port}/ws")
    except socket.gaierror:
        logger.info(f"📱 Connect from mobile app using: ws://<your-local-ip>:{port}/ws")

    logger.info("=" * 60)
    logger.info("Waiting for connections...")

    async with websockets.serve(handle_client, host, port):
        await asyncio.Future()  # Run forever


if __name__ == "__main__":
    # Parse command-line arguments
    parser = argparse.ArgumentParser(
        description="WebSocket Server for Human Activity Recognition"
    )
    parser.add_argument(
        "--data-dir",
        default="collected_data",
        help="Directory to save collected data",
    )

    args = parser.parse_args()

    # Set global data directory
    data_dir = args.data_dir

    # Initialize RAG classifier (auto-detect based on environment variables)
    try:
        logger.info("Initializing RAG-based classifier...")
        from classifier import RAGActivityClassifier

        global_classifier = RAGActivityClassifier(
            model="gpt-5.2",
            fewshot=10,
            out_fewshot=5,
        )
        logger.info("✓ RAG classifier initialized successfully")
    except Exception as e:
        logger.error(f"FAILED to initialize RAG classifier: {e}", exc_info=True)
        logger.error(
            "Server cannot run without RAG classifier. Please fix the error above."
        )
        global_classifier = None
        raise  # Stop server startup if classifier fails

    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("\nServer stopped by user")
