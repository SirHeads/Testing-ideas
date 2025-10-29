# VM Foundation Health Check Remediation Plan

## 1. Problem Analysis

The `check_vm_foundation.sh` script is failing because its DNS validation logic is based on the old, split-horizon DNS architecture. It incorrectly expects the hypervisor to resolve public hostnames to the Nginx gateway IP, while the new, simplified architecture correctly resolves them to the internal Traefik IP.

## 2. Proposed Solution

The solution is to update the `check_dns_resolution` function within the `check_vm_foundation.sh` script. The check that validates the hypervisor's DNS resolution will be modified to expect the internal Traefik IP (`10.0.0.12`), aligning it with the new, unified DNS architecture.

The updated logic will be:

1.  **Hypervisor to Service Mesh:** Check that the hypervisor resolves the service's public hostname to the **Traefik mesh IP (`10.0.0.12`)**.
2.  **Guest to Service Mesh:** This check remains the same, as it already expects the correct Traefik IP.

This change will make the foundational health check compatible with the new, more efficient DNS setup.

## 3. Implementation Plan

1.  **Update the `update_todo_list`:** Add a new item to the todo list to track the update of the `check_vm_foundation.sh` script.
2.  **Modify `check_vm_foundation.sh`:** Update the `check_dns_resolution` function to reflect the new expected IP address for the hypervisor-level check.
3.  **Execute and Verify:** Run the updated health check script against a VM (e.g., VM 1001) to confirm that it now passes.

This plan will ensure that our foundational health checks are aligned with the current state of the infrastructure.