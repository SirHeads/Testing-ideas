# Comprehensive Test Case Analysis for Hypervisor Setup Scripts

This document contains the full, unabridged list of all potential test cases identified for each script in the `usr/local/phoenix_hypervisor/bin/hypervisor_setup/` directory.

---

## 1. `hypervisor_feature_install_nvidia.sh`

| Test Case ID | Description | Expected Outcome |
| :--- | :--- | :--- |
| **PFC-001** | Run script without providing a configuration file path. | Script exits with a fatal error and a message "Configuration file path not provided." |
| **PFC-002** | Provide a path to a non-existent configuration file. | `jq` command fails, and the script exits with a fatal error. |
| **PFC-003** | Provide an invalid command-line option (e.g., `--invalid-option`). | Script exits with a fatal error and a message "Unknown option --invalid-option". |
| **PFC-004** | Run script with the `--no-reboot` flag. | Script completes installation but skips the final reboot, logging a warning. |
| **ENV-001** | Run script as a non-root user. | Script exits immediately with an error message from `check_root`. |
| **CFG-001** | `nvidia_driver.install` is set to `false`. | Script logs "NVIDIA driver installation is disabled" and exits successfully (exit code 0). |
| **HWS-001** | No NVIDIA GPU is detected by `lspci`. | Script logs "No NVIDIA GPU detected" and exits successfully (exit code 0). |
| **HWS-004** | `nvidia-smi` is present, and the installed driver version matches `NVIDIA_DRIVER_VERSION`. | Script logs that the correct version is already installed and exits successfully. |
| **HWS-005** | `nvidia-smi` is present, but the installed driver version does *not* match `NVIDIA_DRIVER_VERSION`. | Script logs the version mismatch and proceeds with re-installation. |
| **RES-001** | Run the script a second time after a successful first run. | The idempotency check identifies the correct version is installed, and the script exits cleanly without re-installing. |

---

## 2. `hypervisor_feature_setup_nfs.sh`

### I. Script Initialization and Pre-checks
1.  **Test Case: Script Execution without Root Privileges**
2.  **Test Case: Missing Configuration File Argument**
3.  **Test Case: Sourcing Missing Common Utilities Script**

### II. `install_nfs_packages` Function
4.  **Test Case: Successful Package Installation**
5.  **Test Case: Package Installation Failure**
6.  **Test Case: Packages Already Installed**

### III. `get_server_ip` Function
7.  **Test Case: Valid IP Address in Configuration**
8.  **Test Case: Missing IP Address in Configuration**

### IV. `configure_nfs_exports` Function
9.  **Test Case: No Existing `/etc/exports` File**
10. **Test Case: Existing `/etc/exports` File**
11. **Test Case: Backup Failure**
12. **Test Case: File Clearing Failure**
13. **Test Case: Valid NFS Shares Configuration**
14. **Test Case: Empty NFS Shares Array**
15. **Test Case: Share with Missing `path`**
16. **Test Case: Share with Missing `clients`**
17. **Test Case: Directory for Export Path Does Not Exist**
18. **Test Case: Directory Creation Failure**
19. **Test Case: NFS Service Restart Failure**
20. **Test Case: `exportfs -ra` Command Failure**

### V. `configure_nfs_firewall` Function
21. **Test Case: Successful UFW Rule Addition (by service name)**
22. **Test Case: Fallback to Specific Ports**
23. **Test Case: Firewall Rule Addition Failure (Fallback Port 111)**
24. **Test Case: Firewall Rule Addition Failure (Fallback Port 2049)**

### VI. `add_nfs_storage` Function
25. **Test Case: `pvesm` Command Not Found**
26. **Test Case: Successful Addition of New Proxmox NFS Storage**
27. **Test Case: Proxmox Storage Already Exists**
28. **Test Case: NFS Export Not Available via `showmount`**
29. **Test Case: Local Mount Point Creation Failure**
30. **Test Case: `pvesm add nfs` Command Failure**
31. **Test Case: No NFS Storage Added**

### VII. Main Execution Flow
32. **Test Case: End-to-End Successful Execution**

---

## 3. `hypervisor_feature_create_admin_user.sh`

### 1. Script Invocation and Configuration File Test Cases
*   **TC-INVOKE-001:** Script fails when run by a non-root user.
*   **TC-INVOKE-002:** Script fails when no configuration file path is provided.
*   **TC-CONFIG-001:** Script fails when the provided configuration file path is invalid.
*   **TC-CONFIG-002:** Script fails when the configuration file is not valid JSON.
*   **TC-CONFIG-003:** Script fails when the `users.username` key is missing or empty.
*   **TC-CONFIG-004:** Script proceeds with default values for missing optional keys.

### 2. `create_system_user` Function Test Cases
*   **TC-SYSUSER-001:** Create a new system user successfully.
*   **TC-SYSUSER-002:** Script skips creation if the system user already exists.
*   **TC-SYSUSER-005:** Sudo access is granted when `sudo_access` is true.
*   **TC-SYSUSER-008:** Script fails if `useradd` command fails.

### 3. `create_proxmox_user` Function Test Cases
*   **TC-PVEUSER-001:** Create a new Proxmox user successfully.
*   **TC-PVEUSER-002:** Script skips creation if the Proxmox user already exists.
*   **TC-PVEUSER-005:** Script fails if `pveum user add` command fails.

### 4. `setup_ssh_key` Function Test Cases
*   **TC-SSH-001:** Set up SSH key for a user successfully.
*   **TC-SSH-002:** SSH key setup is skipped if `ssh_public_key` is empty.
*   **TC-SSH-004:** SSH key is not added if it already exists in `authorized_keys`.

### 5. Idempotency and Integration Test Cases
*   **TC-IDEM-001:** Running the script twice with the same configuration produces no changes on the second run.
*   **TC-INT-001:** Full end-to-end run for a brand new user.

---

## 4. `hypervisor_feature_setup_samba.sh`

### 1. Prerequisite and Initial Checks
*   **Test Case 1.1:** Script not run as root
*   **Test Case 1.3:** Missing `HYPERVISOR_CONFIG_FILE`

### 2. Configuration Reading and Validation
*   **Test Case 2.1:** Valid `hypervisor_config.json`
*   **Test Case 2.3:** System user specified in config does not exist
*   **Test Case 2.6:** Empty `samba.shares` array

### 3. `install_samba` Function
*   **Test Case 3.1:** Samba not installed
*   **Test Case 3.2:** Samba already installed
*   **Test Case 3.4:** `apt-get install` fails

### 4. `configure_samba_user` Function
*   **Test Case 4.1:** Samba user does not exist
*   **Test Case 4.2:** Samba user already exists
*   **Test Case 4.3:** `smbpasswd` command fails

### 5. `configure_samba_shares` Function
*   **Test Case 5.1:** Share directory does not exist
*   **Test Case 5.3:** Failed to create share directory

### 6. `configure_samba_config` Function
*   **Test Case 6.2:** `smb.conf` exists
*   **Test Case 6.4:** Verify `smb.conf` content

### 7. `configure_samba_firewall` Function
*   **Test Case 7.1:** UFW rules do not exist
*   **Test Case 7.3:** `ufw` command fails

### 8. Service Management
*   **Test Case 8.1:** Samba services restart successfully
*   **Test Case 8.2:** Samba services fail to restart

### 9. Integration and End-to-End Tests
*   **Test Case 9.2:** Rerunning the script

---

## 5. `hypervisor_feature_setup_zfs.sh`

### I. Pre-execution and Dependency Checks
1.  **Root Privileges:** TC-ROOT-001, TC-ROOT-002
2.  **External Command Availability:** TC-DEPS-003, TC-DEPS-004

### II. ZFS Pool Creation
1.  **`check_available_drives`:** TC-CAD-001, TC-CAD-004
2.  **`monitor_nvme_wear`:** TC-MNW-001, TC-MNW-003
3.  **`check_system_ram`:** TC-CSR-001, TC-CSR-003
4.  **`create_zfs_pools` Main Logic:** TC-CZP-001, TC-CZP-002, TC-CZP-004

### III. ZFS Dataset Creation
1.  **Configuration Handling:** TC-CZD-001, TC-CZD-002
2.  **Dataset State:** TC-CZD-003, TC-CZD-004
3.  **Command Failures:** TC-CZD-008, TC-CZD-009

### IV. Proxmox Storage Integration
1.  **Existing Storage:** TC-APS-001
2.  **Storage Type Handling:** TC-APS-002, TC-APS-003, TC-APS-004
3.  **Command Failures:** TC-APS-007, TC-APS-008

### V. Main Execution Flow
1.  **End-to-End Success:** TC-MAIN-001
2.  **Idempotency:** TC-MAIN-002
3.  **Partial Failure Scenarios:** TC-MAIN-003

---

## 6. `hypervisor_initial_setup.sh`

### I. Script Invocation and Pre-checks
*   **Test Case 1.1:** Script fails when not run as root.
*   **Test Case 1.2:** Script fails when the configuration file path is not provided.

### II. `configure_log_rotation` Function
*   **Test Case 2.1:** Log rotation configuration file is created successfully.

### III. `configure_proxmox_repositories` Function
*   **Test Case 3.1:** Proxmox repositories are configured successfully on a clean system.
*   **Test Case 3.2:** `configure_proxmox_repositories` fails if GPG key download fails.

### IV. `update_and_upgrade_system` Function
*   **Test Case 5.1:** System update and upgrade succeeds.
*   **Test Case 5.2:** `update_and_upgrade_system` fails if `apt-get update` fails.

### V. Package Installation Functions
*   **Test Case 6.1:** Package installation succeeds.
*   **Test Case 6.3:** Package installation fails.

### VI. `set_system_timezone` Function
*   **Test Case 7.1:** Timezone is set successfully from the config file.
*   **Test Case 7.3:** `set_system_timezone` fails with an invalid timezone.

### VII. `configure_network_interface` Function
*   **Test Case 11.1:** Network interface is configured successfully.
*   **Test Case 11.3:** `configure_network_interface` fails if `systemctl restart networking` fails.

### VIII. `configure_firewall_rules` Function
*   **Test Case 13.1:** Firewall rules are configured successfully, and UFW is enabled.
*   **Test Case 13.3:** `configure_firewall_rules` fails if a `ufw allow` command fails.

### IX. Main Orchestration and Sequencing
*   **Test Case 14.1:** Full script runs successfully from start to finish.
*   **Test Case 14.2:** Script failure in an early stage prevents later stages from running.
*   **Test Case 14.3:** Idempotency test: running the script multiple times does not cause errors.

---