# Portainer Authentication Diagnostic Plan

This document outlines the steps to diagnose the "Invalid credentials" error occurring during the `phoenix sync all` process.

## Theory

The current hypothesis is a **state mismatch**. The Portainer database, which is stored on a persistent NFS volume (`/quickOS/vm-persistent-data/1001/portainer/data`), was likely initialized during a previous, partially successful run. This persistent database contains an admin password that is now out of sync with the password defined in `/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json`.

The `phoenix sync all` script reads the password from the config file, but Portainer validates it against its own database, leading to the authentication failure.

## Diagnostic Script

To verify this, please copy and execute the following script on your Proxmox host (`phoenix`). This script is read-only and will not make any changes to your system.

```bash
#!/bin/bash
set -x # Enable debug output to show each command being executed

echo "--- Step 1: Retrieve Portainer Credentials from Configuration ---"
# This will show us the exact username and password the sync script is using.
USERNAME=$(jq -r '.portainer_api.admin_user' /usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json)
PASSWORD=$(jq -r '.portainer_api.admin_password' /usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json)
PORTAINER_HOSTNAME="portainer.internal.thinkheads.ai"
CA_CERT_PATH="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt"

echo "Username from config: $USERNAME"
echo "Password from config (first 3 chars): ${PASSWORD:0:3}..."

echo ""
echo "--- Step 2: Attempt Manual API Authentication ---"
# This command replicates the failing API call from the portainer-manager.sh script.
# A 422 'Invalid credentials' response here will confirm the password mismatch.
AUTH_PAYLOAD=$(jq -n --arg user "$USERNAME" --arg pass "$PASSWORD" '{username: $user, password: $pass}')
curl -v -X POST \
    -H "Content-Type: application/json" \
    --cacert "$CA_CERT_PATH" \
    --resolve "${PORTAINER_HOSTNAME}:443:10.0.0.153" \
    -d "$AUTH_PAYLOAD" \
    "https://${PORTAINER_HOSTNAME}/api/auth"

echo ""
echo "--- Step 3: Inspect Portainer Server Logs ---"
# The logs inside the Portainer container might give us a more specific error.
qm guest exec 1001 -- docker logs portainer_server

echo ""
echo "--- Step 4: Check Timestamp of Persistent Data ---"
# If the timestamp of the data directory is older than the current sync run,
# it proves that pre-existing data is being used.
ls -ld /quickOS/vm-persistent-data/1001/portainer/data

set +x
```

## Next Steps

Please share the full output of this script. The results will allow us to confirm the diagnosis and proceed with the most effective solution.