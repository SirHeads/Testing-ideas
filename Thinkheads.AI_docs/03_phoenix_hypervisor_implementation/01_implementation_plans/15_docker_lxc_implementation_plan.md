# Docker in Unprivileged LXC Implementation Plan

This document provides a step-by-step guide for implementing the Docker in Unprivileged LXC Remediation Plan.

## 1. Prerequisites

- [ ] **System Backup:** Ensure a full backup of the Proxmox host and all relevant containers has been completed and is verified.
- [ ] **Code Repository:** The `phoenix_hypervisor` code repository is cloned and up-to-date on the Proxmox host at `usr/local/phoenix_hypervisor`.
- [ ] **Access:** SSH access with `root` privileges to the Proxmox host is available.
- [ ] **Container Status:** All containers that will be affected are stopped or in a state where they can be safely restarted.
- [ ] **Audit Log Monitoring:** A terminal session is open and monitoring the system's audit log for AppArmor events (`tail -f /var/log/audit/audit.log` or `dmesg -w`).

## 2. Implementation Steps

### Step 1: Configure Host AppArmor Tunables

1.  **Navigate to the script directory:**
    ```bash
    cd /usr/local/phoenix_hypervisor/bin/hypervisor_setup/
    ```
2.  **Modify the AppArmor setup script** (`hypervisor_feature_setup_apparmor.sh`) to include the nesting tunable. Add the following lines:
    ```bash
    echo 'Adding AppArmor nesting tunable for lxc-phoenix-v2...'
    echo '@{apparmor_nesting_profiles} = lxc-phoenix-v2' > /etc/apparmor.d/tunables/nesting
    ```
3.  **Reload the AppArmor service** to apply the changes:
    ```bash
    systemctl reload apparmor
    ```
4.  **Verification:**
    - Run `apparmor_status` and ensure the `lxc-phoenix-v2` profile is loaded.
    - Check the audit log for any errors related to AppArmor profile loading.

### Step 2: Refine the `lxc-phoenix-v2` AppArmor Profile

1.  **Navigate to the AppArmor profile directory:**
    ```bash
    cd /usr/local/phoenix_hypervisor/etc/apparmor/
    ```
2.  **Edit the `lxc-phoenix-v2` profile** and add the following rules to allow `fuse-overlayfs` operations:
    ```
    # Allow fuse-overlayfs mounts
    mount fstype=fuse.fuse-overlayfs -> /var/lib/docker/fuse-overlayfs/**,
    allow /dev/fuse r,
    allow /sys/fs/fuse/connections r,
    ```
3.  **Deploy the updated profile** by running the `phoenix` CLI or by manually copying the file and reloading AppArmor:
    ```bash
    cp lxc-phoenix-v2 /etc/apparmor.d/
    systemctl reload apparmor
    ```
4.  **Verification:**
    - Monitor the audit log for `apparmor="DENIED"` messages when a container with this profile starts and runs Docker.

### Step 3: Optimize the Docker Installation Script

1.  **Navigate to the script directory:**
    ```bash
    cd /usr/local/phoenix_hypervisor/bin/lxc_setup/
    ```
2.  **Edit the `phoenix_hypervisor_feature_install_docker.sh` script** to incorporate the following changes:
    - Add `set -e` at the beginning of the script.
    - Add a check to see if `fuse-overlayfs` is already installed.
    - Add the command to install `fuse-overlayfs`: `apt-get install -y fuse-overlayfs`.
    - Add commands to create `/etc/docker/daemon.json` with the `fuse-overlayfs` storage driver.
    - Ensure the Docker service is restarted (`systemctl restart docker`).
    
    **Example Script Snippet:**
    ```bash
    #!/bin/bash
    set -e

    if ! dpkg -l | grep -q fuse-overlayfs; then
      echo "Installing fuse-overlayfs..."
      apt-get update
      apt-get install -y fuse-overlayfs
    fi

    echo "Configuring Docker to use fuse-overlayfs..."
    mkdir -p /etc/docker
    cat <<EOF > /etc/docker/daemon.json
    {
      "storage-driver": "fuse-overlayfs"
    }
    EOF

    echo "Restarting Docker service..."
    systemctl restart docker
    ```
3.  **Verification:**
    - Provision a new container with the `docker` feature using the `phoenix` CLI.
    - Re-run the provisioning on the same container to ensure the script is idempotent and completes without errors.

## 3. Rollback Procedure

1.  **Revert Docker Installation Script:**
    - Restore the previous version of `phoenix_hypervisor_feature_install_docker.sh` from version control.
    - For any affected containers, `pct exec <CTID> -- bash` into them and:
        - Remove `/etc/docker/daemon.json`.
        - Run `apt-get purge -y fuse-overlayfs`.
        - Restart the Docker service: `systemctl restart docker`.

2.  **Revert AppArmor Profile:**
    - Restore the previous version of `lxc-phoenix-v2` from version control.
    - Copy the restored profile to `/etc/apparmor.d/`.
    - Reload AppArmor: `systemctl reload apparmor`.

3.  **Revert Host AppArmor Tunables:**
    - Remove the file `/etc/apparmor.d/tunables/nesting`.
    - Reload AppArmor: `systemctl reload apparmor`.

## 4. Validation Strategy

1.  **Provision a Test Container:**
    - Use `phoenix create <CTID>` to create a new LXC container with the `docker` feature enabled.
2.  **Verify Storage Driver:**
    - Execute the following command and confirm the output is `fuse-overlayfs`:
      ```bash
      pct exec <CTID> -- docker info | grep "Storage Driver"
      ```
3.  **Test Docker Functionality:**
    - Run a simple Docker container to ensure basic functionality:
      ```bash
      pct exec <CTID> -- docker run hello-world
      ```
4.  **Monitor for AppArmor Denials:**
    - While running the tests, keep an eye on the host's audit log. The absence of `apparmor="DENIED"` messages related to `fuse-overlayfs` or Docker operations indicates a successful configuration.
5.  **Test Idempotency:**
    - Re-run the `phoenix create <CTID>` command for the same container. The process should complete successfully without any errors, confirming the scripts are idempotent.
