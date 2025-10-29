# Phoenix Certificate Lifecycle Assessment Plan

This document outlines the step-by-step plan to diagnose the certificate lifecycle issues within the Phoenix Hypervisor environment. The goal is to trace the creation, distribution, and consumption of certificates during a full environment recreation to identify the root cause of state inconsistencies.

## Phase 1: Initial State Capture (Baseline)

Before executing any commands, we will capture the baseline state of the system.

1.  **List Initial Shared SSL Directory Contents:**
    ```bash
    ls -la /mnt/pve/quickOS/lxc-persistent-data/103/ssl
    ```

2.  **Record Initial Timestamps:**
    ```bash
    date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/phoenix_assessment_start_time.log
    ```

## Phase 2: Post-Creation Analysis (LXC 103 - Step-CA)

After `phoenix create 103` is executed:

1.  **Verify Shared SSL Directory Contents:**
    ```bash
    ls -la /mnt/pve/quickOS/lxc-persistent-data/103/ssl
    ```

2.  **Inspect Step-CA Logs:**
    ```bash
    pct exec 103 -- journalctl -u step-ca -n 50 --no-pager
    ```

3.  **Verify Root CA Certificate:**
    ```bash
    pct exec 103 -- step certificate inspect /etc/step-ca/ssl/certs/root_ca.crt
    ```

## Phase 3: Post-Creation Analysis (LXC 101 & 102)

After `phoenix create 101` and `phoenix create 102` are executed:

1.  **Inspect Nginx Logs (LXC 101):**
    ```bash
    pct exec 101 -- journalctl -u nginx -n 50 --no-pager
    ```

2.  **Verify Nginx Certificate:**
    ```bash
    pct exec 101 -- step certificate inspect /etc/nginx/ssl/nginx.crt
    ```

3.  **Inspect Traefik Logs (LXC 102):**
    ```bash
    pct exec 102 -- journalctl -u traefik -n 50 --no-pager
    ```

4.  **Verify Traefik Certificate:**
    ```bash
    pct exec 102 -- step certificate inspect /etc/traefik/ssl/traefik.crt
    ```

## Phase 4: Post-Creation Analysis (VM 1001 & 1002)

After `phoenix create 1001` and `phoenix create 1002` are executed:

1.  **Verify Trusted CA in VM 1001:**
    ```bash
    qm guest exec 1001 -- ls -la /usr/local/share/ca-certificates/
    ```

2.  **Inspect Portainer Server Logs (VM 1001):**
    ```bash
    qm guest exec 1001 -- docker logs portainer_server
    ```

3.  **Verify Trusted CA in VM 1002:**
    ```bash
    qm guest exec 1002 -- ls -la /usr/local/share/ca-certificates/
    ```

4.  **Inspect Portainer Agent Logs (VM 1002):**
    ```bash
    qm guest exec 1002 -- docker logs portainer_agent
    ```

## Phase 5: Final State Verification (Post `phoenix sync all`)

After `phoenix sync all` is executed:

1.  **Check Portainer API Status:**
    ```bash
    curl -s --cacert /mnt/pve/quickOS/lxc-persistent-data/103/ssl/certs/root_ca.crt https://portainer.phoenix.thinkheads.ai/api/system/status
    ```

2.  **Check Portainer Endpoints:**
    ```bash
    JWT=$(source /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh && source /usr/local/phoenix_hypervisor/bin/managers/portainer-manager.sh && get_portainer_jwt) && \
    PORTAINER_HOSTNAME=$(source /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh && get_global_config_value '.portainer_api.portainer_hostname') && \
    PORTAINER_URL="https://${PORTAINER_HOSTNAME}:443" && \
    CA_CERT_PATH="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/certs/root_ca.crt" && \
    curl -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}" | jq '.'
    ```

3.  **Record End Timestamps:**
    ```bash
    date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/phoenix_assessment_end_time.log