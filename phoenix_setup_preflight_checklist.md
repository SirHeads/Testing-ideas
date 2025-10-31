# Phoenix Setup Pre-Flight Checklist

This checklist should be reviewed before executing the `phoenix setup` command to ensure a smooth and successful hypervisor configuration.

## 1. Pre-Execution Verification

- [ ] **Backup**: Confirm that a complete and recent backup of the Proxmox host is available and restorable.
- [ ] **Console Access**: Ensure you have out-of-band console access (e.g., IPMI, KVM) to the hypervisor. This is critical in case of a network configuration issue.
- [ ] **Internet Connectivity**: Verify that the Proxmox host has a stable and reliable internet connection to download packages and drivers.

## 2. Configuration File Review (`phoenix_hypervisor_config.json`)

- [ ] **Network Configuration**:
    - [ ] Verify `network.interfaces.address` and `network.interfaces.gateway` are correct for your network.
    - [ ] Confirm that `network.interfaces.dns_nameservers` are valid and reachable.
- [ ] **ZFS Configuration**:
    - [ ] Double-check the disk identifiers in `zfs.pools.disks`. Use `/dev/disk/by-id/` paths to avoid issues with device name changes.
    - [ ] Confirm the `raid_level` for each pool is set as intended.
- [ ] **NVIDIA Driver**:
    - [ ] Verify that the `nvidia_driver.version` is compatible with your GPU hardware.
    - [ ] Check that the `nvidia_driver.runfile_url` is a valid and accessible download link.
- [ ] **User Configuration**:
    - [ ] Ensure the `users.password_hash` is correctly generated if you are not using the interactive user creation.
    - [ ] Verify the `users.ssh_public_key` is correct.

## 3. Execution Plan

- [ ] **ZFS Setup Mode**: Decide which execution mode to use for the ZFS setup (`--mode`).
    - `safe` (default): The script will abort if it detects any existing data on the target disks. Recommended for initial setup.
    - `interactive`: The script will prompt for confirmation before wiping any disks.
    - `force-destructive`: The script will automatically wipe disks without prompting. **Use with extreme caution.**
- [ ] **Reboot Plan**: The NVIDIA driver installation will trigger a system reboot. Plan for this downtime accordingly.
- [ ] **Monitoring**: Have a plan to monitor the script's output in real-time. The `logs.sh` script in the root of the project can be used for this.

## 4. Post-Execution Validation

- [ ] After the reboot, verify that you can log in to the Proxmox web UI.
- [ ] Check the status of the ZFS pools with `zpool status`.
- [ ] Verify the NVIDIA driver is loaded correctly with `nvidia-smi`.
- [ ] Test network connectivity and DNS resolution from the hypervisor.