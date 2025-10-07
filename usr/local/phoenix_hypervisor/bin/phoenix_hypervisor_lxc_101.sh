#!/bin/bash
#
# File: phoenix_hypervisor_lxc_101.sh
# Description: Self-contained setup for Nginx API Gateway in LXC 101. Copies configs from /tmp/phoenix_run/, generates certs if needed, and starts the service with NJS module support.

set -e

# --- Package Installation ---
echo "Updating package lists and installing Nginx and the NJS module..."
apt-get update
apt-get install -y nginx libnginx-mod-http-js

# The libnginx-mod-http-js package automatically creates a symlink in
# /etc/nginx/modules-enabled/ to load the module.

# --- Config Extraction from Tarball ---
TMP_DIR="/tmp/phoenix_run"
CONFIG_TARBALL="${TMP_DIR}/nginx_configs.tar.gz"

echo "Extracting Nginx configurations from tarball..."
tar -xzf "$CONFIG_TARBALL" -C "$TMP_DIR" || { echo "Failed to extract Nginx config tarball." >&2; exit 1; }

# --- Config Copying from Temp Dir ---
SITES_AVAILABLE_DIR="/etc/nginx/sites-available"
SITES_ENABLED_DIR="/etc/nginx/sites-enabled"
SCRIPTS_DIR="/etc/nginx/scripts"
SSL_DIR="/etc/nginx/ssl"

# Create directories
mkdir -p $SITES_AVAILABLE_DIR $SITES_ENABLED_DIR $SCRIPTS_DIR $SSL_DIR

# Copy files (assume pushed by lxc-manager.sh)
cp $TMP_DIR/sites-available/* $SITES_AVAILABLE_DIR/ || { echo "Config files missing in $TMP_DIR." >&2; exit 1; }
cp $TMP_DIR/scripts/* $SCRIPTS_DIR/ || { echo "JS script missing in $TMP_DIR." >&2; exit 1; }

# Link enabled sites
# Link the consolidated gateway configuration
ln -sf $SITES_AVAILABLE_DIR/gateway $SITES_ENABLED_DIR/gateway

# Remove default site
rm -f $SITES_ENABLED_DIR/default

# Certificate generation is now handled centrally by the phoenix-cli.
# This container will have the certs mounted by the lxc-manager.
echo "Skipping certificate generation in LXC 101."

# Remove invalid js_include from nginx.conf if present
sed -i '/js_include/d' /etc/nginx/nginx.conf

# Add NJS module configuration
echo "Adding NJS module configuration..."
cat > /etc/nginx/conf.d/njs.conf << 'EOF'
js_import http from /etc/nginx/scripts/http.js;
EOF

# Overwrite vllm_gateway to ensure JS module usage

# --- Service Management and Validation ---
echo "Testing Nginx configuration..."
nginx -t

echo "Enabling and restarting Nginx service..."
systemctl enable nginx
systemctl restart nginx

echo "Performing health check on Nginx service..."
if ! systemctl is-active --quiet nginx; then
    echo "Nginx service health check failed. The service is not running." >&2
    exit 1
fi

echo "Nginx API Gateway has been configured successfully in LXC 101."
exit 0