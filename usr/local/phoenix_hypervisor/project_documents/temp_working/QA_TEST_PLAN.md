# QA Test Plan: Hypervisor Setup Scripts

This document provides a comprehensive test plan for the internal quality assurance of the hypervisor setup scripts. It covers a full range of test cases, including error handling, idempotency, configuration edge cases, and function-level tests to ensure the stability and reliability of the setup process.

---

## 1. Error Handling and Pre-checks

These tests focus on the scripts' ability to handle invalid states, missing dependencies, and incorrect invocation.

| Test Case ID | Priority | Description | Preconditions/Steps | Expected Result |
| :--- | :--- | :--- | :--- | :--- |
| **PFC-001** | P1 | Verify script exits gracefully when no config file is provided. | Run any setup script without the `--config` argument. | Script exits with a fatal error and a clear message (e.g., "Configuration file path not provided"). |
| **PFC-002** | P1 | Verify script handles a non-existent configuration file. | Provide a path to a file that does not exist. | The script exits with a fatal error, indicating the file cannot be found or read. |
| **ENV-001** | P1 | Verify script fails when not executed as the root user. | Execute any setup script as a non-root user. | Script exits immediately with an error message like "This script must be run as root." |
| **TC-DEPS-003** | P2 | Verify script checks for required external commands. | Uninstall a required command (e.g., `jq`, `smartctl`, `pvesm`). Run the relevant script. | The script detects the missing dependency and exits with a fatal error. |
| **TC-CONFIG-002** | P2 | Verify script handles malformed JSON in the config file. | Provide a config file with a JSON syntax error. | The `jq` command fails, and the script exits with a fatal error. |

---

## 2. Idempotency and Re-runnability

These tests ensure that running the scripts multiple times does not cause errors or unintended changes.

| Test Case ID | Priority | Description | Preconditions/Steps | Expected Result |
| :--- | :--- | :--- | :--- | :--- |
| **RES-001** | P1 | Verify NVIDIA driver installation is idempotent. | Run `hypervisor_feature_install_nvidia.sh` twice successfully. | The second run should detect that the correct driver is already installed and exit cleanly without re-installing. |
| **TC-IDEM-001** | P1 | Verify user creation is idempotent. | Run `hypervisor_feature_create_admin_user.sh` twice with the same configuration. | The second run should not create new users or modify existing ones. All checks should pass. |
| **TC-MAIN-002** | P1 | Verify ZFS setup is idempotent. | Run `hypervisor_feature_setup_zfs.sh` twice. | The second run should identify that the pools and datasets already exist and exit without making changes. |
| **Test Case 9.2** | P1 | Verify Samba setup is idempotent. | Run `hypervisor_feature_setup_samba.sh` twice. | The second run should not alter the configuration, re-create users, or fail. |
| **TC-14.3** | P1 | Verify initial system setup is idempotent. | Run `hypervisor_initial_setup.sh` multiple times. | Subsequent runs should not cause errors or change system state (e.g., re-adding repos, re-creating files). |

---

## 3. Configuration Edge Cases

These tests explore how the scripts behave with non-standard, empty, or unusual configuration values.

| Test Case ID | Priority | Description | Preconditions/Steps | Expected Result |
| :--- | :--- | :--- | :--- | :--- |
| **CFG-001** | P2 | Verify NVIDIA installation is skipped when disabled. | Set `nvidia_driver.install` to `false` in the config. | The script logs that installation is disabled and exits with status 0. |
| **TC-CONFIG-004** | P2 | Verify user creation handles missing optional keys. | Provide a user config with only the `username` specified. | The script proceeds with default values for optional fields like `shell` or `sudo_access`. |
| **Test Case 2.6** | P2 | Verify Samba script handles an empty shares array. | Configure `samba.shares` as an empty array `[]`. | The script should run without errors, skipping the share configuration logic. |
| **Test Case 14** | P2 | Verify NFS script handles an empty shares array. | Configure `nfs.shares` as an empty array `[]`. | The script should complete successfully, configuring the NFS server but not creating any exports. |
| **TC-CZD-002** | P2 | Verify ZFS script handles an empty datasets array. | Configure `zfs.datasets` as an empty array `[]`. | The script should create the ZFS pools but skip the dataset creation step. |

---

## 4. Function-Level and Failure Scenario Tests

These tests target specific functions within the scripts to verify their resilience to failure.

| Test Case ID | Priority | Description | Preconditions/Steps | Expected Result |
| :--- | :--- | :--- | :--- | :--- |
| **Test Case 5.2** | P2 | Simulate `apt-get update` failure during initial setup. | Modify the script to force `apt-get update` to return a non-zero exit code. | The `update_and_upgrade_system` function should fail, and the main script should exit with a fatal error. |
| **Test Case 19** | P2 | Simulate NFS service restart failure. | Modify the script to force `systemctl restart nfs-kernel-server` to fail. | The `configure_nfs_exports` function should log the failure and exit, preventing the script from proceeding. |
| **Test Case 4.3** | P2 | Simulate `smbpasswd` command failure. | Force the `smbpasswd` command to return a non-zero exit code. | The `configure_samba_user` function should fail, and the script should exit with an error. |
| **TC-PVEUSER-005** | P2 | Simulate `pveum user add` command failure. | Force the `pveum user add` command to fail (e.g., by providing invalid parameters). | The `create_proxymox_user` function should detect the failure and exit. |
| **TC-APS-007** | P2 | Simulate `pvesm add` command failure for ZFS storage. | Force the `pvesm add` command to fail. | The `add_proxmox_storage` function should catch the error and exit gracefully. |
