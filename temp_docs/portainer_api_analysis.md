# Targeted Portainer API Analysis Plan

This document outlines the commands to diagnose the `phoenix sync all` failure by manually replicating the Portainer API workflow.

## Phase 1: Portainer API Pre-flight Checks (from Proxmox Host)

### Step 1.1: Verify DNS resolution and certificate trust for `portainer.internal.thinkheads.ai`.

This command verifies that the Portainer FQDN resolves correctly and that the TLS handshake completes successfully, which validates the entire certificate trust chain.

```bash
echo "---> Verifying DNS and Certificate Trust for Portainer..."
curl -v --cacert /mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt https://portainer.internal.thinkheads.ai/api/system/status
```

### Step 1.2: Attempt a manual API authentication to get a JWT.

This mimics the `get_portainer_jwt` function in `portainer-manager.sh`. A successful response will give us a JWT, proving the authentication part of the workflow is sound.

```bash
echo "---> Attempting Manual Portainer API Authentication..."
ADMIN_USER=$(grep 'admin_user' /usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json | awk -F'"' '{print $4}')
ADMIN_PASSWORD=$(grep 'admin_password' /usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json | awk -F'"' '{print $4}')

curl -k -X POST \
  -H "Content-Type: application/json" \
  --cacert /mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt \
  -d "{\"username\": \"$ADMIN_USER\", \"password\": \"$ADMIN_PASSWORD\"}" \
  https://portainer.internal.thinkheads.ai/api/auth
```

## Phase 2: Endpoint Creation Analysis

### Step 2.1: Verify DNS resolution and network path for the agent from within the Portainer Server VM (1001).

This is a critical test. The Portainer Server (VM 1001) must be able to resolve and reach the Portainer Agent (VM 1002) for the endpoint to be created.

```bash
echo "---> Verifying Agent DNS and Connectivity from within Portainer Server (VM 1001)..."
qm guest exec 1001 -- dig +short portainer-agent.internal.thinkheads.ai
qm guest exec 1001 -- nc -zv portainer-agent.internal.thinkheads.ai 9001
```

### Step 2.2: Manually attempt to create the Portainer endpoint via an API call.

Using the JWT from Step 1.2, we will manually send the API request to create the endpoint. This is the exact operation that is likely failing.

```bash
echo "---> Manually Attempting to Create Portainer Endpoint..."
# NOTE: You must manually replace YOUR_JWT_TOKEN_HERE with the token from Step 1.2
JWT="YOUR_JWT_TOKEN_HERE"
AGENT_NAME="dr-phoenix"
AGENT_URL="tcp://portainer-agent.internal.thinkheads.ai:9001"

curl -k -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  --cacert /mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt \
  -d "{\"Name\": \"$AGENT_NAME\", \"URL\": \"$AGENT_URL\", \"Type\": 2, \"GroupID\": 1, \"TLS\": false}" \
  https://portainer.internal.thinkheads.ai/api/endpoints
