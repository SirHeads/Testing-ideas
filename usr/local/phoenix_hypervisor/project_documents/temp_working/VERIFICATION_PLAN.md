# Post-Setup Verification Plan

This document outlines a series of non-destructive tests to verify the successful installation and configuration of the hypervisor environment after running the `--setup-hypervisor` command. These tests are intended for the end-user to quickly confirm that critical components are functioning as expected.

---

## 1. Critical System Checks

These tests verify the fundamental components of the hypervisor setup.

| Test Name | Feature/Component | Verification Command | Expected Outcome |
| :--- | :--- | :--- | :--- |
| **Verify NVIDIA Driver** | NVIDIA GPU Support | `nvidia-smi` | The command returns a table with details about the NVIDIA driver version and attached GPUs. No errors should be displayed. |
| **Verify ZFS Pool Status** | ZFS Storage | `zpool status` | The command lists the configured ZFS pools. The state of all pools should be `ONLINE`, and there should be no read, write, or checksum errors. |
| **Verify Proxmox Services** | Proxmox VE | `systemctl is-active pveproxy pvedaemon pvestatd` | The command should output `active` for all three services, confirming that the Proxmox API and management daemons are running. |
| **Verify System Timezone** | System Configuration | `timedatectl \| grep "Time zone"` | The output should display the timezone that was configured during the setup process (e.g., `Time zone: America/New_York (EDT, -0400)`). |
| **Verify Admin User** | User Management | `id <admin_username>` | The command should return the user's UID, GID, and group memberships, confirming the user exists. Replace `<admin_username>` with the actual username. |
| **Verify Sudo Access** | User Management | `sudo -l -U <admin_username>` | The command should list the allowed sudo commands for the user, typically indicating full access `(ALL : ALL) ALL`. |

---

## 2. Network Services

These tests confirm that essential network services are correctly configured and accessible.

| Test Name | Feature/Component | Verification Command | Expected Outcome |
| :--- | :--- | :--- | :--- |
| **Verify Network Configuration** | Networking | `ip a` | The output should show the primary network interface with the static IP address configured during setup. |
| **Verify Firewall Status** | Firewall (UFW) | `sudo ufw status` | The output should show `Status: active` and list the firewall rules that were added, including rules for SSH, Proxmox Web UI, NFS, and Samba. |
| **Verify NFS Exports** | NFS Server | `showmount -e localhost` | The command should list the NFS export paths and the clients that are allowed to connect, matching the configuration. |
| **Verify Samba Access** | Samba Server | `smbclient -L //localhost -U <admin_username>%<password>` | The command should list the available Samba shares. Replace `<admin_username>` and `<password>` with the configured credentials. |

---

## 3. Hardware and Storage Verification

These tests ensure that storage and hardware components are correctly integrated.

| Test Name | Feature/Component | Verification Command | Expected Outcome |
| :--- | :--- | :--- | :--- |
| **Verify Proxmox ZFS Storage** | Proxmox Storage | `pvesm status \| grep '^zfs-'` | The command should list the ZFS-based storage pools that were added to Proxmox, showing them as `active`. |
| **Verify Proxmox NFS Storage** | Proxmox Storage | `pvesm status \| grep '^nfs-'` | The command should list the NFS-based storage that was added to Proxmox, showing it as `active`. |
| **Verify NVMe Wear Level** | ZFS Storage (NVMe) | `smartctl -a /dev/nvme0 \| grep "Percentage Used"` | For NVMe-based pools, this command should return the wear level percentage, which should be within acceptable limits (e.g., under 90%). |
