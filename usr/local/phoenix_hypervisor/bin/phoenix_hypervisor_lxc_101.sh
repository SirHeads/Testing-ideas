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

# --- Function to generate Nginx certificates ---
generate_nginx_certs() {
    set -x # Enable verbose logging for this function
    echo "Generating Nginx server certificates for internal_traefik_proxy..."
    local NGINX_CERT_DIR="/etc/nginx/ssl" # Certificates will be stored directly in the container's Nginx SSL directory
    local NGINX_HOSTNAME="*.internal.thinkheads.ai" # Wildcard domain for internal Traefik proxy
    local CA_URL="https://ca.internal.thinkheads.ai:9000"
    local CA_FINGERPRINT=""
    local MAX_RETRIES=10
    local RETRY_DELAY=10
    local attempt=1

    # Ensure step-cli is installed inside the container
    if ! command -v step &> /dev/null; then
        echo "INFO: step-cli not found in LXC 101. Installing..."
        echo "INFO: Installing step-cli via Smallstep APT repository..."
        # Add Smallstep GPG key
        curl -fsSL https://packages.smallstep.com/keys/apt/repo-signing-key.gpg -o /etc/apt/trusted.gpg.d/smallstep.asc || { echo "FATAL: Failed to download Smallstep GPG key." >&2; exit 1; }
        # Add Smallstep APT repository
        echo 'deb [signed-by=/etc/apt/trusted.gpg.d/smallstep.asc] https://packages.smallstep.com/stable/debian debs main' | tee /etc/apt/sources.list.d/smallstep.list > /dev/null || { echo "FATAL: Failed to add Smallstep APT repository." >&2; exit 1; }
        # Update package lists and install step-cli
        apt-get update && apt-get install -y step-cli || { echo "FATAL: Failed to install step-cli from APT repository." >&2; exit 1; }
        hash -r # Clear the command hash table
        # Re-check if step-cli is now available after installation
        if ! command -v step &> /dev/null; then
            echo "FATAL: Failed to install step-cli in LXC 101, or it's not in PATH after installation." >&2
            exit 1
        fi
        echo "INFO: step-cli installed successfully in LXC 101."
    fi

    # Wait for Step CA (LXC 103) to be reachable and responsive
    echo "Waiting for Step CA (LXC 103 at 10.0.0.10) to be reachable..."
    local CA_IP="10.0.0.10"
    while ! ping -c 1 "$CA_IP" > /dev/null 2>&1 && [ "$attempt" -le "$MAX_RETRIES" ]; do
        echo "Attempt $attempt/$MAX_RETRIES: Ping to Step CA ($CA_IP) failed. Retrying in $RETRY_DELAY seconds..."
        sleep "$RETRY_DELAY"
        attempt=$((attempt + 1))
    done
    if [ "$attempt" -gt "$MAX_RETRIES" ]; then
        echo "FATAL: Step CA ($CA_IP) is not reachable after $MAX_RETRIES attempts. Cannot generate certificates." >&2
        exit 1
    fi
    echo "Step CA ($CA_IP) is reachable."

    # Add CA hostname to /etc/hosts for internal resolution
    echo "INFO: Adding 'ca.internal.thinkheads.ai' to /etc/hosts..."
    if ! grep -q "ca.internal.thinkheads.ai" /etc/hosts; then
        echo "${CA_IP} ca.internal.thinkheads.ai" >> /etc/hosts || { echo "FATAL: Failed to add CA entry to /etc/hosts." >&2; exit 1; }
    fi
    echo "INFO: CA entry added to /etc/hosts."

    # Retrieve CA fingerprint from the mounted root certificate
    local ROOT_CA_CERT_PATH="${NGINX_CERT_DIR}/phoenix_ca.crt" # Assuming phoenix_ca.crt is the root CA cert
    echo "INFO: Checking for root CA certificate at $ROOT_CA_CERT_PATH..."
    if [ ! -f "$ROOT_CA_CERT_PATH" ]; then
        echo "FATAL: Root CA certificate not found at $ROOT_CA_CERT_PATH. Cannot retrieve fingerprint." >&2
        exit 1
    fi
    echo "INFO: Root CA certificate found. Retrieving fingerprint..."
    CA_FINGERPRINT=$(step certificate fingerprint "$ROOT_CA_CERT_PATH" 2>/dev/null)
    if [ -z "$CA_FINGERPRINT" ]; then
        echo "FATAL: Failed to retrieve fingerprint from $ROOT_CA_CERT_PATH." >&2
        exit 1
    fi
    echo "INFO: Retrieved CA Fingerprint: $CA_FINGERPRINT"

    # Add the locally mounted root CA certificate to the trust store
    echo "INFO: Adding locally mounted root CA certificate to trust store..."
    if ! STEPDEBUG=1 step certificate install "${ROOT_CA_CERT_PATH}"; then
        echo "FATAL: Failed to install locally mounted root CA certificate into trust store." >&2
        exit 1
    fi
    echo "INFO: Locally mounted root CA certificate added to trust store successfully."

    # Bootstrap the step CLI with the CA's URL and fingerprint
    echo "INFO: Bootstrapping step CLI with CA information..."
    echo "INFO: Testing connectivity to Step CA at $CA_URL..."
    if ! curl -vk --cacert "$ROOT_CA_CERT_PATH" "$CA_URL/health" > /dev/null 2>&1; then
        echo "FATAL: Failed to connect to Step CA at $CA_URL. Please check network connectivity and CA service status." >&2
        exit 1
    fi
    echo "INFO: Successfully connected to Step CA."

    if ! STEPDEBUG=1 step ca bootstrap --ca-url "$CA_URL" --fingerprint "$CA_FINGERPRINT"; then
        echo "FATAL: Failed to bootstrap step CLI with CA information." >&2
        exit 1
    fi
    echo "INFO: step CLI bootstrapped successfully."

    # Generate the certificate and key
    local cert_cmd=(
        step ca certificate "$NGINX_HOSTNAME"
        "${NGINX_CERT_DIR}/internal_traefik_proxy.crt"
        "${NGINX_CERT_DIR}/internal_traefik_proxy.key"
        --password-file "${NGINX_CERT_DIR}/ca_password.txt" # Use the mounted password file
        --provisioner "admin@thinkheads.ai"
        --force
    )
    if ! "${cert_cmd[@]}"; then
        echo "FATAL: Failed to generate Nginx server certificate for $NGINX_HOSTNAME." >&2
        exit 1
    fi

    echo "Nginx server certificates generated successfully."
}

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
cp "$TMP_DIR/sites-available/gateway" "$SITES_AVAILABLE_DIR/gateway" || { echo "Config file gateway missing in $TMP_DIR." >&2; exit 1; }
cp "$TMP_DIR/scripts/http.js" "$SCRIPTS_DIR/http.js" || { echo "JS script missing in $TMP_DIR." >&2; exit 1; }
cp "$TMP_DIR/snippets/acme_challenge.conf" "$SNIPPETS_DIR/acme_challenge.conf" || { echo "ACME snippet missing in $TMP_DIR." >&2; exit 1; }
cp "$TMP_DIR/nginx.conf" "/etc/nginx/nginx.conf" || { echo "Master nginx.conf missing in $TMP_DIR." >&2; exit 1; }

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

# --- Certificate Generation and Trust ---
generate_nginx_certs
echo "Installing Step-CA root certificate into system trust store..."
cp /etc/nginx/ssl/phoenix_ca.crt /usr/local/share/ca-certificates/phoenix_ca.crt
update-ca-certificates
echo "Step-CA root certificate installed."
chmod 600 "/etc/nginx/ssl/internal_traefik_proxy.key" || { echo "FATAL: Failed to set permissions for Nginx private key." >&2; exit 1; }


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