#!/bin/bash
#
# File: phoenix_hypervisor_lxc_101.sh
# Description: Self-contained setup for Nginx API Gateway in LXC 101. Copies configs from /tmp/phoenix_run/, generates certs if needed, and starts the service with NJS module support.
#
# Arguments:
#   $1 - The CTID of the container (expected to be 101).
#
# Dependencies:
#   - phoenix_hypervisor_common_utils.sh: For logging and utility functions.
#   - step-cli and step-ca binaries (installed by feature_install_step_ca.sh).
#
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

set -e

# --- SCRIPT INITIALIZATION ---
source "/tmp/phoenix_run/phoenix_hypervisor_common_utils.sh"

# --- Function to ensure Nginx certificates are trusted ---
ensure_ca_trust() {
    echo "Ensuring the system trusts the Phoenix CA..."
    local ROOT_CA_CERT_PATH="/etc/step-ca/ssl/phoenix_ca.crt"
    local TRUST_STORE_PATH="/usr/local/share/ca-certificates/phoenix_ca.crt"

    # Wait for the root CA to become available via the mount point
    local attempt=1
    local max_attempts=12
    while [ ! -f "$ROOT_CA_CERT_PATH" ]; do
        if [ "$attempt" -ge "$max_attempts" ]; then
            echo "FATAL: Root CA certificate not found at $ROOT_CA_CERT_PATH after waiting." >&2
            exit 1
        fi
        echo "Waiting for root CA certificate at $ROOT_CA_CERT_PATH... (Attempt $attempt/$max_attempts)"
        sleep 10
        attempt=$((attempt + 1))
    done

    # Copy the certificate to the trust store and update the system
    cp "$ROOT_CA_CERT_PATH" "$TRUST_STORE_PATH" || { echo "FATAL: Failed to copy root CA to trust store." >&2; exit 1; }
    update-ca-certificates || { echo "FATAL: Failed to update CA certificates." >&2; exit 1; }
    echo "Phoenix CA is now trusted by the system."
}

# --- Function to generate Nginx certificate if missing ---
generate_nginx_cert() {
    echo "Checking for Nginx SSL certificate..."
    local CERT_PATH="/etc/step-ca/ssl/phoenix.thinkheads.ai.crt"
    local KEY_PATH="/etc/step-ca/ssl/phoenix.thinkheads.ai.key"
    local PROVISIONER_PASSWORD_FILE="/etc/step-ca/ssl/provisioner_password.txt"

    echo "Forcing regeneration of Nginx SSL certificate to ensure validity."
    rm -f "$CERT_PATH" "$KEY_PATH"

    # 1. Generate Certificate
    # We must provide the CA URL and the root cert path for this online request.
    local DOMAIN_NAME="*.phoenix.thinkheads.ai"
    local CA_URL="https://ca.internal.thinkheads.ai:9000"
    local ROOT_CA_CERT_PATH="/etc/step-ca/ssl/phoenix_root_ca.crt"
    if ! step ca certificate "$DOMAIN_NAME" "$CERT_PATH" "$KEY_PATH" --provisioner "admin@thinkheads.ai" --password-file "$PROVISIONER_PASSWORD_FILE" --force --ca-url "$CA_URL" --root "$ROOT_CA_CERT_PATH"; then
        echo "FATAL: Failed to generate certificate for Nginx." >&2
        exit 1
    fi

    echo "Successfully generated Nginx SSL certificate."
}

# --- Package Installation ---
echo "Updating package lists and installing Nginx with the NJS module..."
apt-get update

# Install Nginx and the NJS module with robust error handling
if ! apt-get install -y nginx libnginx-mod-http-js; then
    echo "FATAL: Failed to install nginx and libnginx-mod-http-js." >&2
    exit 1
fi

# Verify that the NJS module was installed correctly
MODULE_PATH="/usr/lib/nginx/modules/ngx_http_js_module.so"
if [ ! -f "$MODULE_PATH" ]; then
    echo "FATAL: NJS module not found at $MODULE_PATH after installation." >&2
    exit 1
fi

echo "Nginx and NJS module installed and verified successfully."

# The libnginx-mod-http-js package automatically creates a symlink in
# /etc/nginx/modules-enabled/ to load the module.

# --- DYNAMIC CONFIGURATION GENERATION ---
echo "Unpacking Nginx configuration files from host..."
temp_dir="/tmp/phoenix_run"
tarball_path="${temp_dir}/nginx_configs.tar.gz"
if [ ! -f "$tarball_path" ]; then
    echo "FATAL: Nginx configuration tarball not found at $tarball_path." >&2
    exit 1
fi
if ! tar -xzf "$tarball_path" -C "$temp_dir"; then
    echo "FATAL: Failed to unpack Nginx configuration tarball." >&2
    exit 1
fi
echo "Nginx configuration files unpacked successfully."

# --- Define Directories ---
SITES_AVAILABLE_DIR="/etc/nginx/sites-available"
SITES_ENABLED_DIR="/etc/nginx/sites-enabled"
SCRIPTS_DIR="/etc/nginx/scripts"
SNIPPETS_DIR="/etc/nginx/snippets"
SSL_DIR="/etc/nginx/ssl"
STREAM_CONF_DIR="/etc/nginx/stream.d"

# --- Clean and Create Directories ---
echo "Cleaning up and creating Nginx directory structure..."
rm -rf $SITES_AVAILABLE_DIR $SITES_ENABLED_DIR $SCRIPTS_DIR $SNIPPETS_DIR $STREAM_CONF_DIR /etc/nginx/conf.d/*
mkdir -p $SITES_AVAILABLE_DIR $SITES_ENABLED_DIR $SCRIPTS_DIR $SNIPPETS_DIR $SSL_DIR $STREAM_CONF_DIR /var/cache/nginx
chown -R www-data:www-data /var/cache/nginx

# --- Copy Core Configuration Files ---
echo "Copying core Nginx configuration files..."
# The gateway file is now generated dynamically, so we copy it from its source
# Copy other static files from the temporary run directory
cp "${temp_dir}/sites-available/gateway" "$SITES_AVAILABLE_DIR/gateway" || { echo "Generated gateway config file missing in ${temp_dir}." >&2; exit 1; }
cp "${temp_dir}/scripts/http.js" "$SCRIPTS_DIR/http.js" || { echo "JS script missing in ${temp_dir}." >&2; exit 1; }
cp "${temp_dir}/snippets/acme_challenge.conf" "$SNIPPETS_DIR/acme_challenge.conf" || { echo "ACME snippet missing in ${temp_dir}." >&2; exit 1; }
cp "${temp_dir}/nginx.conf" "/etc/nginx/nginx.conf" || { echo "Master nginx.conf missing in ${temp_dir}." >&2; exit 1; }

# --- Create Stream Gateway Configuration ---
echo "Creating Nginx stream gateway configuration..."
cat > "$STREAM_CONF_DIR/stream-gateway.conf" << 'EOF'
server {
    listen 9001;
    proxy_pass 10.0.0.102:9001;
}
EOF

# --- Link Enabled Site ---
echo "Enabling the main gateway site..."
ln -sf "$SITES_AVAILABLE_DIR/gateway" "$SITES_ENABLED_DIR/gateway"

# --- Certificate Trust ---
ensure_ca_trust
generate_nginx_cert


# Overwrite vllm_gateway to ensure JS module usage. This is now handled by copying the file directly.

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

# DNS update is now handled by lxc-manager.sh

exit 0