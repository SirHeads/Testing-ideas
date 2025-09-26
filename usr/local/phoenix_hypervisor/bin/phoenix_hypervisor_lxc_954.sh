#!/bin/bash

# This script installs and runs n8n using Docker.

set -e

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" >&2
}

# Create a directory for n8n data
mkdir -p /home/node/.n8n

# Run the n8n Docker container
docker run -d --restart always --name n8n -p 5678:5678 -v /home/node/.n8n:/home/node/.n8n n8nio/n8n

log_info "n8n container started successfully."