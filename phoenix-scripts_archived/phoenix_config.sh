# Metadata: {"chunk_id": "phoenix_config-1.0", "keywords": ["config", "proxmox", "zfs", "samba"], "comment_type": "block"}
#!/bin/bash
# phoenix_config.sh
# Configuration variables for Proxmox VE setup scripts
# Version: 1.3.2 (Added NVIDIA Configuration for Project Goals)
# Author: Heads, Grok, Devstral, Assistant

# Main: Defines and exports configuration variables for Proxmox setup
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_config-1.1", "keywords": ["config", "proxmox"], "comment_type": "block"}
# Algorithm: Configuration loading
# Sets and exports ZFS pool, dataset, storage, and network variables
# Keywords: [config, zfs, proxmox, samba, nfs]
# TODO: Add validation for environment variable conflicts

# --- NVIDIA Configuration for Host Setup ---
# Metadata: {"chunk_id": "phoenix_config-1.15", "keywords": ["nvidia", "driver", "proxmox"], "comment_type": "block"}
# Defines the target NVIDIA driver version and download URL for the Proxmox host setup.
# These variables are intended to be used by phoenix_install_nvidia_driver.sh.
export PHOENIX_NVIDIA_DRIVER_VERSION="${PHOENIX_NVIDIA_DRIVER_VERSION:-580.76.05}"
export PHOENIX_NVIDIA_RUNFILE_URL="${PHOENIX_NVIDIA_RUNFILE_URL:-https://us.download.nvidia.com/XFree86/Linux-x86_64/580.76.05/NVIDIA-Linux-x86_64-580.76.05.run}"
# --- End NVIDIA Configuration ---

# load_config: Loads and exports configuration variables for Proxmox setup
# Args: None
# Returns: 0 on success
# Metadata: {"chunk_id": "phoenix_config-1.2", "keywords": ["config", "zfs", "samba", "nfs"], "comment_type": "block"}
# Algorithm: Configuration setup
# Validates network settings, defines ZFS pools, datasets, and storage types
# Keywords: [config, zfs, samba, nfs]
# TODO: Re-enable storageNFS pool configuration if needed
load_config() 
{
    # Network configuration
    # Metadata: {"chunk_id": "phoenix_config-1.3", "keywords": ["network", "nfs"], "comment_type": "block"}
    if [[ -n "$PROXMOX_NFS_SERVER" ]]; then
        if ! [[ "$PROXMOX_NFS_SERVER" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            echo "Error: Invalid PROXMOX_NFS_SERVER format: $PROXMOX_NFS_SERVER" | tee -a "${LOGFILE:-/dev/stderr}"
            exit 1
        fi
    else
        PROXMOX_NFS_SERVER="10.0.0.13"
    fi
    if [[ -n "$DEFAULT_SUBNET" ]]; then
        if ! [[ "$DEFAULT_SUBNET" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            echo "Error: Invalid DEFAULT_SUBNET format: $DEFAULT_SUBNET" | tee -a "${LOGFILE:-/dev/stderr}"
            exit 1
        fi
    else
        DEFAULT_SUBNET="10.0.0.0/24"
    fi
    export PROXMOX_NFS_SERVER DEFAULT_SUBNET

    # SMB configuration
    # Metadata: {"chunk_id": "phoenix_config-1.4", "keywords": ["samba", "user"], "comment_type": "block"}
    SMB_USER="${SMB_USER:-heads}"
    export SMB_USER

    # ZFS pools and drives
    # Metadata: {"chunk_id": "phoenix_config-1.5", "keywords": ["zfs", "pool"], "comment_type": "block"}
    QUICKOS_POOL="quickOS"
    FASTDATA_POOL="fastData"
    # STORAGE_NFS_POOL="storageNFS" # Disabled for 3-drive setup
    export QUICKOS_POOL FASTDATA_POOL # STORAGE_NFS_POOL
    # Drives are set by orchestrator (create_phoenix.sh)
    # export QUICKOS_DRIVES FASTDATA_DRIVE

    # quickOS datasets
    # Metadata: {"chunk_id": "phoenix_config-1.6", "keywords": ["zfs", "dataset", "quickOS"], "comment_type": "block"}
    declare -gA QUICKOS_DATASET_PROPERTIES
    QUICKOS_DATASET_PROPERTIES=(
        ["vm-disks"]="recordsize=128K,compression=lz4,sync=standard,quota=800G"
        ["lxc-disks"]="recordsize=16K,compression=lz4,sync=standard,quota=600G"
        ["shared-prod-data"]="recordsize=128K,compression=lz4,sync=standard,quota=400G"
        ["shared-prod-data-sync"]="recordsize=16K,compression=lz4,sync=always,quota=100G"
    )
    QUICKOS_DATASET_LIST=("vm-disks" "lxc-disks" "shared-prod-data" "shared-prod-data-sync")
    export QUICKOS_DATASET_LIST

    # fastData datasets
    # Metadata: {"chunk_id": "phoenix_config-1.7", "keywords": ["zfs", "dataset", "fastData"], "comment_type": "block"}
    declare -gA FASTDATA_DATASET_PROPERTIES
    FASTDATA_DATASET_PROPERTIES=(
        ["shared-test-data"]="recordsize=128K,compression=lz4,sync=standard,quota=500G"
        ["shared-backups"]="recordsize=1M,compression=zstd,sync=standard,quota=2T"
        ["shared-iso"]="recordsize=1M,compression=lz4,sync=standard,quota=100G"
        ["shared-bulk-data"]="recordsize=1M,compression=lz4,sync=standard,quota=1.4T"
        ["shared-test-data-sync"]="recordsize=16K,compression=lz4,sync=always,quota=100G"
    )
    FASTDATA_DATASET_LIST=("shared-test-data" "shared-backups" "shared-iso" "shared-bulk-data" "shared-test-data-sync")
    export FASTDATA_DATASET_LIST

    # storageNFS datasets (disabled)
    # Metadata: {"chunk_id": "phoenix_config-1.8", "keywords": ["nfs", "dataset", "storageNFS"], "comment_type": "block"}
    # STORAGE_NFS_DATASET_LIST=(
    #     "shared-prod-data"
    #     "shared-prod-data-sync"
    #     "shared-test-data"
    #     "shared-test-data-sync"
    # )
    # declare -gA STORAGE_NFS_DATASET_PROPERTIES
    # STORAGE_NFS_DATASET_PROPERTIES=(
    #     ["shared-prod-data"]="compression=lz4,recordsize=128K,sync=standard,quota=400G"
    #     ["shared-prod-data-sync"]="compression=lz4,recordsize=16K,sync=always"
    #     ["shared-test-data"]="compression=lz4,atime=off"
    #     ["shared-test-data-sync"]="compression=lz4,atime=off,sync=always"
    # )
    # export STORAGE_NFS_DATASET_LIST

    # Dataset storage types
    # Metadata: {"chunk_id": "phoenix_config-1.9", "keywords": ["zfs", "storage", "proxmox"], "comment_type": "block"}
    declare -gA DATASET_STORAGE_TYPES
    DATASET_STORAGE_TYPES=(
        ["quickOS/vm-disks"]="zfspool:images"
        ["quickOS/lxc-disks"]="zfspool:rootdir"
        ["quickOS/shared-prod-data"]="cifs:images"
        ["quickOS/shared-prod-data-sync"]="cifs:images"
        ["fastData/shared-backups"]="dir:backup"
        ["fastData/shared-iso"]="dir:iso,vztmpl"
        ["fastData/shared-test-data"]="cifs:images"
        ["fastData/shared-bulk-data"]="cifs:images"
        ["fastData/shared-test-data-sync"]="cifs:images"
    )
    export DATASET_STORAGE_TYPES

    # Samba dataset options
    # Metadata: {"chunk_id": "phoenix_config-1.10", "keywords": ["samba", "options"], "comment_type": "block"}
    declare -gA SAMBA_DATASET_OPTIONS
    SAMBA_DATASET_OPTIONS=(
        ["quickOS/shared-prod-data"]="browseable=yes writable=yes"
        ["quickOS/shared-prod-data-sync"]="browseable=yes writable=yes"
        ["fastData/shared-test-data"]="browseable=yes writable=yes"
        ["fastData/shared-bulk-data"]="browseable=yes writable=yes"
        ["fastData/shared-test-data-sync"]="browseable=yes writable=yes"
    )
    SAMBA_DATASET_LIST=("quickOS/shared-prod-data" "quickOS/shared-prod-data-sync" "fastData/shared-test-data" "fastData/shared-bulk-data" "fastData/shared-test-data-sync")
    export SAMBA_DATASET_LIST SAMBA_DATASET_OPTIONS

    # NFS dataset options
    # Metadata: {"chunk_id": "phoenix_config-1.11", "keywords": ["nfs", "options"], "comment_type": "block"}
    declare -gA NFS_DATASET_OPTIONS
    NFS_DATASET_OPTIONS=(
        ["quickOS/shared-prod-data"]="rw,async,no_subtree_check,noatime"
        ["quickOS/shared-prod-data-sync"]="rw,sync,no_subtree_check,noatime"
        ["fastData/shared-test-data"]="rw,async,no_subtree_check,noatime"
        ["fastData/shared-backups"]="rw,async,no_subtree_check,noatime"
        ["fastData/shared-iso"]="rw,async,no_subtree_check,noatime"
        ["fastData/shared-bulk-data"]="rw,async,no_subtree_check,noatime"
        ["fastData/shared-test-data-sync"]="rw,sync,no_subtree_check,noatime"
    )
    NFS_DATASET_LIST=("quickOS/shared-prod-data" "quickOS/shared-prod-data-sync" "fastData/shared-test-data" "fastData/shared-iso" "fastData/shared-backups" "fastData/shared-bulk-data" "fastData/shared-test-data-sync")
    export NFS_DATASET_LIST NFS_DATASET_OPTIONS

    # Proxmox storage IDs
    # Metadata: {"chunk_id": "phoenix_config-1.12", "keywords": ["storage", "proxmox"], "comment_type": "block"}
    DEFAULT_STORAGE_ID_QUICKOS_VM="quickOS-vm"
    DEFAULT_STORAGE_ID_QUICKOS_LXC="quickOS-lxc"
    DEFAULT_STORAGE_ID_FASTDATA_BACKUP="fastData-backup"
    DEFAULT_STORAGE_ID_FASTDATA_ISO="fastData-iso"
    export DEFAULT_STORAGE_ID_QUICKOS_VM DEFAULT_STORAGE_ID_QUICKOS_LXC DEFAULT_STORAGE_ID_FASTDATA_BACKUP DEFAULT_STORAGE_ID_FASTDATA_ISO

    # ZFS ARC limit
    # Metadata: {"chunk_id": "phoenix_config-1.13", "keywords": ["zfs", "arc"], "comment_type": "block"}
    ZFS_ARC_MAX="32212254720"  # 30GB
    export ZFS_ARC_MAX

    # Base mount point
    # Metadata: {"chunk_id": "phoenix_config-1.14", "keywords": ["mount", "zfs"], "comment_type": "block"}
    MOUNT_POINT_BASE="/mnt/pve"
    export MOUNT_POINT_BASE

    echo "[$(date)] Configuration variables loaded and validated" >> "${LOGFILE:-/dev/stderr}"
}

# Note: load_config is not called automatically to allow orchestrator control