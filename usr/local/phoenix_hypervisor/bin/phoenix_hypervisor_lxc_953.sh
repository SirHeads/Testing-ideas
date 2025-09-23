#!/bin/bash

# Exit on any error
set -e

# Update package lists and install Nginx
apt-get update
apt-get install -y nginx


# Copy the static configuration file from the host
cp /tmp/phoenix_run/vllm_gateway /etc/nginx/sites-available/vllm_gateway

# Enable the gateway
rm -f /etc/nginx/sites-enabled/vllm_gateway
ln -s /etc/nginx/sites-available/vllm_gateway /etc/nginx/sites-enabled/vllm_gateway

# Remove default site to avoid conflicts
rm -f /etc/nginx/sites-enabled/default

# Define SSL directory. This path is a mount point for a shared volume.
SSL_DIR="/etc/nginx/ssl"
CERT_FILE="$SSL_DIR/portainer.phoenix.local.crt"

# Create SSL directory
mkdir -p "$SSL_DIR"

# Check if certificates already exist. If not, generate them.
if [ ! -f "$CERT_FILE" ]; then
    echo "Generating self-signed certificates..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_DIR/n8n.phoenix.local.key" \
        -out "$SSL_DIR/n8n.phoenix.local.crt" \
        -subj "/C=US/ST=New York/L=New York/O=Phoenix/CN=n8n.phoenix.local"

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_DIR/portainer.phoenix.local.key" \
        -out "$SSL_DIR/portainer.phoenix.local.crt" \
        -subj "/C=US/ST=New York/L=New York/O=Phoenix/CN=portainer.phoenix.local"

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_DIR/ollama.phoenix.local.key" \
        -out "$SSL_DIR/ollama.phoenix.local.crt" \
        -subj "/C=US/ST=New York/L=New York/O=Phoenix/CN=ollama.phoenix.local"
else
    echo "Certificates already exist. Skipping generation."
fi

# Test Nginx configuration
nginx -t

# Enable and restart Nginx service
systemctl enable nginx
systemctl restart nginx

# Perform health check
if ! systemctl is-active --quiet nginx; then
    echo "Nginx service is not running."
    exit 1
fi

echo "Nginx has been installed and configured successfully."
exit 0