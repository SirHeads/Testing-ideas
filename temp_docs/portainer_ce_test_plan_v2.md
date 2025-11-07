# Test Plan: Portainer CE Integration via phoenix-cli (v1.1)

**Objective:** Validate `phoenix-cli sync all --reset-portainer` successfully deploys:
- Portainer Server (CE)
- Portainer Agents (internally TLS-enabled)
- Endpoints registered via a direct-to-container API call using `tcp://`
- Docker stacks via the Portainer API
- Traefik-routed services

---

### Pre-requisites
1.  **Clean state on all relevant VMs:**
    ```bash
    # Example for VMs 1001 (server), 1002 & 1003 (agents)
    for vmid in 1001 1002 1003; do
      qm guest exec $vmid -- docker rm -f portainer portainer_agent 2>/dev/null || true
      qm guest exec $vmid -- docker volume rm portainer_data 2>/dev/null || true
    done
    ```
2.  `phoenix_hypervisor_config.json` correctly defines `portainer_server_vmid` and `portainer_agent_vmids`.
3.  Certificates are correctly pre-deployed to the persistent storage locations accessed by the VMs.

---

### Test Execution Steps

1.  **Full System Sync (CLI)**
    ```bash
    /usr/local/phoenix_hypervisor/bin/phoenix-cli sync all --reset-portainer
    ```
    **Expected Output:**
    ```text
    [+] Deploying Portainer Server (VM 1001)... OK
    [+] Deploying Portainer Agent (VM 1002)... OK
    [+] Deploying Portainer Agent (VM 1003)... OK
    [+] Registering agent endpoints... OK
    [+] Deploying stack: thinkheads_ai_app... OK
    [+] Sync complete. All systems operational.
    ```

2.  **Verification Steps**

    *   **2.1 Portainer Server (UI)**
        *   **Action:** Open `https://portainer.internal.thinkheads.ai`
        *   **Action:** Log in with configured credentials.
        *   **Verify:** Dashboard loads without errors.

    *   **2.2 Endpoints (Critical Fix Verification)**
        *   **Action:** Navigate to `Environments`.
        *   **Verify:** One endpoint exists for each agent VM.
        *   **Verify:** The URL for each endpoint is `tcp://<agent_ip>:9001` (e.g., `tcp://10.0.0.112:9001`). **It must not be `https://`**.
        *   **Verify:** The status for each endpoint is green ("up").

    *   **2.3 Agent Container (TLS Active Verification)**
        *   **Action:** `qm guest exec <agent_vmid> -- docker logs portainer_agent`
        *   **Verify:** Logs show `use_tls=true` and `server_port=9001`.
        *   **Verify:** No TLS handshake errors are present.

    *   **2.4 Stack Deployment Verification**
        *   **Action:** In Portainer UI, navigate to `Stacks`.
        *   **Verify:** All expected stacks are listed with a "running" status.
        *   **Verify:** All containers within each stack are in the "running" state.

    *   **2.5 Application Access Verification**
        *   **Action:** `curl -H "Host: app.internal.thinkheads.ai" http://<traefik_gateway_ip>` (or similar for your specific service)
        *   **Verify:** The application responds with a `200 OK` and expected content.

---

### Success Criteria

| Metric                  | Expected Result                               |
| ----------------------- | --------------------------------------------- |
| `phoenix-cli` exit code | 0                                             |
| Portainer UI            | Accessible and functional                     |
| Endpoints               | All present, status "up", using `tcp://` URLs |
| Agents                  | Running with `use_tls=true`, no errors        |
| Stacks                  | Deployed and all services running             |
| Applications            | Reachable and responsive via Traefik gateway  |