#!/bin/bash
#
# File: phoenix_hypervisor_lxc_101.sh
# Description: Self-contained setup for Nginx API Gateway in LXC 101. This script
#              handles the initial installation and basic configuration of Nginx.
#              The final site configuration and certificate deployment are handled
#              by the 'phoenix sync all' command to resolve timing issues.
#
# Version: 2.0.0 (Remediated)
# Author: Roo

set -e

# --- SCRIPT INITIALIZATION ---
# Use a temporary source for utils as this runs during container creation.
source "/tmp/phoenix_run/phoenix_hypervisor_common_utils.sh"

# --- User and Group Management ---
log_info "Ensuring current user is in the www-data group..."
usermod -aG www-data $(whoami)

# --- Package Installation ---
log_info "Updating package lists and installing Nginx..."
apt-get update
if ! apt-get install -y nginx-full; then
    log_fatal "Failed to install nginx-full."
fi
log_success "Nginx installed successfully."

# --- CONFIGURATION DEPLOYMENT (INITIAL SETUP ONLY) ---
temp_dir="/tmp/phoenix_run"

# --- Define Directories ---
CONF_D_DIR="/etc/nginx/conf.d"
STREAM_D_DIR="/etc/nginx/stream.d"
SSL_DIR="/etc/nginx/ssl"
ACME_WEBROOT="/var/www/html"

# --- Clean and Create Directories ---
log_info "Cleaning up and creating simplified Nginx directory structure..."
rm -rf /etc/nginx/sites-available /etc/nginx/sites-enabled
rm -f ${CONF_D_DIR}/* ${STREAM_D_DIR}/*
mkdir -p $CONF_D_DIR $STREAM_D_DIR $SSL_DIR $ACME_WEBROOT /var/cache/nginx
chown -R www-data:www-data /var/cache/nginx $ACME_WEBROOT

# --- Copy Core Nginx Configuration ---
log_info "Copying core Nginx configuration file..."
cp "${temp_dir}/nginx.conf" "/etc/nginx/nginx.conf" || log_fatal "Master nginx.conf missing in ${temp_dir}."

# --- Create a Default/Placeholder Site ---
# This ensures that Nginx can start successfully before certificates are available.
# The 'phoenix sync all' command will overwrite this with the real gateway config.
log_info "Creating a placeholder default site to ensure Nginx starts..."
cat > "$CONF_D_DIR/default.conf" <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    location / {
        return 200 'Nginx is running. Gateway configuration pending.';
        add_header Content-Type text/plain;
    }
}
EOF

# --- Service Management and Validation ---
log_info "Testing Nginx configuration with placeholder site..."
if ! nginx -t; then
    log_fatal "Nginx configuration test failed even with a placeholder site. Check nginx.conf."
fi

log_info "Enabling and restarting Nginx service..."
systemctl enable nginx
systemctl restart nginx

log_info "Performing health check on Nginx service..."
if ! systemctl is-active --quiet nginx; then
    log_fatal "Nginx service health check failed. The service is not running."
fi

log_success "Nginx has been installed and started successfully in LXC 101. Final configuration will be applied by 'phoenix sync all'."

exit 0