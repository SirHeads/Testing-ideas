# Firewall Remediation Plan

This document outlines the root cause of the recent firewall configuration failures and presents a robust, system-wide solution that aligns with the Phoenix Hypervisor architecture.

## 1. Root Cause Analysis

The previous attempts to fix the firewall script failed due to a fundamental misunderstanding of how Proxmox enables container-level firewalls.

*   **Incorrect Command:** The command `pct set <vmid> --firewall 1` is not a valid Proxmox command and was the source of the "Unknown option" error.
*   **Manual Edit Errors:** Manually adding `firewall: 1` to the LXC configuration file caused parsing errors with subsequent `pct` commands.
*   **Correct Mechanism:** The firewall for an LXC container must be enabled on a per-network-interface basis (e.g., `net0`) using the command `pct set <vmid> --net0 firewall=1`.

## 2. Proposed Solution

The solution is to modify the `phoenix_hypervisor_firewall.sh` script to use the correct, idempotent Proxmox commands for enabling and disabling the firewall, while continuing to manage the specific firewall rules from the JSON configuration.

### Plan of Action:

1.  **Modify `phoenix_hypervisor_firewall.sh`:**
    *   Remove the `sed` and `echo` commands that manually edit the `.conf` file to enable/disable the firewall.
    *   Replace them with the appropriate `pct set` command:
        *   If `firewall.enabled` is `true` in the JSON, execute `pct set <ctid> --net0 firewall=1`.
        *   If `firewall.enabled` is `false` or not present, execute `pct set <ctid> --net0 firewall=0`.
    *   Retain the existing logic that reads the `firewall.rules` array from the JSON and writes the `net[i]: ...` rules to the `.conf` file.

2.  **Verification:**
    *   Re-run the orchestrator for the NGINX container (CTID 953).
    *   Confirm that the build process completes without any firewall-related errors.
    *   Inspect the `/etc/pve/lxc/953.conf` file to verify that the `net0` line now includes `,firewall=1`.
    *   Proceed with the final verification of the NGINX health checks.

This approach provides a robust, consistent, and Proxmox-native solution that is driven entirely by your "single source of truth" JSON configuration files.