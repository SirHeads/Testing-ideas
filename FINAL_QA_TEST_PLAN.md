# QA Test Plan: Hypervisor Setup Scripts

## 1. Scope

### In-Scope
This document provides a comprehensive test plan for the internal quality assurance of the hypervisor setup scripts. It covers:
*   Error handling, pre-checks, and dependency validation.
*   Idempotency of all setup and configuration scripts.
*   Configuration edge cases, including empty or disabled values.
*   Simulated failure scenarios for critical functions.

### Out-of-Scope
*   End-to-end user acceptance testing (covered by the Smoke Test Plan).
*   Performance or scalability testing of the hypervisor.
*   Hardware compatibility testing beyond the specified test environment.

---

## 2. Test Environment

*   **Hardware:** Virtualized or physical machine with 4+ CPU cores, 8GB+ RAM, 100GB+ storage.
*   **Operating System:** Clean installation of Debian 12 (Bookworm).
*   **Software:** Proxmox VE 8.x installed as a baseline.
*   **Testing Tools:** Bash, `jq`, `pvesm`, `zpool`, `systemctl`.

---

## 3. Entry and Exit Criteria

### Entry Criteria
*   All setup scripts are code-complete and have passed linting checks.
*   The test environment is provisioned and meets the specifications above.
*   A valid baseline configuration file (`phoenix_hypervisor_config.json`) is available.

### Exit Criteria
*   100% of P1 test cases have passed.
*   95% of P2 test cases have passed.
*   No open defects with a "Critical" or "High" severity rating.
*   All test results are documented.

---

## 4. Risk Assessment and Mitigation

| Risk | Likelihood | Impact | Mitigation Strategy |
| :--- | :--- | :--- | :--- |
| **Critical Script Failure** | Medium | High | Implement robust error handling and pre-checks in all scripts to fail gracefully. |
| **Environment Inconsistency** | Medium | Medium | Use a standardized, automated process (e.g., Packer, Terraform) for provisioning test environments. |
| **Data Corruption** | Low | High | Conduct tests on non-production systems; ensure ZFS setup scripts have safeguards against reformatting existing pools. |

---

## 5. Regression Strategy

After any bug fix or feature enhancement, the following regression tests will be executed:
*   All P1 test cases from this plan.
*   Any P2 test cases directly related to the modified component.
*   A full run of the `Post-Setup Smoke Test Plan`.

---

## 6. Test Cases

### 6.1. Error Handling and Pre-checks

| Test Case ID | Requirement ID | Priority | Description | Preconditions/Steps | Expected Result |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **PRECHECK-CONFIG-001** | REQ-001 | P1 | Verify script exits gracefully when no config file is provided. | Run any setup script without the `--config` argument. | Script exits with a fatal error and a clear message (e.g., "Configuration file path not provided"). |
| **PRECHECK-CONFIG-002** | REQ-001 | P1 | Verify script handles a non-existent configuration file. | Provide a path to a file that does not exist. | The script exits with a fatal error, indicating the file cannot be found or read. |
| **PRECHECK-ENV-001** | REQ-002 | P1 | Verify script fails when not executed as the root user. | Execute any setup script as a non-root user. | Script exits immediately with an error message like "This script must be run as root." |
| **PRECHECK-DEPS-001** | REQ-003 | P2 | Verify script checks for required external commands. | Uninstall a required command (e.g., `jq`, `smartctl`, `pvesm`). Run the relevant script. | The script detects the missing dependency and exits with a fatal error. |
| **PRECHECK-CONFIG-003** | REQ-001 | P2 | Verify script handles malformed JSON in the config file. | Provide a config file with a JSON syntax error. | The `jq` command fails, and the script exits with a fatal error. |

### 6.2. Idempotency and Re-runnability

| Test Case ID | Requirement ID | Priority | Description | Preconditions/Steps | Expected Result |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **IDEM-NVIDIA-001** | REQ-004 | P1 | Verify NVIDIA driver installation is idempotent. | Run `hypervisor_feature_install_nvidia.sh` twice successfully. | The second run should detect that the correct driver is already installed and exit cleanly without re-installing. |
| **IDEM-USER-001** | REQ-005 | P1 | Verify user creation is idempotent. | Run `hypervisor_feature_create_admin_user.sh` twice with the same configuration. | The second run should not create new users or modify existing ones. All checks should pass. |
| **IDEM-ZFS-001** | REQ-006 | P1 | Verify ZFS setup is idempotent. | Run `hypervisor_feature_setup_zfs.sh` twice. | The second run should identify that the pools and datasets already exist and exit without making changes. |
| **IDEM-SAMBA-001** | REQ-007 | P1 | Verify Samba setup is idempotent. | Run `hypervisor_feature_setup_samba.sh` twice. | The second run should not alter the configuration, re-create users, or fail. |
| **IDEM-SYSTEM-001** | REQ-008 | P1 | Verify initial system setup is idempotent. | Run `hypervisor_initial_setup.sh` multiple times. | Subsequent runs should not cause errors or change system state (e.g., re-adding repos, re-creating files). |

### 6.3. Configuration Edge Cases

| Test Case ID | Requirement ID | Priority | Description | Preconditions/Steps | Expected Result |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **CONFIG-NVIDIA-001** | REQ-004 | P2 | Verify NVIDIA installation is skipped when disabled. | Set `nvidia_driver.install` to `false` in the config. | The script logs that installation is disabled and exits with status 0. |
| **CONFIG-USER-001** | REQ-005 | P2 | Verify user creation handles missing optional keys. | Provide a user config with only the `username` specified. | The script proceeds with default values for optional fields like `shell` or `sudo_access`. |
| **CONFIG-SAMBA-001** | REQ-007 | P2 | Verify Samba script handles an empty shares array. | Configure `samba.shares` as an empty array `[]`. | The script should run without errors, skipping the share configuration logic. |
| **CONFIG-NFS-001** | REQ-009 | P2 | Verify NFS script handles an empty shares array. | Configure `nfs.shares` as an empty array `[]`. | The script should complete successfully, configuring the NFS server but not creating any exports. |
| **CONFIG-ZFS-001** | REQ-006 | P2 | Verify ZFS script handles an empty datasets array. | Configure `zfs.datasets` as an empty array `[]`. | The script should create the ZFS pools but skip the dataset creation step. |

### 6.4. Function-Level and Failure Scenario Tests

| Test Case ID | Requirement ID | Priority | Description | Preconditions/Steps | Expected Result |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **FAIL-SYSTEM-001** | REQ-008 | P2 | Simulate `apt-get update` failure during initial setup. | Use a temporary wrapper script to intercept the `apt-get update` call and return a non-zero exit code. | The `update_and_upgrade_system` function should fail, and the main script should exit with a fatal error. |
| **FAIL-NFS-001** | REQ-009 | P2 | Simulate NFS service restart failure. | Use `systemctl mask nfs-kernel-server` to prevent the service from starting. Run the script. | The `configure_nfs_exports` function should log the failure and exit, preventing the script from proceeding. |
| **FAIL-SAMBA-001** | REQ-007 | P2 | Simulate `smbpasswd` command failure. | Replace the `smbpasswd` binary with a script that returns a non-zero exit code. | The `configure_samba_user` function should fail, and the script should exit with an error. |
| **FAIL-PVE-USER-001** | REQ-005 | P2 | Simulate `pveum user add` command failure. | Force the `pveum user add` command to fail (e.g., by providing invalid parameters). | The `create_proxmox_user` function should detect the failure and exit. |
| **FAIL-PVE-STORAGE-001**| REQ-006 | P2 | Simulate `pvesm add` command failure for ZFS storage. | Provide an invalid storage type or path to force the `pvesm add` command to fail. | The `add_proxmox_storage` function should catch the error and exit gracefully. |