#!/bin/bash
# phoenix_setup_zfs_datasets.sh
# Configures ZFS datasets on Proxmox VE
# Version: 1.3.2 (Fixed ZFS property handling for dataset creation)
# Author: Heads, Grok, Devstral

# Main: Configures ZFS datasets for quickOS, fastData, and storageNFS pools
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_zfs_datasets-1.1", "keywords": ["zfs", "dataset"], "comment_type": "block"}
# Algorithm: ZFS dataset configuration
# Loads configuration, creates datasets for quickOS and fastData, adds Proxmox storage
# Keywords: [zfs, dataset, proxmox]
# TODO: Validate dataset properties and handle missing configuration

# Source common functions and configuration
source /usr/local/bin/common.sh || { echo "[$(date)] Error: Failed to source common.sh" | tee -a /dev/stderr; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "[$(date)] Error: Failed to source phoenix_config.sh" | tee -a /dev/stderr; exit 1; }

# Load configuration to get dataset lists and properties
load_config

# Ensure script runs only once
# Metadata: {"chunk_id": "phoenix_setup_zfs_datasets-1.2", "keywords": ["state"], "comment_type": "block"}
#STATE_FILE="/var/log/proxmox_setup_state"
#if grep -Fx "phoenix_setup_zfs_datasets" "$STATE_FILE" >/dev/null 2>&1; then
#  echo "[$(date)] phoenix_setup_zfs_datasets already executed, skipping" >> "${LOGFILE:-/dev/stderr}"
#  exit 0
#fi

# check_pvesm: Checks for pvesm availability
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_zfs_datasets-1.3", "keywords": ["pvesm", "proxmox"], "comment_type": "block"}
# Algorithm: pvesm check
# Verifies pvesm command availability
# Keywords: [pvesm, proxmox]
check_pvesm() {
  if ! command -v pvesm >/dev/null 2>&1; then
    echo "[$(date)] Error: pvesm command not found" | tee -a "${LOGFILE:-/dev/stderr}"
    exit 1
  fi
  echo "[$(date)] Verified pvesm availability" >> "${LOGFILE:-/dev/stderr}"
}

# create_quickos_datasets: Creates datasets for quickOS pool
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_zfs_datasets-1.4", "keywords": ["zfs", "quickOS"], "comment_type": "block"}
# Algorithm: quickOS dataset creation
# Creates datasets for quickOS pool with specified properties
# Keywords: [zfs, quickOS]
create_quickos_datasets() {
  local pool="$QUICKOS_POOL"
  local datasets=("${QUICKOS_DATASET_LIST[@]}")
  if zfs_pool_exists "$pool"; then
    for dataset in "${datasets[@]}"; do
      local mountpoint="$MOUNT_POINT_BASE/$dataset"
      local properties
      IFS=',' read -r -a properties <<< "${QUICKOS_DATASET_PROPERTIES[$dataset]}"
      local zfs_create_props=()
      for prop in "${properties[@]}"; do
        zfs_create_props+=("-o" "$prop")
      done
      if ! zfs_dataset_exists "$pool/$dataset"; then
        create_zfs_dataset "$pool" "$dataset" "$mountpoint" "${zfs_create_props[@]}"
        echo "[$(date)] Created ZFS dataset: $pool/$dataset with mountpoint $mountpoint" >> "${LOGFILE:-/dev/stderr}"
      else
        set_zfs_properties "$pool/$dataset" "${properties[@]}"
        echo "[$(date)] Updated properties for ZFS dataset: $pool/$dataset" >> "${LOGFILE:-/dev/stderr}"
      fi
    done
  else
    echo "[$(date)] Error: Pool $pool does not exist" | tee -a "${LOGFILE:-/dev/stderr}"
    exit 1
  fi
}

# create_fastdata_datasets: Creates datasets for fastData pool
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_zfs_datasets-1.5", "keywords": ["zfs", "fastData"], "comment_type": "block"}
# Algorithm: fastData dataset creation
# Creates datasets for fastData pool with specified properties
# Keywords: [zfs, fastData]
create_fastdata_datasets() {
  local pool="$FASTDATA_POOL"
  local datasets=("${FASTDATA_DATASET_LIST[@]}")
  if zfs_pool_exists "$pool"; then
    for dataset in "${datasets[@]}"; do
      local mountpoint="$MOUNT_POINT_BASE/$dataset"
      local properties
      IFS=',' read -r -a properties <<< "${FASTDATA_DATASET_PROPERTIES[$dataset]}"
      local zfs_create_props=()
      for prop in "${properties[@]}"; do
        zfs_create_props+=("-o" "$prop")
      done
      if ! zfs_dataset_exists "$pool/$dataset"; then
        create_zfs_dataset "$pool" "$dataset" "$mountpoint" "${zfs_create_props[@]}"
        echo "[$(date)] Created ZFS dataset: $pool/$dataset with mountpoint $mountpoint" >> "${LOGFILE:-/dev/stderr}"
      else
        set_zfs_properties "$pool/$dataset" "${properties[@]}"
        echo "[$(date)] Updated properties for ZFS dataset: $pool/$dataset" >> "${LOGFILE:-/dev/stderr}"
      fi
    done
  else
    echo "[$(date)] Error: Pool $pool does not exist" | tee -a "${LOGFILE:-/dev/stderr}"
    exit 1
  fi
}

# add_proxmox_storage: Adds Proxmox storage for datasets
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_zfs_datasets-1.6", "keywords": ["proxmox", "storage"], "comment_type": "block"}
# Algorithm: Proxmox storage addition
# Adds Proxmox storage for quickOS and fastData datasets using pvesm
# Keywords: [proxmox, storage]
# add_proxmox_storage: Adds Proxmox storage for datasets
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_zfs_datasets-1.6", "keywords": ["proxmox", "storage"], "comment_type": "block"}
# Algorithm: Proxmox storage addition
# Adds configured ZFS datasets as Proxmox storage (zfspool, dir, cifs)
# Keywords: [proxmox, storage, zfs]
# TODO: Add validation for storage type compatibility
add_proxmox_storage() {
  check_pvesm

  # Process quickOS datasets
  for dataset in "${QUICKOS_DATASET_LIST[@]}"; do
    local full_dataset="quickOS/$dataset"
    echo "[$(date)] DEBUG: Processing dataset $full_dataset" >> "${LOGFILE:-/dev/stderr}"
    local storage_info="${DATASET_STORAGE_TYPES[$full_dataset]}"
    echo "[$(date)] DEBUG: storage_info='$storage_info' for $full_dataset" >> "${LOGFILE:-/dev/stderr}"
    if [[ -z "$storage_info" ]]; then
      echo "[$(date)] ERROR: No storage info defined for $full_dataset, skipping" >> "${LOGFILE:-/dev/stderr}"
      continue
    fi
    if ! echo "$storage_info" | grep -q ":"; then
      echo "[$(date)] ERROR: Invalid storage_info format for $full_dataset: '$storage_info', skipping" >> "${LOGFILE:-/dev/stderr}"
      continue
    fi
    local storage_type=$(echo "$storage_info" | cut -d':' -f1)
    local content_type=$(echo "$storage_info" | cut -d':' -f2)
    echo "[$(date)] DEBUG: storage_type='$storage_type', content_type='$content_type' for $full_dataset" >> "${LOGFILE:-/dev/stderr}"
    local storage_id="zfs-$(echo "$dataset" | tr '/' '-')"
    echo "[$(date)] DEBUG: storage_id='$storage_id' for $full_dataset" >> "${LOGFILE:-/dev/stderr}"
    if ! pvesm status | grep -q "^$storage_id"; then
      echo "[$(date)] DEBUG: Adding storage $storage_id" >> "${LOGFILE:-/dev/stderr}"
      if [[ "$storage_type" == "dir" ]]; then
        local mountpoint="$MOUNT_POINT_BASE/$dataset"
        if ! mountpoint -q "$mountpoint"; then
          echo "[$(date)] DEBUG: Setting mountpoint $mountpoint for $QUICKOS_POOL/$dataset" >> "${LOGFILE:-/dev/stderr}"
          zfs set mountpoint="$mountpoint" "$QUICKOS_POOL/$dataset" || {
            echo "[$(date)] ERROR: Failed to set mountpoint $mountpoint for $QUICKOS_POOL/$dataset" | tee -a "${LOGFILE:-/dev/stderr}"
            exit 1
          }
          zfs mount "$QUICKOS_POOL/$dataset" || {
            echo "[$(date)] ERROR: Failed to mount $QUICKOS_POOL/$dataset" | tee -a "${LOGFILE:-/dev/stderr}"
            exit 1
          }
        fi
        echo "[$(date)] DEBUG: Running pvesm add $storage_type $storage_id -path $mountpoint -content $content_type" >> "${LOGFILE:-/dev/stderr}"
        retry_command "pvesm add $storage_type $storage_id -path $mountpoint -content $content_type" || {
          echo "[$(date)] ERROR: Failed to add $storage_type storage $storage_id" | tee -a "${LOGFILE:-/dev/stderr}"
          exit 1
        }
        echo "[$(date)] Added Proxmox $storage_type storage: $storage_id for $mountpoint with content $content_type" >> "${LOGFILE:-/dev/stderr}"
      elif [[ "$storage_type" == "zfspool" ]]; then
        echo "[$(date)] DEBUG: Running pvesm add $storage_type $storage_id -pool $QUICKOS_POOL/$dataset -content $content_type" >> "${LOGFILE:-/dev/stderr}"
        retry_command "pvesm add $storage_type $storage_id -pool $QUICKOS_POOL/$dataset -content $content_type" || {
          echo "[$(date)] ERROR: Failed to add $storage_type storage $storage_id" | tee -a "${LOGFILE:-/dev/stderr}"
          exit 1
        }
        echo "[$(date)] Added Proxmox $storage_type storage: $storage_id for $QUICKOS_POOL/$dataset with content $content_type" >> "${LOGFILE:-/dev/stderr}"
      elif [[ "$storage_type" == "cifs" ]]; then
        echo "[$(date)] INFO: Skipping CIFS storage addition for $full_dataset ($storage_id). Will be handled by phoenix_setup_samba.sh." >> "${LOGFILE:-/dev/stderr}"
      else
        echo "[$(date)] WARNING: Unsupported storage type '$storage_type' for dataset $full_dataset ($storage_id). Skipping." >> "${LOGFILE:-/dev/stderr}"
      fi
    else
      echo "[$(date)] Proxmox storage $storage_id already exists, skipping" >> "${LOGFILE:-/dev/stderr}"
    fi
  done

  # Process fastData datasets
  for dataset in "${FASTDATA_DATASET_LIST[@]}"; do
    local full_dataset="fastData/$dataset"
    echo "[$(date)] DEBUG: Processing dataset $full_dataset" >> "${LOGFILE:-/dev/stderr}"
    local storage_info="${DATASET_STORAGE_TYPES[$full_dataset]}"
    echo "[$(date)] DEBUG: storage_info='$storage_info' for $full_dataset" >> "${LOGFILE:-/dev/stderr}"
    if [[ -z "$storage_info" ]]; then
      echo "[$(date)] Skipping $full_dataset for Proxmox storage (likely handled by NFS)" >> "${LOGFILE:-/dev/stderr}"
      continue
    fi
    if ! echo "$storage_info" | grep -q ":"; then
      echo "[$(date)] ERROR: Invalid storage_info format for $full_dataset: '$storage_info', skipping" >> "${LOGFILE:-/dev/stderr}"
      continue
    fi
    local storage_type=$(echo "$storage_info" | cut -d':' -f1)
    local content_type=$(echo "$storage_info" | cut -d':' -f2)
    echo "[$(date)] DEBUG: storage_type='$storage_type', content_type='$content_type' for $full_dataset" >> "${LOGFILE:-/dev/stderr}"
    local storage_id="zfs-$(echo "$dataset" | tr '/' '-')"
    echo "[$(date)] DEBUG: storage_id='$storage_id' for $full_dataset" >> "${LOGFILE:-/dev/stderr}"
    if ! pvesm status | grep -q "^$storage_id"; then
      echo "[$(date)] DEBUG: Adding storage $storage_id" >> "${LOGFILE:-/dev/stderr}"
      if [[ "$storage_type" == "dir" ]]; then
        local mountpoint="$MOUNT_POINT_BASE/$dataset"
        if ! mountpoint -q "$mountpoint"; then
          echo "[$(date)] DEBUG: Setting mountpoint $mountpoint for $FASTDATA_POOL/$dataset" >> "${LOGFILE:-/dev/stderr}"
          zfs set mountpoint="$mountpoint" "$FASTDATA_POOL/$dataset" || {
            echo "[$(date)] ERROR: Failed to set mountpoint $mountpoint for $FASTDATA_POOL/$dataset" | tee -a "${LOGFILE:-/dev/stderr}"
            exit 1
          }
          zfs mount "$FASTDATA_POOL/$dataset" || {
            echo "[$(date)] ERROR: Failed to mount $FASTDATA_POOL/$dataset" | tee -a "${LOGFILE:-/dev/stderr}"
            exit 1
          }
        fi
        echo "[$(date)] DEBUG: Running pvesm add $storage_type $storage_id -path $mountpoint -content $content_type" >> "${LOGFILE:-/dev/stderr}"
        retry_command "pvesm add $storage_type $storage_id -path $mountpoint -content $content_type" || {
          echo "[$(date)] ERROR: Failed to add $storage_type storage $storage_id" | tee -a "${LOGFILE:-/dev/stderr}"
          exit 1
        }
        echo "[$(date)] Added Proxmox $storage_type storage: $storage_id for $mountpoint with content $content_type" >> "${LOGFILE:-/dev/stderr}"
      elif [[ "$storage_type" == "zfspool" ]]; then
        echo "[$(date)] DEBUG: Running pvesm add $storage_type $storage_id -pool $FASTDATA_POOL/$dataset -content $content_type" >> "${LOGFILE:-/dev/stderr}"
        retry_command "pvesm add $storage_type $storage_id -pool $FASTDATA_POOL/$dataset -content $content_type" || {
          echo "[$(date)] ERROR: Failed to add $storage_type storage $storage_id" | tee -a "${LOGFILE:-/dev/stderr}"
          exit 1
        }
        echo "[$(date)] Added Proxmox $storage_type storage: $storage_id for $FASTDATA_POOL/$dataset with content $content_type" >> "${LOGFILE:-/dev/stderr}"
      elif [[ "$storage_type" == "cifs" ]]; then
        echo "[$(date)] INFO: Skipping CIFS storage addition for $full_dataset ($storage_id). Will be handled by phoenix_setup_samba.sh." >> "${LOGFILE:-/dev/stderr}"
      else
        echo "[$(date)] WARNING: Unsupported storage type '$storage_type' for dataset $full_dataset ($storage_id). Skipping." >> "${LOGFILE:-/dev/stderr}"
      fi
    else
      echo "[$(date)] Proxmox storage $storage_id already exists, skipping" >> "${LOGFILE:-/dev/stderr}"
    fi
  done
}

# --- MAIN EXECUTION BLOCK ADDED ---
# Main execution
# Metadata: {"chunk_id": "phoenix_setup_zfs_datasets-1.7", "keywords": ["main", "execution"], "comment_type": "block"}
# Algorithm: Main execution flow
# Calls functions to create datasets and add Proxmox storage
# Keywords: [main, execution]
# TODO: Add overall error handling

# Create datasets
echo "[$(date)] Starting dataset creation..." >> "${LOGFILE:-/dev/stderr}"
create_quickos_datasets
create_fastdata_datasets
echo "[$(date)] Dataset creation completed." >> "${LOGFILE:-/dev/stderr}"

# Add Proxmox storage entries
echo "[$(date)] Starting Proxmox storage addition..." >> "${LOGFILE:-/dev/stderr}"
add_proxmox_storage
echo "[$(date)] Proxmox storage addition completed." >> "${LOGFILE:-/dev/stderr}"

echo "[$(date)] Successfully completed phoenix_setup_zfs_datasets.sh" >> "${LOGFILE:-/dev/stderr}"
exit 0
# --- END OF MAIN EXECUTION BLOCK ---