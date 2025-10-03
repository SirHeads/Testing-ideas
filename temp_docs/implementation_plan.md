# Implementation Plan: Declarative LXC Volume Mounts

This document provides the specific code and configuration changes required to implement the declarative shared volume mounting feature for LXC containers.

## 1. Update `phoenix_lxc_configs.json`

Add the following `mount_points` array to the configuration for container `101`. This will declaratively link the required Nginx host directories to the container.

```json
"mount_points": [
    {
        "host_path": "/usr/local/phoenix_hypervisor/etc/nginx/sites-available",
        "container_path": "/etc/nginx/sites-available"
    },
    {
        "host_path": "/mnt/pve/quickOS/shared-prod-data/ssl",
        "container_path": "/etc/nginx/ssl"
    },
    {
        "host_path": "/mnt/pve/quickOS/shared-prod-data/logs/nginx",
        "container_path": "/logs/nginx"
    }
],
```

## 2. Add `apply_mount_points` Function to `lxc-manager.sh`

Add the following new function to `usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh`. It should be placed after the `apply_dedicated_volumes` function.

```bash
# =====================================================================================
# Function: apply_mount_points
# Description: Mounts shared host directories into the container as defined in the
#              container's specific configuration.
# =====================================================================================
apply_mount_points() {
    local CTID="$1"
    log_info "Applying host path mount points for CTID: $CTID..."

    local mounts
    mounts=$(jq_get_value "$CTID" ".mount_points // [] | .[]" || echo "")
    if [ -z "$mounts" ]; then
        log_info "No host path mount points to apply for CTID $CTID."
        return 0
    fi

    local volume_index=0
    # Find the next available mount point index
    while pct config "$CTID" | grep -q "mp${volume_index}:"; do
        volume_index=$((volume_index + 1))
    done

    for mount_config in $(echo "$mounts" | jq -c '.'); do
        local host_path=$(echo "$mount_config" | jq -r '.host_path')
        local container_path=$(echo "$mount_config" | jq -r '.container_path')
        local mount_id="mp${volume_index}"
        local mount_string="${host_path},mp=${container_path}"

        # Idempotency Check
        if ! pct config "$CTID" | grep -q "mp.*: ${mount_string}"; then
            log_info "Applying mount: ${host_path} -> ${container_path}"
            run_pct_command set "$CTID" --"${mount_id}" "$mount_string" || log_fatal "Failed to apply mount."
            volume_index=$((volume_index + 1))
        else
            log_info "Mount point ${host_path} -> ${container_path} already configured."
        fi
    done
}
```

## 3. Integrate `apply_mount_points` into the Orchestration Workflow

Modify the `main_lxc_orchestrator` function in `usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh` to call the new function.

```diff
--- a/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
+++ b/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
@@ -1076,6 +1076,7 @@
                 
                 apply_configurations "$ctid"
                 apply_zfs_volumes "$ctid"
+                apply_mount_points "$ctid"
                 apply_dedicated_volumes "$ctid"
                 ensure_container_disk_size "$ctid"
                 
```

## 4. Revise `phoenix_hypervisor_lxc_101.sh`

The application script for container `101` must be modified to use the centrally managed configurations and certificates provided by the new mount points. The self-signed certificate generation logic will be removed.

```bash
#!/bin/bash
#
# File: phoenix_hypervisor_lxc_101.sh
# Description: This script configures and launches the Nginx API Gateway and reverse proxy within LXC container 101.
#              It now relies on centrally managed configuration files and SSL certificates mounted from the hypervisor host.
#

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Package Installation ---
echo "Updating package lists and installing Nginx..."
apt-get update
apt-get install -y nginx

# --- Nginx Configuration ---
# The Nginx site configurations are now mounted directly from the host.
# This script will ensure the correct symlinks are in place.
echo "Enabling Nginx sites from mounted configuration..."
ln -s /etc/nginx/sites-available/vllm_gateway /etc/nginx/sites-enabled/vllm_gateway
ln -s /etc/nginx/sites-available/n8n_proxy /etc/nginx/sites-enabled/n8n_proxy
ln -s /etc/nginx/sites-available/ollama_proxy /etc/nginx/sites-enabled/ollama_proxy
ln -s /etc/nginx/sites-available/portainer_proxy /etc/nginx/sites-enabled/portainer_proxy
ln -s /etc/nginx/sites-available/vllm_proxy /etc/nginx/sites-enabled/vllm_proxy


# Remove the default Nginx site to prevent conflicts.
echo "Removing default Nginx site..."
rm -f /etc/nginx/sites-enabled/default

# --- SSL Certificates ---
# SSL certificates are now mounted from the host. This script no longer generates them.
# It will, however, verify that the certificate directory is not empty.
SSL_DIR="/etc/nginx/ssl"
if [ -z "$(ls -A $SSL_DIR)" ]; then
   echo "SSL certificate directory is empty. Certificates should be mounted from the host." >&2
   exit 1
fi

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

echo "Nginx API Gateway has been configured successfully in LXC 101 using mounted configurations."
exit 0