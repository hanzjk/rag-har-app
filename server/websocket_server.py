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
from datetime import datetime, timezone
from typing import Set, Optional
import websockets

from data_collector import DataCollector
from activity_predictor import ActivityPredictor

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
        logger.info(f"🟢 Client connected: {client_id} (Total: {len(connected_clients)})")
    except Exception as e:
        logger.error(f"❌ Error in handle_client setup: {e}")
        return

    sample_count = 0

    # Create per-client instances
    # Pass global classifier to predictor (may be None for mock mode)
    client_predictor = ActivityPredictor(classifier=global_classifier)
    client_collector = DataCollector(data_dir)
    mode = "RAG-based" if global_classifier else "mock"
    logger.info(f"Created {mode} predictor and collector for client: {client_id}")

    try:
        async for message in websocket:
            try:
                # Parse incoming message
                data = json.loads(message)
                message_type = data.get("type")
                timestamp = data.get("timestamp", "unknown")

                if message_type == "collect_data":
                    # Data collection mode
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

                elif message_type == "predict_activity":
                    # Activity recognition mode
                    logger.debug(
                        f"Received prediction request from {client_id} at {timestamp}"
                    )

                    # Predict activity using client-specific predictor
                    # Returns None if not at step boundary (step_size feature)
                    prediction = client_predictor.predict(data)

                    # Only send prediction if one was generated (not None)
                    if prediction is not None:
                        try:
                            # Send prediction back to client
                            await websocket.send(json.dumps(prediction))

                            # Only log non-buffering predictions
                            if prediction.get("status") != "buffering":
                                logger.info(
                                    f"Sent prediction to {client_id}: {prediction['activity']} "
                                    f"[window:{prediction.get('window_size', 0)}]"
                                )
                        except websockets.exceptions.ConnectionClosed:
                            logger.info(f"Client {client_id} disconnected while sending prediction")
                            break

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
        # Clean up per-client resources
        logger.info(f"Cleaning up resources for client: {client_id}")
        client_predictor.reset_window()
        client_collector.close_all()
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
    hostname = socket.gethostname()
    local_ip = socket.gethostbyname(hostname)
    logger.info(f"📱 Connect from mobile app using: ws://{local_ip}:{port}/ws")

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
            model="gpt-5-mini",
            fewshot=15,
            out_fewshot=10,
        )
        logger.info("✓ RAG classifier initialized successfully")
    except Exception as e:
        logger.warning(f"Could not initialize RAG classifier: {e}")
        logger.info("Using mock predictor instead")
        global_classifier = None

    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("\nServer stopped by user")
