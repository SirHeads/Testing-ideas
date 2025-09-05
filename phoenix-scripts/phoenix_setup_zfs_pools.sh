#!/bin/bash
# phoenix_setup_zfs_pools.sh
# Configures ZFS pools (quickOS and fastData) on Proxmox VE for the Phoenix server
# Version: 1.2.2 (3-drive setup) - Patched for full device path handling
# Author: Heads, Grok, Devstral

# Main: Creates and configures ZFS pools for quickOS and fastData
# Args: -q "drive1 drive2" (quickOS mirror drives), -f drive (fastData drive)
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_zfs_pools-1.1", "keywords": ["zfs", "proxmox"], "comment_type": "block"}
# Algorithm: ZFS pool setup
# Parses drive arguments, validates inputs, creates mirrored quickOS and single-drive fastData pools
# Keywords: [zfs, pool, proxmox]
# TODO: Implement drive existence and compatibility validation

# Source common functions and configuration
# Assumes LOGFILE is set by the orchestrator (create_phoenix.sh)
source /usr/local/bin/common.sh || { echo "[$(date)] Error: Failed to source common.sh" | tee -a /dev/stderr; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "[$(date)] Error: Failed to source phoenix_config.sh" | tee -a /dev/stderr; exit 1; }
# load_config # Properties used here are likely static or passed via arguments

# Parse command-line arguments for drives
# Metadata: {"chunk_id": "phoenix_setup_zfs_pools-1.2", "keywords": ["args", "drives"], "comment_type": "block"}
QUICKOS_DRIVES=()
FASTDATA_DRIVE=""
while getopts "q:f:" opt; do
  case $opt in
    q)
      IFS=' ' read -r -a QUICKOS_DRIVES <<< "$OPTARG"
      if [[ ${#QUICKOS_DRIVES[@]} -ne 2 ]]; then
          echo "[$(date)] Error: -q requires exactly two drives." | tee -a "${LOGFILE:-/dev/stderr}"
          exit 1
      fi
      ;;
    f)
      FASTDATA_DRIVE="$OPTARG"
      ;;
    \?)
      echo "[$(date)] Invalid option: -$OPTARG" | tee -a "${LOGFILE:-/dev/stderr}" >&2
      exit 1
      ;;
    :)
      echo "[$(date)] Option -$OPTARG requires an argument." | tee -a "${LOGFILE:-/dev/stderr}" >&2
      exit 1
      ;;
  esac
done

# Validate drive arguments
# Metadata: {"chunk_id": "phoenix_setup_zfs_pools-1.3", "keywords": ["validation", "drives"], "comment_type": "block"}
if [[ ${#QUICKOS_DRIVES[@]} -ne 2 || -z "$FASTDATA_DRIVE" ]]; then
    echo "[$(date)] Error: Both -q (two drives) and -f (one drive) are required." | tee -a "${LOGFILE:-/dev/stderr}"
    exit 1
fi

check_root
# setup_logging # Assume handled by orchestrator

echo "[$(date)] Starting phoenix_setup_zfs_pools.sh" >> "${LOGFILE:-/dev/stderr}"
echo "[$(date)] Drives - quickOS: ${QUICKOS_DRIVES[*]}, fastData: $FASTDATA_DRIVE" >> "${LOGFILE:-/dev/stderr}"

# check_available_drives: Verifies drive availability and ZFS pool membership
# Args: $1: Full drive path (e.g., /dev/disk/by-id/nvme-...)
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_zfs_pools-1.4", "keywords": ["drive", "validation"], "comment_type": "block"}
# Algorithm: Drive availability check
# Verifies drive existence, checks if part of ZFS pool, logs drive type
# Keywords: [drive, validation]
check_available_drives() {
    # Expecting full path like /dev/disk/by-id/nvme-...
    local drive_path="$1"

    # --- FIX 1: Correctly check existence of the full path ---
    if [ ! -b "$drive_path" ]; then
        echo "[$(date)] Error: Drive $drive_path does not exist" | tee -a "${LOGFILE:-/dev/stderr}"
        exit 1
    fi

    # Check if drive is already part of any ZFS pool
    # zpool status lists devices by their full path if that's how they were added
    if zpool status | grep -q "$drive_path"; then
        echo "[$(date)] Error: Drive $drive_path is already part of a ZFS pool" | tee -a "${LOGFILE:-/dev/stderr}"
        exit 1
    fi

    # --- FIX 2: Get drive type using the full path ---
    # lsblk -d -o NAME,TRAN /dev/disk/by-id/nvme-... will show the TRAN for that specific device
    DRIVE_TYPE=$(lsblk -d -o NAME,TRAN "$drive_path" | tail -n +2 | awk '{print $2}')
    if [[ -z "$DRIVE_TYPE" ]]; then
        echo "[$(date)] Warning: Drive type for $drive_path could not be determined, proceeding anyway" >> "${LOGFILE:-/dev/stderr}"
    else
        echo "[$(date)] Drive $drive_path is of type $DRIVE_TYPE" >> "${LOGFILE:-/dev/stderr}"
    fi
    echo "[$(date)] Verified that drive $drive_path is available" >> "${LOGFILE:-/dev/stderr}"
}

# monitor_nvme_wear: Monitors NVMe drive wear using smartctl
# Args: Full drive paths to monitor (space-separated)
# Returns: 0 on success, logs warnings if smartctl not installed
# Metadata: {"chunk_id": "phoenix_setup_zfs_pools-1.5", "keywords": ["nvme", "wear"], "comment_type": "block"}
# Algorithm: NVMe wear monitoring
# Logs NVMe wear stats for drives if smartctl is available
# Keywords: [nvme, wear]
monitor_nvme_wear() {
    # Expecting full paths like /dev/disk/by-id/nvme-...
    local drive_paths="$@"

    if command -v smartctl >/dev/null 2>&1; then
        for drive_path in $drive_paths; do
            # --- FIX 3: Check if the specific drive is NVMe using its full path ---
            if lsblk -d -o NAME,TRAN "$drive_path" | tail -n +2 | grep -q "nvme$"; then
                # --- FIX 4: Extract canonical name (e.g., nvme0n1) for smartctl ---
                canonical_name=$(basename "$drive_path")
                smartctl -a "/dev/$canonical_name" | grep -E "Wear_Leveling|Media_Wearout" >> "${LOGFILE:-/dev/stderr}" 2>/dev/null
                echo "[$(date)] NVMe wear stats for $drive_path ($canonical_name) logged" >> "${LOGFILE:-/dev/stderr}"
            fi
        done
    else
        echo "[$(date)] Warning: smartctl not installed, skipping NVMe wear monitoring" >> "${LOGFILE:-/dev/stderr}"
    fi
}

# check_system_ram: Checks system RAM for ZFS ARC limit
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_zfs_pools-1.6", "keywords": ["ram", "zfs"], "comment_type": "block"}
# Algorithm: RAM check for ZFS ARC
# Verifies system RAM is sufficient for ZFS ARC limit, sets zfs_arc_max
# Keywords: [ram, zfs]
# TODO: Allow configurable ZFS_ARC_MAX
check_system_ram() {
    local zfs_arc_max=8589934592  # 8GB in bytes
    local required_ram=$((zfs_arc_max * 2))
    local total_ram=$(free -b | awk '/Mem:/ {print $2}')
    if [[ $total_ram -lt $required_ram ]]; then
        echo "[$(date)] Warning: System RAM ($((total_ram / 1024 / 1024 / 1024)) GB) is less than twice ZFS_ARC_MAX ($((zfs_arc_max / 1024 / 1024 / 1024)) GB). This may cause memory issues." | tee -a "${LOGFILE:-/dev/stderr}"
        read -p "Continue with current ZFS_ARC_MAX setting? (y/n): " RAM_CONFIRMATION
        if [[ "$RAM_CONFIRMATION" != "y" && "$RAM_CONFIRMATION" != "Y" ]]; then
            echo "[$(date)] Error: Aborted due to insufficient RAM for ZFS_ARC_MAX" | tee -a "${LOGFILE:-/dev/stderr}"
            exit 1
        fi
    fi
    echo "[$(date)] Verified system RAM ($((total_ram / 1024 / 1024 / 1024)) GB) is sufficient for ZFS_ARC_MAX" >> "${LOGFILE:-/dev/stderr}"
    echo "$zfs_arc_max" > /sys/module/zfs/parameters/zfs_arc_max || { echo "[$(date)] Error: Failed to set zfs_arc_max to $zfs_arc_max" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
    echo "[$(date)] Set zfs_arc_max to $zfs_arc_max bytes" >> "${LOGFILE:-/dev/stderr}"
}

# Check available drives
# Metadata: {"chunk_id": "phoenix_setup_zfs_pools-1.7", "keywords": ["drive", "check"], "comment_type": "block"}
for drive in "${QUICKOS_DRIVES[@]}" "$FASTDATA_DRIVE"; do
    check_available_drives "$drive"
done

# Wipe existing partitions
# Metadata: {"chunk_id": "phoenix_setup_zfs_pools-1.8", "keywords": ["partition", "wipe"], "comment_type": "block"}
# Algorithm: Partition wiping
# Wipes partitions on selected drives
# Keywords: [partition, wipe]
for drive in "${QUICKOS_DRIVES[@]}" "$FASTDATA_DRIVE"; do
    # Use the full path directly with wipefs
    retry_command "wipefs -a $drive" || { echo "[$(date)] Error: Failed to wipe partitions on $drive" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
    echo "[$(date)] Wiped partitions on $drive" >> "${LOGFILE:-/dev/stderr}"
done

# Create ZFS pools
# Metadata: {"chunk_id": "phoenix_setup_zfs_pools-1.9", "keywords": ["zfs", "pool"], "comment_type": "block"}
# Algorithm: ZFS pool creation
# Creates ZFS pools for quickOS and fastData if not existing
# Keywords: [zfs, pool]
if zpool list quickOS >/dev/null 2>&1; then
    echo "[$(date)] Pool quickOS already exists, skipping creation" >> "${LOGFILE:-/dev/stderr}"
else
    # Pass full paths directly to zpool create
    retry_command "zpool create -f -o autotrim=on -O compression=lz4 -O atime=off quickOS mirror ${QUICKOS_DRIVES[0]} ${QUICKOS_DRIVES[1]}" || { echo "[$(date)] Error: Failed to create quickOS pool" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
    echo "[$(date)] Created ZFS pool quickOS on ${QUICKOS_DRIVES[*]}" >> "${LOGFILE:-/dev/stderr}"
fi

if zpool list fastData >/dev/null 2>&1; then
    echo "[$(date)] Pool fastData already exists, skipping creation" >> "${LOGFILE:-/dev/stderr}"
else
    # Pass full path directly to zpool create
    retry_command "zpool create -f -o autotrim=on -O compression=lz4 -O atime=off fastData $FASTDATA_DRIVE" || { echo "[$(date)] Error: Failed to create fastData pool" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
    echo "[$(date)] Created ZFS pool fastData on $FASTDATA_DRIVE" >> "${LOGFILE:-/dev/stderr}"
fi

# Monitor NVMe wear
# Metadata: {"chunk_id": "phoenix_setup_zfs_pools-1.10", "keywords": ["nvme", "wear"], "comment_type": "block"}
monitor_nvme_wear "${QUICKOS_DRIVES[@]}" "$FASTDATA_DRIVE" # Pass array elements and single drive

# Check system RAM and set ARC limit
# Metadata: {"chunk_id": "phoenix_setup_zfs_pools-1.11", "keywords": ["ram", "zfs"], "comment_type": "block"}
check_system_ram

echo "[$(date)] Successfully completed phoenix_setup_zfs_pools.sh" >> "${LOGFILE:-/dev/stderr}"
exit 0