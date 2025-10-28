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
    # This function is now deprecated. The `trusted_ca` feature script
    # is responsible for installing the root CA certificate into the
    # system's trust store. This ensures a single source of truth and
    # avoids redundant or conflicting logic.
    echo "CA trust is now managed by the 'trusted_ca' feature. Skipping redundant setup."
}
# --- User and Group Management ---
echo "Ensuring current user is in the www-data group..."
usermod -aG www-data $(whoami)

# --- Package Installation ---
echo "Updating package lists and installing Nginx..."
apt-get update

# Install Nginx and the NJS module with robust error handling
if ! apt-get install -y nginx-full; then
    echo "FATAL: Failed to install nginx-full." >&2
    exit 1
fi
echo "Nginx installed successfully."

# --- CONFIGURATION DEPLOYMENT ---
temp_dir="/tmp/phoenix_run"

# --- Define Directories ---
SITES_AVAILABLE_DIR="/etc/nginx/sites-available"
SITES_ENABLED_DIR="/etc/nginx/sites-enabled"
STREAM_CONF_DIR="/etc/nginx/stream.d"

# --- Clean and Create Directories ---
echo "Cleaning up and creating Nginx directory structure..."
rm -rf $SITES_AVAILABLE_DIR $SITES_ENABLED_DIR $STREAM_CONF_DIR /etc/nginx/conf.d/*
mkdir -p $SITES_AVAILABLE_DIR $SITES_ENABLED_DIR $STREAM_CONF_DIR /var/cache/nginx
chown -R www-data:www-data /var/cache/nginx

# --- Copy Core Configuration Files ---
echo "Copying core Nginx configuration files..."
cp "${temp_dir}/nginx.conf" "/etc/nginx/nginx.conf" || { echo "Master nginx.conf missing in ${temp_dir}." >&2; exit 1; }
cp "${temp_dir}/sites-available/gateway" "$SITES_AVAILABLE_DIR/gateway" || { echo "Generated gateway config file missing in ${temp_dir}." >&2; exit 1; }
cp "${temp_dir}/stream.d/stream-gateway.conf" "$STREAM_CONF_DIR/stream-gateway.conf" || { echo "Generated stream gateway config file missing in ${temp_dir}." >&2; exit 1; }

# --- Link Enabled Site ---
echo "Enabling the main gateway site..."
ln -sf "$SITES_AVAILABLE_DIR/gateway" "$SITES_ENABLED_DIR/gateway"

# --- Certificate Trust and Generation ---
# This is no longer needed as Nginx is now a TCP proxy and does not terminate TLS.
# Traefik will handle all certificate management.
ensure_ca_trust

# --- Certificate Generation ---
echo "Bootstrapping Step CLI and generating Nginx certificate..."
# Bootstrap the step CLI with the CA URL and fingerprint from the trusted CA feature
step ca bootstrap --ca-url "https://ca.internal.thinkheads.ai:9000" --fingerprint "$(step certificate fingerprint /usr/local/share/ca-certificates/phoenix_root_ca.crt)"

# Generate the certificate
step ca certificate phoenix.thinkheads.ai /etc/nginx/ssl/phoenix.thinkheads.ai.crt /etc/nginx/ssl/phoenix.thinkheads.ai.key --provisioner "admin@thinkheads.ai" --provisioner-password-file "/etc/step-ca/ssl/provisioner_password.txt" --force

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