#!/bin/bash
#
# File: phoenix_hypervisor_lxc_953.sh
# Description: This script configures and launches the Nginx API Gateway and reverse proxy within LXC container 953.
#              It serves as the final application-specific step in the orchestration process for this container.
#              The script installs Nginx, deploys a static gateway configuration, generates self-signed SSL
#              certificates for various local services, and ensures the Nginx service is running and enabled.
#              This gateway acts as a central, secure entry point for all backend AI and management services.
#
# Dependencies: - A Debian-based LXC container environment.
#               - The main `phoenix_orchestrator.sh` script, which prepares and calls this script.
#               - A pre-staged Nginx configuration file at `/tmp/phoenix_run/vllm_gateway`.
#
# Inputs: - CTID (Container ID): Implicitly 953.
#         - Nginx site configuration file (`vllm_gateway`) provided by the orchestrator.
#
# Outputs: - A running and enabled Nginx service (`systemd`).
#          - A configured Nginx reverse proxy routing traffic to backend services.
#          - Self-signed SSL certificates for `n8n.phoenix.local`, `portainer.phoenix.local`, and `ollama.phoenix.local`.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Package Installation ---
# Update the package lists to ensure access to the latest versions and install the Nginx web server.
echo "Updating package lists and installing Nginx..."
apt-get update
apt-get install -y nginx

# --- Nginx Configuration ---
# Copy the static Nginx site configuration file from a temporary location on the host.
# This file defines the reverse proxy rules, upstreams, and server blocks for the gateway.
echo "Copying Nginx gateway configuration..."
cp /tmp/phoenix_run/vllm_gateway /etc/nginx/sites-available/vllm_gateway

# Enable the new vLLM gateway configuration by creating a symbolic link.
# This is the standard practice for managing sites in Nginx.
echo "Enabling the vLLM gateway site..."
rm -f /etc/nginx/sites-enabled/vllm_gateway
ln -s /etc/nginx/sites-available/vllm_gateway /etc/nginx/sites-enabled/vllm_gateway

# Remove the default Nginx site to prevent conflicts with the custom gateway configuration.
echo "Removing default Nginx site..."
rm -f /etc/nginx/sites-enabled/default

# --- SSL Certificate Generation ---
# Define the directory where SSL certificates will be stored.
SSL_DIR="/etc/nginx/ssl"
CERT_FILE="$SSL_DIR/portainer.phoenix.local.crt"

# Create the SSL directory if it doesn't already exist.
mkdir -p "$SSL_DIR"

# Check if certificates already exist to make the script idempotent.
# If they don't exist, generate self-signed certificates for local development and testing purposes.
# These certificates enable HTTPS for various internal services proxied by Nginx.
if [ ! -f "$CERT_FILE" ]; then
    echo "Generating self-signed SSL certificates for local services..."
    
    # Generate certificate for n8n service
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_DIR/n8n.phoenix.local.key" \
        -out "$SSL_DIR/n8n.phoenix.local.crt" \
        -subj "/C=US/ST=New York/L=New York/O=Phoenix/CN=n8n.phoenix.local"

    # Generate certificate for Portainer service
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_DIR/portainer.phoenix.local.key" \
        -out "$SSL_DIR/portainer.phoenix.local.crt" \
        -subj "/C=US/ST=New York/L=New York/O=Phoenix/CN=portainer.phoenix.local"

    # Generate certificate for Ollama service
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_DIR/ollama.phoenix.local.key" \
        -out "$SSL_DIR/ollama.phoenix.local.crt" \
        -subj "/C=US/ST=New York/L=New York/O=Phoenix/CN=ollama.phoenix.local"
else
    echo "SSL certificates already exist. Skipping generation."
fi

# --- Service Management and Validation ---
# Test the Nginx configuration syntax to ensure there are no errors before restarting the service.
echo "Testing Nginx configuration..."
nginx -t

# Enable the Nginx service to start on boot and restart it to apply the new configuration.
echo "Enabling and restarting Nginx service..."
systemctl enable nginx
systemctl restart nginx

# Perform a final health check to verify that the Nginx service is active.
echo "Performing health check on Nginx service..."
if ! systemctl is-active --quiet nginx; then
    echo "Nginx service health check failed. The service is not running." >&2
    exit 1
fi

echo "Nginx API Gateway has been installed and configured successfully in LXC 953."
exit 0