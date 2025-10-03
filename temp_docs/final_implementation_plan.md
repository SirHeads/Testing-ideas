# Final Implementation Plan: Correcting Container 101 Configuration

This document provides the final, corrected implementation plan to align container 101 with the consultant's recommendations and resolve the startup failures.

## 1. Update `phoenix_lxc_configs.json`

The following changes must be made to the configuration for container `101` in `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`.

### 1.1. Re-enable Nesting and Update AppArmor Profile

-   **Re-enable Nesting**: Add `"nesting=1"` back to the `pct_options` array.
-   **Update AppArmor Profile**: Change the `apparmor_profile` from `"unconfined"` to `"lxc-container-default-cgns"`.
-   **Update lxc.apparmor.profile**: Change the `lxc.apparmor.profile` from `"unconfined"` to `"lxc-container-default-cgns"`.

### 1.2. Add Additional Mount Points

Add the following new mount points to the `mount_points` array:

-   `/usr/local/phoenix_hypervisor/etc/nginx/sites-enabled` -> `/etc/nginx/sites-enabled`
-   `/usr/local/phoenix_hypervisor/etc/nginx/snippets` -> `/etc/nginx/snippets`
-   `/usr/local/phoenix_hypervisor/etc/nginx/conf` -> `/etc/nginx`

## 2. Simplify `phoenix_hypervisor_lxc_101.sh`

The application script for container `101` must be simplified to remove the redundant symbolic link creation, as the `sites-enabled` directory will now be mounted directly from the host.

### Revised Script

Replace the contents of `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_101.sh` with the following:

```bash
#!/bin/bash
#
# File: phoenix_hypervisor_lxc_101.sh
# Description: This script configures and launches the Nginx API Gateway. It relies on
#              all configurations being mounted from the host.
#

set -e

# --- Package Installation ---
echo "Updating package lists and installing Nginx..."
apt-get update
apt-get install -y nginx

# --- Directory Verification ---
# Verify that the necessary directories, mounted from the host, are not empty.
SSL_DIR="/etc/nginx/ssl"
SITES_ENABLED_DIR="/etc/nginx/sites-enabled"

if [ -z "$(ls -A $SSL_DIR)" ]; then
   echo "SSL certificate directory is empty. Certificates should be mounted from the host." >&2
   exit 1
fi

if [ -z "$(ls -A $SITES_ENABLED_DIR)" ]; then
   echo "Nginx 'sites-enabled' directory is empty. Configurations should be mounted from the host." >&2
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
```

## 3. Final Todo List for `code` mode

- [ ] Apply the specified changes to the configuration for container `101` in `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`.
- [ ] Replace the contents of `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_101.sh` with the revised script.