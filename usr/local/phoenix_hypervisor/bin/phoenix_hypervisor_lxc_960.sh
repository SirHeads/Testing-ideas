#!/bin/bash

# Exit on any error
set -e

# Source common utilities
# The orchestrator will place the common_utils.sh script in the same directory.
source "phoenix_hypervisor_common_utils.sh"

log_info "Starting application setup for CTID 960: Monitoring Stack"

# Create a directory for the monitoring stack configuration
mkdir -p /opt/monitoring
cd /opt/monitoring

# Create a docker-compose.yml file
cat << EOF > docker-compose.yml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - "3000:3000"
    depends_on:
      - prometheus

volumes:
  grafana_data:
EOF

# Create a prometheus.yml file
cat << EOF > prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF

log_info "Docker Compose files created. Starting the monitoring stack..."

# Start the Docker containers
docker-compose up -d

log_info "Monitoring stack (Prometheus and Grafana) has been deployed successfully."

exit 0