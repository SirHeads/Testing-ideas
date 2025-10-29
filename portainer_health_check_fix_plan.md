# Portainer Agent Deployment Plan

## 1. Problem Analysis

The successful deployment of the Portainer Agent (VM 1002) and the subsequent `phoenix sync all` command are at risk due to two critical gaps in the current configuration:

1.  **Missing DNS Record:** The `hypervisor_feature_setup_dns_server.sh` script does not create a DNS A record for `portainer-agent.internal.thinkheads.ai`. Without this, the Portainer Server (VM 1001) will be unable to resolve and connect to the agent, causing the environment registration to fail.
2.  **Inadequate Health Check:** The current `check_portainer_agent.sh` script only confirms that the agent's Docker container is running. It does not validate network reachability from the Portainer Server, which is the true measure of a successful deployment.

## 2. Proposed Solution

This plan will address both issues by enhancing the DNS generation logic and creating a more robust, network-aware health check for the Portainer agent.

### Phase 1: Declarative DNS for Portainer Agents

The DNS generation script will be updated to automatically create records for all Portainer agents defined in the VM configuration.

*   **File to Modify:** `usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh`
*   **Change:** Add a new section to the `jq` query that iterates through the VMs, selects those with a `portainer_role` of `agent`, and generates a DNS record using their `portainer_agent_hostname` and `network_config.ip`.

### Phase 2: Enhanced Portainer Agent Health Check

The health check script will be replaced with a more comprehensive validation process that confirms network connectivity and API-level health.

*   **File to Modify:** `usr/local/phoenix_hypervisor/bin/health_checks/check_portainer_agent.sh`
*   **Change:**
    *   The script will be updated to accept the VMID as an argument.
    *   It will read the VM's IP address and port from the `phoenix_vm_configs.json` file.
    *   It will perform a `curl` command from the **hypervisor** to the agent's `/ping` endpoint (`https://<agent_ip>:9001/ping`). This will validate that the agent is running, listening on the correct port, and accessible from the network.

## 3. Implementation Steps

1.  Apply the changes to `usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh`.
2.  Apply the changes to `usr/local/phoenix_hypervisor/bin/health_checks/check_portainer_agent.sh`.
3.  Run `phoenix setup` to apply the new DNS configuration.
4.  Run `phoenix create 1002` to deploy the Portainer agent.
5.  Run `phoenix sync all` to register the agent and deploy the stacks.

This plan will ensure that the Portainer agent is correctly registered in DNS and that its health is comprehensively validated, leading to a successful `phoenix sync all` operation.