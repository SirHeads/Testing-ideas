#!/bin/bash

# This script runs vLLM integration tests inside a specified LXC container.

# Check if container ID is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <container_id>"
    exit 1
fi

LXC_ID=$1
CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json"
TEST_SCRIPT_DIR="/usr/local/phoenix_hypervisor/bin/tests"
CONTAINER_TEST_DIR="/tmp"

# Check if max_model_len exists and is not null for the given container ID
if ! jq -e --arg lxc_id "$LXC_ID" '.lxc_configs[$lxc_id].vllm_max_model_len' $CONFIG_FILE > /dev/null; then
    echo "Skipping vLLM integration tests for template container CTID $LXC_ID as max_model_len is not defined."
    exit 0
fi

# Extract max_model_len from the JSON config
MAX_MODEL_LEN=$(jq --arg lxc_id "$LXC_ID" '.lxc_configs[$lxc_id].vllm_max_model_len' $CONFIG_FILE)
SERVED_MODEL_NAME=$(jq -r --arg lxc_id "$LXC_ID" '.lxc_configs[$lxc_id].vllm_served_model_name' $CONFIG_FILE)

echo "--- Running vLLM Integration Tests for CTID $LXC_ID ---"

# Copy test scripts to the container
# Create test_vllm_responsiveness.py
lxc-attach $LXC_ID -- bash -c "cat > $CONTAINER_TEST_DIR/test_vllm_responsiveness.py" <<EOF
$(cat $TEST_SCRIPT_DIR/test_vllm_responsiveness.py)
EOF

# Create test_vllm_context_window.py
lxc-attach $LXC_ID -- bash -c "cat > $CONTAINER_TEST_DIR/test_vllm_context_window.py" <<EOF
$(cat $TEST_SCRIPT_DIR/test_vllm_context_window.py)
EOF

# Install dependencies
lxc-attach $LXC_ID -- apt-get update
lxc-attach $LXC_ID -- apt-get install -y python3-openai

# Execute tests
echo "--- Running Responsiveness Test ---"
lxc-attach $LXC_ID -- bash -c "python3 $CONTAINER_TEST_DIR/test_vllm_responsiveness.py --model-name '$SERVED_MODEL_NAME'"
echo "--- Responsiveness Test Complete ---"

echo "--- Running Context Window Test ---"
lxc-attach $LXC_ID -- bash -c "python3 $CONTAINER_TEST_DIR/test_vllm_context_window.py --max-model-len $MAX_MODEL_LEN --model-name '$SERVED_MODEL_NAME'"
echo "--- Context Window Test Complete ---"

echo "--- vLLM Integration Tests for CTID $LXC_ID Complete ---"