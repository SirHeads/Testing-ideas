#!/bin/bash

# --- Source common utilities ---
# Determine script's absolute directory
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
# Source the common_utils.sh script, which provides shared functions
source "${SCRIPT_DIR}/phoenix_hypervisor_common_utils.sh"

# Set the LXC_ID
LXC_ID=958

# Update package list and install the venv package
pct exec 958 -- apt-get update
pct exec 958 -- apt-get install -y python3-venv

# Function to log messages
log_info "Starting application-specific setup for LXC $LXC_ID..."

# Create users
log_info "Creating 'rag_user' and 'qdrant' users..."
pct exec $LXC_ID -- useradd -m -s /bin/bash rag_user
pct exec $LXC_ID -- useradd -m -s /bin/bash qdrant

# Create directories
log_info "Creating directories..."
pct exec $LXC_ID -- mkdir -p /opt/rag_api
pct exec $LXC_ID -- mkdir -p /opt/qdrant/storage

# Set permissions
log_info "Setting permissions..."
pct exec $LXC_ID -- chown -R rag_user:rag_user /opt/rag_api
pct exec $LXC_ID -- chown -R qdrant:qdrant /opt/qdrant/storage

# Copy application files
log_info "Copying application files..."
pct exec 958 -- mkdir -p /opt/rag_api/rag_api
pct push 958 /usr/local/phoenix_hypervisor/src/rag-api-service/rag_api/main.py /opt/rag_api/rag_api/main.py
log_info "Creating systemd service files..."

pct exec 958 -- bash -c "cat > /etc/systemd/system/embedding_server.service" <<'EOF'
[Unit]
Description=Embedding Inference Server (vLLM)
After=network.target

[Service]
User=rag_user
WorkingDirectory=/opt/rag_api
ExecStart=/opt/rag_api/venv/bin/python -m vllm.entrypoints.api_server --model ibm-granite/granite-embedding-english-r2 --host 0.0.0.0 --port 8001
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

pct exec 958 -- bash -c "cat > /etc/systemd/system/rag_api.service" <<'EOF'
[Unit]
Description=RAG API Orchestrator (FastAPI)
After=embedding_server.service
Requires=embedding_server.service

[Service]
User=rag_user
WorkingDirectory=/opt/rag_api/rag_api
Environment="QDRANT_HOST=localhost"
Environment="EMBEDDING_URL=http://localhost:8001/v1"
ExecStart=/opt/rag_api/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create requirements.txt
log_info "Creating requirements.txt..."
echo "fastapi
uvicorn
qdrant-client
openai
pydantic
vllm
httpx" > requirements.txt
pct push $LXC_ID requirements.txt /opt/rag_api/requirements.txt
rm requirements.txt

# Create Python virtual environment
log_info "Creating Python virtual environment..."
pct exec $LXC_ID -- su - rag_user -c "python3 -m venv /opt/rag_api/venv"

# Install Python packages
log_info "Installing Python packages..."
pct exec $LXC_ID -- su - rag_user -c "source /opt/rag_api/venv/bin/activate && pip install -r /opt/rag_api/requirements.txt"


# Enable and start services
log_info "Reloading systemd..."
pct exec $LXC_ID -- systemctl daemon-reload

log_info "Enabling and starting services..."
pct exec $LXC_ID -- systemctl enable embedding_server.service
pct exec $LXC_ID -- systemctl enable rag_api.service
pct exec $LXC_ID -- systemctl start embedding_server.service
pct exec $LXC_ID -- systemctl start rag_api.service

log_info "Application-specific setup for LXC $LXC_ID complete."