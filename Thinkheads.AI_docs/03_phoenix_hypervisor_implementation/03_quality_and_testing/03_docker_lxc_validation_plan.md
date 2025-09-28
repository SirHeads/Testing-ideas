# Docker LXC Validation Plan

This document outlines the validation plan for the Docker and AppArmor configuration changes as detailed in the [Docker LXC Implementation Plan](Thinkheads.AI_docs/03_phoenix_hypervisor_implementation/01_implementation_plans/15_docker_lxc_implementation_plan.md).

## 1. Overview

This plan follows the user's specified testing workflow to ensure that the new AppArmor profiles are correctly applied and that Docker containers function as expected.

**Testing Workflow:**
1.  Run `phoenix_orchestrator.sh --setup-hypervisor`.
2.  Create container 902 (Docker template).
3.  Create container 910 (Portainer instance, cloned from 902).

## 2. Validation Steps

### Step 1: Host-Level Verification

After running `phoenix_orchestrator.sh --setup-hypervisor`, perform the following checks on the Proxmox host:

1.  **Check AppArmor Status:**
    *   Run the following command to verify that the `lxc-phoenix-v2` profile is loaded:
        ```bash
        aa-status
        ```
    *   **Expected Outcome:** The output should list `lxc-phoenix-v2` among the loaded profiles in enforce mode.

2.  **Check for AppArmor Denials:**
    *   Monitor the system logs for any AppArmor-related errors during the setup process.
        ```bash
        journalctl -u apparmor.service
        dmesg | grep apparmor
        ```
    *   **Expected Outcome:** There should be no "DENIED" messages related to the loading of the `lxc-phoenix-v2` profile.

### Step 2: Container 902 (Docker Template) Verification

After creating container 902, perform the following checks:

1.  **Verify Docker Storage Driver:**
    *   Execute the following command to confirm that Docker is using the `fuse-overlayfs` storage driver:
        ```bash
        pct exec 902 -- docker info | grep "Storage Driver"
        ```
    *   **Expected Outcome:** The output should be `Storage Driver: fuse-overlayfs`.

2.  **Test Basic Docker Functionality:**
    *   Run a `hello-world` container to ensure Docker is functioning correctly:
        ```bash
        pct exec 902 -- docker run hello-world
        ```
    *   **Expected Outcome:** The command should successfully pull and run the `hello-world` image, displaying the confirmation message.

3.  **Verify AppArmor Confinement:**
    *   While the container is running, monitor the host's audit log for any AppArmor denials related to container 902.
        ```bash
        tail -f /var/log/audit/audit.log | grep "lxc-902"
        ```
    *   **Expected Outcome:** There should be no `apparmor="DENIED"` messages related to Docker operations within the container.

### Step 3: Container 910 (Portainer Instance) Verification

After creating container 910, perform the following checks:

1.  **Verify Portainer Service Status:**
    *   Check if the Portainer container and service have started correctly.
        ```bash
        pct exec 910 -- docker ps
        ```
    *   **Expected Outcome:** The output should show the Portainer container in a running state.

2.  **Verify Portainer Accessibility:**
    *   Attempt to access the Portainer web UI from a browser at `http://<container-ip>:9000`.
    *   **Expected Outcome:** The Portainer login page should be accessible.

## 3. Log Analysis and Troubleshooting

If any of the validation steps fail, consult the following logs for more information:

*   **Host System Logs:**
    *   `journalctl -f`: General system logs.
    *   `dmesg -w`: Kernel ring buffer, useful for AppArmor and hardware-related issues.
    *   `/var/log/audit/audit.log`: Detailed AppArmor audit logs.

*   **Container Logs:**
    *   `pct exec <CTID> -- journalctl -f`: Logs from within the container.
    *   `pct exec <CTID> -- docker logs <container_name>`: Logs for a specific Docker container (e.g., Portainer).