# Implementation Plan: Redefining LXC Container 101 (Nginx Gateway)

## 1. Overview

This document outlines the detailed plan to redefine and redeploy LXC container 101, the Nginx gateway, as a fully self-contained and robust service. This plan is based on the consultant's report and a thorough analysis of the existing Phoenix Hypervisor architecture.

The core of this plan is to move away from a fragile, host-mounted configuration to a declarative, idempotent, and self-contained model that aligns with the core principles of the Phoenix Hypervisor project.

## 2. Proposed Changes

The following changes will be made to the Phoenix Hypervisor configuration and scripts to achieve the desired state for container 101.

### 2.1. New Definition for CTID 101 in `phoenix_lxc_configs.json`

The following JSON snippet should replace the existing definition for CTID 101 in `/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`. This new definition removes the host-mounted directories and adds the recommended options for nesting and AppArmor.

```json
"101": {
    "name": "Nginx-Phoenix",
    "memory_mb": 4096,
    "swap_mb": 512,
    "cores": 4,
    "storage_pool": "quickOS-lxc-disks",
    "storage_size_gb": 32,
    "network_config": {
        "name": "eth0",
        "bridge": "vmbr0",
        "ip": "10.0.0.153/24",
        "gw": "10.0.0.1"
    },
    "mac_address": "",
    "gpu_assignment": "none",
    "unprivileged": true,
    "portainer_role": "infrastructure",
    "clone_from_ctid": "900",
    "features": [
        "base_setup"
    ],
    "pct_options": [
        "nesting=1"
    ],
    "lxc_options": [
        "lxc.mount.auto: sys:rw",
        "lxc.apparmor.profile=unconfined"
    ],
    "application_script": "phoenix_hypervisor_lxc_101.sh",
    "firewall": {
        "enabled": true
    },
    "start_at_boot": true,
    "boot_order": 1,
    "boot_delay": 5,
    "apparmor_profile": "unconfined",
    "apparmor_manages_nesting": true
}
```

### 2.2. New Self-Contained `phoenix_hypervisor_lxc_101.sh` Script

The following script should replace the contents of `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_101.sh`. This new script is fully self-contained and will handle the entire Nginx setup process within the container.

```bash
#!/bin/bash
#
# File: phoenix_hypervisor_lxc_101.sh
# Description: Self-contained setup for Nginx API Gateway in LXC 101. Copies configs from /tmp/phoenix_run/, generates certs if needed, and starts the service.

set -e

# --- Package Installation ---
echo "Updating package lists and installing Nginx..."
apt-get update
apt-get install -y nginx

# --- Config Copying from Temp Dir ---
TMP_DIR="/tmp/phoenix_run"
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
ln -sf $SITES_AVAILABLE_DIR/vllm_gateway $SITES_ENABLED_DIR/vllm_gateway
ln -sf $SITES_AVAILABLE_DIR/n8n_proxy $SITES_ENABLED_DIR/n8n_proxy
ln -sf $SITES_AVAILABLE_DIR/ollama_proxy $SITES_ENABLED_DIR/ollama_proxy
ln -sf $SITES_AVAILABLE_DIR/portainer_proxy $SITES_ENABLED_DIR/portainer_proxy

# Remove default site
rm -f $SITES_ENABLED_DIR/default

# Generate self-signed certs if missing
if [ ! -f "$SSL_DIR/portainer.phoenix.local.crt" ]; then
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

# Include JS module
echo "js_include /etc/nginx/scripts/http.js;" >> /etc/nginx/conf.d/js_includes.conf

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
```

### 2.3. Proposed Modifications to `lxc-manager.sh`

The following `pct push` commands need to be added to the `run_application_script` function in `/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh`. These commands will copy the Nginx configuration files from the host to the container's temporary directory before the application script is executed.

The new lines should be inserted after the temporary directory is created and before the application script is copied to the container.

```bash
# --- New Robust Script Execution Model ---
# This model ensures that the script and its dependencies are available inside the container.
local temp_dir_in_container="/tmp/phoenix_run"
local common_utils_source_path="${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"
local common_utils_dest_path="${temp_dir_in_container}/phoenix_hypervisor_common_utils.sh"
local app_script_dest_path="${temp_dir_in_container}/${app_script_name}"

# 1. Create a temporary directory in the container
log_info "Creating temporary directory in container: $temp_dir_in_container"
if ! pct exec "$CTID" -- mkdir -p "$temp_dir_in_container"; then
    log_fatal "Failed to create temporary directory in container $CTID."
fi

# --- START OF NEW CODE ---
# Create subdirectories for Nginx configs
if ! pct exec "$CTID" -- mkdir -p "$temp_dir_in_container/sites-available"; then
    log_fatal "Failed to create sites-available directory in container $CTID."
fi
if ! pct exec "$CTID" -- mkdir -p "$temp_dir_in_container/scripts"; then
    log_fatal "Failed to create scripts directory in container $CTID."
fi

# Push Nginx configs to the container
log_info "Pushing Nginx configs to container $CTID..."
if ! pct push "$CTID" "${PHOENIX_BASE_DIR}/etc/nginx/sites-available/"* "$temp_dir_in_container/sites-available/"; then
    log_fatal "Failed to push Nginx sites-available to container $CTID."
fi
if ! pct push "$CTID" "${PHOENIX_BASE_DIR}/etc/nginx/scripts/"* "$temp_dir_in_container/scripts/"; then
    log_fatal "Failed to push Nginx scripts to container $CTID."
fi
# --- END OF NEW CODE ---

# 2. Copy common_utils.sh to the container
...
```

## 3. Next Steps

1.  Review and approve this plan.
2.  Switch to Code mode to implement the changes.
3.  Execute the `lxc-manager.sh` script to create the new container 101.
4.  Verify that the new container is running and that the Nginx gateway is functioning correctly.