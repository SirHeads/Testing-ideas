#!/bin/bash

# File: phoenix_hypervisor_lxc_960.sh
# Description: This script configures and launches the monitoring stack within LXC container 960.
#              It serves as the final application-specific step in the orchestration process for this container.
#              The script uses Docker Compose to deploy Prometheus for metrics collection and Grafana for
#              visualization and dashboards. This provides a comprehensive monitoring solution for the entire
#              Phoenix Hypervisor ecosystem, including host, container, and application-level metrics.
#
# Dependencies: - A running Docker service and the `docker-compose` command within the container.
#               - The `phoenix_hypervisor_common_utils.sh` script for logging functions.
#
# Inputs: - CTID (Container ID): Implicitly 960.
#
# Outputs: - A running Docker Compose stack with two services: "prometheus" and "grafana".
#          - Prometheus will be accessible on port 9090.
#          - Grafana will be accessible on port 3000.
#          - A persistent Docker volume named "grafana_data" for Grafana dashboards and settings.

# --- Script Initialization ---
# Exit immediately if a command exits with a non-zero status.
set -e

# Source common utility functions, such as log_info.
# The orchestrator ensures this script is available in the same directory.
source "phoenix_hypervisor_common_utils.sh"

log_info "Starting application setup for CTID 960: Monitoring Stack (Prometheus and Grafana)"

# --- Configuration Setup ---
# Create a dedicated directory for all monitoring-related configuration files.
mkdir -p /opt/monitoring
cd /opt/monitoring

# --- Docker Compose Configuration ---
# Create the docker-compose.yml file, which defines the monitoring services.
# This declarative approach makes the stack easy to manage, update, and replicate.
log_info "Creating Docker Compose configuration file for the monitoring stack..."
cat << EOF > docker-compose.yml
version: '3.8'

services:
  # Prometheus service for collecting and storing time-series metrics.
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    volumes:
      # Mount the Prometheus configuration file into the container.
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      # Expose the Prometheus web UI and API on port 9090.
      - "9090:9090"

  # Grafana service for visualizing metrics stored in Prometheus.
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    volumes:
      # Use a named volume to persist Grafana data (dashboards, data sources, etc.).
      - grafana_data:/var/lib/grafana
    ports:
      # Expose the Grafana web UI on port 3000.
      - "3000:3000"
    depends_on:
      - prometheus

volumes:
  # Define the named volume for Grafana data persistence.
  grafana_data:
EOF

# --- Prometheus Configuration ---
# Create the prometheus.yml file. This is the main configuration for Prometheus,
# defining scrape intervals and targets. This initial configuration scrapes Prometheus itself.
log_info "Creating Prometheus configuration file..."
cat << EOF > prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF

# --- Service Deployment ---
# Start the monitoring stack using Docker Compose in detached mode.
log_info "Docker Compose files created. Starting the monitoring stack..."
docker-compose up -d

log_info "Monitoring stack (Prometheus and Grafana) has been deployed successfully."
log_info "Prometheus is accessible at http://<container_ip>:9090"
log_info "Grafana is accessible at http://<container_ip>:3000"

exit 0