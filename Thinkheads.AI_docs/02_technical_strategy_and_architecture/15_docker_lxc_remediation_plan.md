# Architectural Plan: Docker in Unprivileged LXC Remediation

## 1. High-Level Summary

### 1.1. The Problem

Running Docker within unprivileged LXC containers presents significant security and stability challenges. The default `vfs` storage driver is inefficient and not recommended for production, while AppArmor confinement requires careful configuration to avoid blocking legitimate Docker operations. Our current implementation, while functional, can be improved to align with security best practices, enhance performance, and increase maintainability.

### 1.2. The Proposed Solution

This document outlines an architectural plan to implement a consultant's recommendations for running Docker securely and efficiently in unprivileged LXC containers. The solution is a multi-faceted approach that involves:

1.  **Replacing the Docker Storage Driver:** Migrating from the `vfs` driver to `fuse-overlayfs` to improve performance and stability.
2.  **Refining the AppArmor Profile:** Enhancing the `lxc-phoenix-v2` profile to provide robust security confinement without interfering with `fuse-overlayfs` or other necessary Docker functions.
3.  **Optimizing the Installation Script:** Streamlining the `phoenix_hypervisor_feature_install_docker.sh` script to be more robust, idempotent, and maintainable.
4.  **Configuring Host AppArmor Tunables:** Ensuring the Proxmox host is correctly configured to support nested AppArmor profiles, which is essential for the container-level policies to function correctly.

This plan is designed to be implemented declaratively through our existing `phoenix_orchestrator.sh` framework, ensuring changes are automated, repeatable, and consistent.

## 2. Detailed Implementation Plan

### Step 1: Implement `fuse-overlayfs` Storage Driver

*   **Why This Is Necessary:** The `fuse-overlayfs` driver allows unprivileged users to leverage overlay filesystem technology, which is significantly more efficient for container image layering than the default `vfs` driver. This change will reduce disk I/O, decrease container startup times, and provide a more stable foundation for our Dockerized services.

*   **Implementation Steps:**
    1.  **Modify Docker Installation Script:** The `usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_docker.sh` script will be updated.
    2.  **Install Dependency:** Add a command to the script to install the `fuse-overlayfs` package within the container (`apt-get install -y fuse-overlayfs`).
    3.  **Configure Docker Daemon:** The script will create the file `/etc/docker/daemon.json` inside the container with the following content to explicitly set the storage driver:
        ```json
        {
          "storage-driver": "fuse-overlayfs"
        }
        ```
    4.  **Restart Docker Service:** Ensure the Docker service is restarted after the configuration is applied to load the new driver.

*   **Verification:**
    *   After a container with the `docker` feature is provisioned, execute `pct exec <CTID> -- docker info | grep "Storage Driver"` and confirm the output is `fuse-overlayfs`.

### Step 2: Refine the `lxc-phoenix-v2` AppArmor Profile

*   **Why This Is Necessary:** A properly configured AppArmor profile is our primary defense against container escapes. The existing `lxc-phoenix-v2` profile must be updated to explicitly allow the operations required by `fuse-overlayfs` while denying unnecessary privileges. This follows the principle of least privilege, enhancing our security posture.

*   **Implementation Steps:**
    1.  **Edit the Profile:** The profile at `usr/local/phoenix_hypervisor/etc/apparmor/lxc-phoenix-v2` will be modified.
    2.  **Add Mount Rules:** Add rules to permit the `fuse-overlayfs` driver to perform its necessary mount operations. This will include rules similar to:
        ```
        # Allow fuse-overlayfs mounts
        mount fstype=fuse.fuse-overlayfs -> /var/lib/docker/fuse-overlayfs/**,
        ```
    3.  **Automated Deployment:** The `phoenix_orchestrator.sh` script already handles the copying of this profile to `/etc/apparmor.d/` and reloading the AppArmor service. No changes are needed for this part of the process.

*   **Verification:**
    *   After provisioning a container, monitor the host's audit logs (`/var/log/audit/audit.log` or `dmesg`) for any `apparmor="DENIED"` messages related to Docker or `fuse-overlayfs`. The absence of such messages during normal Docker operations indicates success.

### Step 3: Optimize Docker Installation Script

*   **Why This Is Necessary:** Consolidating all Docker-related setup into a single, idempotent script improves maintainability and reduces the risk of configuration drift. A robust script ensures that every container is provisioned identically and that the process can be re-run without causing errors.

*   **Implementation Steps:**
    1.  **Consolidate Logic:** The logic from Step 1 (installing `fuse-overlayfs` and configuring `daemon.json`) will be integrated directly into the `phoenix_hypervisor_feature_install_docker.sh` script.
    2.  **Ensure Idempotency:** Add checks to the script to prevent re-running commands unnecessarily. For example, check if `fuse-overlayfs` is already installed before attempting to install it.
    3.  **Improve Error Handling:** Add `set -e` to the script to ensure it exits immediately if any command fails, allowing the `phoenix_orchestrator.sh` to catch the failure and halt the provisioning process.

*   **Verification:**
    *   The successful and repeatable provisioning of a Docker-enabled container using the orchestrator will serve as the primary verification. The process should complete without errors even when run multiple times on the same container.

### Step 4: Correct Host AppArmor Tunables

*   **Why This Is Necessary:** The Proxmox host's AppArmor configuration must explicitly permit profile stacking to allow container-specific AppArmor policies to be enforced correctly. Without this, the host-level policy may override and block actions permitted by our refined `lxc-phoenix-v2` profile.

*   **Implementation Steps:**
    1.  **Modify Hypervisor Setup:** The `usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_apparmor.sh` script will be updated.
    2.  **Apply Nesting Tunable:** Add a command to the script to ensure that AppArmor nesting is enabled on the host. This is typically done by ensuring the following line is present in `/etc/apparmor.d/tunables/nesting`:
        ```
        @{apparmor_nesting_profiles} = lxc-phoenix-v2
        ```
    3.  **Reload AppArmor:** The script will execute `systemctl reload apparmor` to apply the changes to the host.

*   **Verification:**
    *   The successful operation of containers using the `lxc-phoenix-v2` profile without unexpected AppArmor denials will serve as indirect verification that the host is configured correctly.

## 3. Expected Outcomes

Upon successful implementation of this plan, we expect the following outcomes:

*   **Improved Performance:** Dockerized applications will exhibit faster container start times and reduced I/O load.
*   **Enhanced Security:** Containers will be confined by a least-privilege AppArmor profile specifically tailored for `fuse-overlayfs`, reducing the attack surface.
*   **Increased Stability:** The use of a supported storage driver will eliminate a class of potential bugs and data corruption issues associated with the `vfs` driver.
*   **Improved Maintainability:** The entire configuration will be managed declaratively and idempotently through our existing automation, making the system easier to manage and upgrade.