# Project Plan: Phoenix Hypervisor Tests Enhancement

## 1. Purpose

This project is initiated to enhance the `phoenix_hypervisor_tests.sh` script by automating the post-setup verification process outlined in the `FINAL_VERIFICATION_PLAN.md`. The primary objective is to provide end-users with a simple, reliable, and executable script to validate the integrity of their hypervisor installation, thereby improving user confidence and reducing the need for manual verification.

## 2. Strategy

The enhancement strategy will focus on creating a modular, user-friendly Bash script. Each verification test defined in the `FINAL_VERIFICATION_PLAN.md` will be implemented as a distinct function within the script. This approach ensures that the script is easy to read, maintain, and extend. The script will provide clear, color-coded pass/fail feedback for each test and conclude with a summary report of the overall system status.

## 3. Architectural Considerations

The enhanced script will be designed with the following architectural principles:

*   **Modularity:** Each test will be encapsulated in its own function, promoting code reuse and simplifying maintenance.
*   **Maintainability:** The script will be well-documented with comments explaining the purpose and function of each test.
*   **Integration:** The script will be self-contained and will not require external dependencies beyond standard system utilities.
*   **User Experience:** The output will be clear, concise, and actionable, enabling users to quickly identify and address any issues.

## 4. Goals

The high-level goals for this project are:

*   **Automation:** Fully automate the execution of all post-setup smoke tests.
*   **Clarity:** Provide users with unambiguous, actionable feedback on the installation status.
*   **Efficiency:** Reduce the time and effort required for manual verification.
*   **Reliability:** Minimize the potential for human error in the verification process.

## 5. Requirements

The final script must meet the following specific and measurable criteria:

*   Implement all verification tests as specified in the `FINAL_VERIFICATION_PLAN.md`.
*   Execute non-interactively, though it may require initial input for credentials if they cannot be sourced securely from the environment.
*   Produce a summary report detailing the results of each test.
*   Use color-coding to distinguish between successful and failed tests.
*   Adhere to Bash scripting best practices for robustness and readability.

## 6. Specifications

The following tests, derived from the `FINAL_VERIFICATION_PLAN.md`, will be implemented:

### 6.1. Critical System Checks
- **Verify NVIDIA Driver:** Execute `nvidia-smi` and confirm a successful exit code and output.
- **Verify ZFS Pool Status:** Run `zpool status` and parse the output to ensure all pools are `ONLINE` and error-free.
- **Verify Proxmox Services:** Use `systemctl is-active` to check that `pveproxy`, `pvedaemon`, and `pvestatd` are all active.
- **Verify System Timezone:** Check the output of `timedatectl` to confirm the correct timezone is set.
- **Verify Admin User:** Use the `id` command to ensure the administrative user exists.
- **Verify Sudo Access:** Confirm the administrative user has appropriate sudo privileges.

### 6.2. Network Services
- **Verify Network Configuration:** Parse the output of `ip a` to ensure the primary network interface has the correct static IP.
- **Verify Firewall Status:** Check `ufw status` to confirm the firewall is active and correctly configured.
- **Verify NFS Exports:** Use `showmount -e localhost` to validate the NFS export configuration.
- **Verify Samba Access:** Check for available Samba shares using `smbclient`.

### 6.3. Hardware and Storage Verification
- **Verify Proxmox ZFS Storage:** Ensure ZFS-based storage pools are active in Proxmox with `pvesm status`.
- **Verify Proxmox NFS Storage:** Confirm that NFS-based storage is active in Proxmox.
- **Verify NVMe Wear Level:** For NVMe devices, check the wear level using `smartctl` to ensure it is within acceptable limits.