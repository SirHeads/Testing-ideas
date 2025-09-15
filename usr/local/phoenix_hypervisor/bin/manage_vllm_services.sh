#!/bin/bash

# A simple script to manage vLLM services

# It is assumed that the vllm services are started with a command like:
# python -m vllm.entrypoints.openai.api_server --model <model_name> --host 0.0.0.0 --port <port>

EMBEDDING_MODEL_NAME="text-embedding-ada-002" # Replace with your actual model
QWEN_MODEL_NAME="qwen-1.5-7b-chat" # Replace with your actual model

EMBEDDING_PORT=8000
QWEN_PORT=8001

start() {
    echo "Starting vLLM services..."
    echo "Starting embedding model ($EMBEDDING_MODEL_NAME) on port $EMBEDDING_PORT"
    #nohup python -m vllm.entrypoints.openai.api_server --model "$EMBEDDING_MODEL_NAME" --host 0.0.0.0 --port $EMBEDDING_PORT &> /var/log/vllm_embedding.log &
    echo "Starting Qwen model ($QWEN_MODEL_NAME) on port $QWEN_PORT"
    #nohup python -m vllm.entrypoints.openai.api_server --model "$QWEN_MODEL_NAME" --host 0.0.0.0 --port $QWEN_PORT &> /var/log/vllm_qwen.log &
    echo "Services started (commands are commented out for safety)."
}

stop() {
    echo "Stopping vLLM services..."
    pkill -f "vllm.entrypoints.openai.api_server.*--port $EMBEDDING_PORT"
    pkill -f "vllm.entrypoints.openai.api_server.*--port $QWEN_PORT"
    echo "Services stopped."
}

status() {
    echo "Checking status of vLLM services..."
    echo "--- Embedding Service (Port $EMBEDDING_PORT) ---"
    pgrep -f "vllm.entrypoints.openai.api_server.*--port $EMBEDDING_PORT" || echo "Not running"
    echo "--- Qwen Service (Port $QWEN_PORT) ---"
    pgrep -f "vllm.entrypoints.openai.api_server.*--port $QWEN_PORT" || echo "Not running"
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
esac