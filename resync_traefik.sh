#!/bin/bash
#
# This script regenerates the Traefik dynamic configuration and restarts the
# Traefik service to make it aware of manually deployed services like Qdrant.
# Run this script on the Proxmox host.

set -e

echo "--- Starting Traefik Resync ---"

# 1. Regenerate the dynamic configuration file
echo "[1/2] Regenerating Traefik dynamic configuration..."
/usr/local/phoenix_hypervisor/bin/generate_traefik_config.sh

# 2. Restart the Traefik service inside the LXC container to apply the new config
echo "[2/2] Restarting Traefik service in LXC 102..."
pct exec 102 -- systemctl restart traefik

echo "--- Traefik Resync Complete ---"
echo "The new routing rules should now be active."
