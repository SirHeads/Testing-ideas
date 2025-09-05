# Metadata: {"chunk_id": "phoenix_setup_nfs-1.0", "keywords": ["nfs", "proxmox", "exports"], "comment_type": "block"}
#!/bin/bash
# phoenix_setup_nfs.sh
# Configures NFS server and exports for Proxmox VE
# Version: 1.1.1
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_nfs.sh [--no-reboot]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Main: Configures NFS server, exports, firewall, and Proxmox storage
# Args: [--no-reboot] to skip reboot
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_nfs-1.1", "keywords": ["nfs", "proxmox"], "comment_type": "block"}
# Algorithm: NFS setup
# Installs NFS packages, configures exports, sets up firewall, adds NFS storage, and optionally reboots
# Keywords: [nfs, proxmox, exports]
# TODO: Validate NFS dataset existence and enhance mount options

# Source common functions and configuration
# Metadata: {"chunk_id": "phoenix_setup_nfs-1.2", "keywords": ["common", "config"], "comment_type": "block"}
source /usr/local/bin/common.sh || { echo "[$(date)] Error: Failed to source common.sh" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "[$(date)] Error: Failed to source phoenix_config.sh" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }

# Parse command-line arguments
# Metadata: {"chunk_id": "phoenix_setup_nfs-1.3", "keywords": ["args"], "comment_type": "block"}
NO_REBOOT=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-reboot)
      NO_REBOOT=true
      shift
      ;;
    *)
      echo "[$(date)] Error: Unknown option $1" | tee -a "${LOGFILE:-/dev/stderr}"
      exit 1
      ;;
  esac
done

# install_nfs_packages: Installs required NFS packages
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_nfs-1.4", "keywords": ["nfs", "packages"], "comment_type": "block"}
# Algorithm: NFS package installation
# Updates package lists and installs nfs-kernel-server, nfs-common, and ufw
# Keywords: [nfs, packages]
install_nfs_packages() {
  echo "[$(date)] Installing NFS packages..." >> "${LOGFILE:-/dev/stderr}"
  retry_command "apt-get update" || { echo "[$(date)] Error: Failed to update package list" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
  retry_command "apt-get install -y nfs-kernel-server nfs-common ufw" || { echo "[$(date)] Error: Failed to install NFS packages" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
  echo "[$(date)] NFS packages installed" >> "${LOGFILE:-/dev/stderr}"
}

# get_server_ip: Retrieves server IP in DEFAULT_SUBNET
# Args: None
# Returns: Server IP or exits on failure
# Metadata: {"chunk_id": "phoenix_setup_nfs-1.5", "keywords": ["network", "ip"], "comment_type": "block"}
# Algorithm: Server IP retrieval
# Identifies IP address in the specified subnet
# Keywords: [network, ip]
get_server_ip() {
  local subnet="${DEFAULT_SUBNET:-10.0.0.0/24}"
  if ! check_interface_in_subnet "$subnet"; then
    echo "[$(date)] Error: No network interface found in subnet $subnet" | tee -a "${LOGFILE:-/dev/stderr}"
    exit 1
  fi
  local ip
  ip=$(ip addr show | grep -E "inet.*$(echo "$subnet" | cut -d'/' -f1)" | awk '{print $2}' | cut -d'/' -f1 | head -1)
  if [[ -z "$ip" ]]; then
    echo "[$(date)] Error: Failed to determine server IP in subnet $subnet" | tee -a "${LOGFILE:-/dev/stderr}"
    exit 1
  fi
  echo "$ip"
}

# configure_nfs_exports: Configures NFS exports for ZFS datasets
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_nfs-1.6", "keywords": ["nfs", "exports", "zfs"], "comment_type": "block"}
# Algorithm: NFS exports configuration
# Verifies ZFS pools, filters datasets, configures exports, and restarts NFS service
# Keywords: [nfs, exports, zfs]
# TODO: Enhance export options validation
configure_nfs_exports() {
  echo "[$(date)] Configuring NFS exports..." >> "${LOGFILE:-/dev/stderr}"
  local subnet="${DEFAULT_SUBNET:-10.0.0.0/24}"
  local exports_file="/etc/exports"
  # Verify required ZFS pools
  if ! zpool list quickOS >/dev/null 2>&1; then
    echo "[$(date)] Error: ZFS pool quickOS does not exist" | tee -a "${LOGFILE:-/dev/stderr}"
    exit 1
  fi
  if ! zpool list fastData >/dev/null 2>&1; then
    echo "[$(date)] Error: ZFS pool fastData does not exist" | tee -a "${LOGFILE:-/dev/stderr}"
    exit 1
  fi
  local STORAGE_NFS_POOL=${STORAGE_NFS_POOL:-"storageNFS"}
  if ! zpool list "$STORAGE_NFS_POOL" >/dev/null 2>&1; then
    echo "[$(date)] Warning: ZFS pool $STORAGE_NFS_POOL does not exist, skipping exports for this pool" >> "${LOGFILE:-/dev/stderr}"
  else
    echo "[$(date)] Verified ZFS pool $STORAGE_NFS_POOL exists" >> "${LOGFILE:-/dev/stderr}"
  fi
  echo "[$(date)] Verified ZFS pools quickOS and fastData exist" >> "${LOGFILE:-/dev/stderr}"
  # Backup exports file
  if [[ -f "$exports_file" ]]; then
    cp "$exports_file" "$exports_file.bak.$(date +%F_%H-%M-%S)" || { echo "[$(date)] Error: Failed to backup $exports_file" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
    echo "[$(date)] Backed up $exports_file" >> "${LOGFILE:-/dev/stderr}"
  fi
  # Clear exports file
  : > "$exports_file" || { echo "[$(date)] Error: Failed to clear $exports_file" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
  # Filter datasets for existing pools
  local filtered_dataset_list=()
  for dataset_full_path in "${NFS_DATASET_LIST[@]}"; do
    local pool_name=$(echo "$dataset_full_path" | cut -d'/' -f1)
    if zpool list "$pool_name" >/dev/null 2>&1; then
      filtered_dataset_list+=("$dataset_full_path")
      echo "[$(date)] Will configure NFS export for dataset: $dataset_full_path (pool $pool_name exists)" >> "${LOGFILE:-/dev/stderr}"
    else
      echo "[$(date)] Skipping NFS export for dataset: $dataset_full_path (pool $pool_name does not exist)" >> "${LOGFILE:-/dev/stderr}"
    fi
  done
  # Configure exports
  for dataset_full_path in "${filtered_dataset_list[@]}"; do
    local zfs_path="$dataset_full_path"
    local mount_path_name=$(echo "$dataset_full_path" | tr '/' '-')
    local mount_path="$MOUNT_POINT_BASE/$mount_path_name"
    local options="${NFS_DATASET_OPTIONS[$dataset_full_path]:-rw,sync,no_subtree_check,noatime}"
    # Verify ZFS dataset
    if ! zfs list "$zfs_path" >/dev/null 2>&1; then
      echo "[$(date)] Error: ZFS dataset $zfs_path does not exist. Run phoenix_setup_zfs_datasets.sh to create it" | tee -a "${LOGFILE:-/dev/stderr}"
      zfs list -r "$(dirname "$zfs_path")" 2>&1 | tee -a "${LOGFILE:-/dev/stderr}" || true
      exit 1
    fi
    # Create mount point
    mkdir -p "$mount_path" || { echo "[$(date)] Error: Failed to create mount point $mount_path" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
    # Set ZFS mountpoint
    local current_mountpoint
    current_mountpoint=$(zfs get -H -o value mountpoint "$zfs_path")
    if [[ "$current_mountpoint" != "$mount_path" ]]; then
      echo "[$(date)] Setting mountpoint for $zfs_path from '$current_mountpoint' to '$mount_path'" >> "${LOGFILE:-/dev/stderr}"
      zfs set mountpoint="$mount_path" "$zfs_path" || { echo "[$(date)] Error: Failed to set mountpoint for $zfs_path to $mount_path" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
    else
      echo "[$(date)] Mountpoint for $zfs_path is already correctly set to '$mount_path'" >> "${LOGFILE:-/dev/stderr}"
    fi
    # Verify mount
    if ! mount | grep -q " $mount_path "; then
      echo "[$(date)] Warning: $mount_path does not appear to be mounted after setting ZFS mountpoint. Checking ZFS status..." >> "${LOGFILE:-/dev/stderr}"
      zfs mount | grep "$zfs_path" >> "${LOGFILE:-/dev/stderr}" 2>&1 || echo "[$(date)] ZFS reports $zfs_path is not mounted" >> "${LOGFILE:-/dev/stderr}"
    fi
    # Add export
    if grep -q "^$mount_path " "$exports_file"; then
      echo "[$(date)] Warning: Export line for $mount_path already exists in $exports_file, skipping addition" >> "${LOGFILE:-/dev/stderr}"
    else
      echo "$mount_path $subnet($options)" >> "$exports_file" || { echo "[$(date)] Error: Failed to add $mount_path to $exports_file" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
      echo "[$(date)] Added NFS export for $zfs_path at $mount_path with options $options" >> "${LOGFILE:-/dev/stderr}"
    fi
  done
  if [[ ${#filtered_dataset_list[@]} -eq 0 ]]; then
    echo "[$(date)] Warning: No NFS datasets found for existing pools. No exports configured" >> "${LOGFILE:-/dev/stderr}"
  fi
  # Restart NFS service
  echo "[$(date)] Refreshing and restarting NFS exports/services..." >> "${LOGFILE:-/dev/stderr}"
  retry_command "exportfs -ra" || { 
    echo "[$(date)] Error: Failed to refresh NFS exports (exportfs -ra)" | tee -a "${LOGFILE:-/dev/stderr}"
    echo "[$(date)] Contents of $exports_file:" >> "${LOGFILE:-/dev/stderr}"
    cat "$exports_file" >> "${LOGFILE:-/dev/stderr}"
    exit 1
  }
  retry_command "systemctl restart nfs-server nfs-kernel-server 2>/dev/null || systemctl restart nfs-kernel-server" || {
    echo "[$(date)] Error: Failed to restart NFS service" | tee -a "${LOGFILE:-/dev/stderr}"
    systemctl status nfs-server nfs-kernel-server 2>&1 >> "${LOGFILE:-/dev/stderr}"
    exit 1
  }
  echo "[$(date)] NFS exports configured and service restarted" >> "${LOGFILE:-/dev/stderr}"
}

# configure_nfs_firewall: Configures firewall for NFS
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_nfs-1.7", "keywords": ["firewall", "nfs"], "comment_type": "block"}
# Algorithm: Firewall configuration for NFS
# Configures ufw to allow NFS traffic from the specified subnet
# Keywords: [firewall, nfs]
configure_nfs_firewall() {
  echo "[$(date)] Configuring firewall for NFS..." >> "${LOGFILE:-/dev/stderr}"
  local subnet="${DEFAULT_SUBNET:-10.0.0.0/24}"
  if ! retry_command "ufw allow from $subnet to any port nfs"; then
    echo "[$(date)] Error: Failed to allow NFS service in firewall (ufw allow nfs)" | tee -a "${LOGFILE:-/dev/stderr}"
    echo "[$(date)] Trying fallback to specific ports..." >> "${LOGFILE:-/dev/stderr}"
    retry_command "ufw allow from $subnet to any port 111" || { echo "[$(date)] Error: Failed to allow port 111 (rpcbind) in firewall" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
    retry_command "ufw allow from $subnet to any port 2049" || { echo "[$(date)] Error: Failed to allow port 2049 (nfs) in firewall" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
  fi
  echo "[$(date)] Firewall configured for NFS" >> "${LOGFILE:-/dev/stderr}"
}

# add_nfs_storage: Adds NFS storage to Proxmox
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_nfs-1.8", "keywords": ["nfs", "proxmox", "storage"], "comment_type": "block"}
# Algorithm: NFS storage addition
# Adds NFS storage to Proxmox using pvesm for valid datasets
# Keywords: [nfs, proxmox, storage]
# TODO: Add validation for storage accessibility
add_nfs_storage() {
  echo "[$(date)] Adding NFS storage to Proxmox..." >> "${LOGFILE:-/dev/stderr}"
  if ! command -v pvesm >/dev/null 2>&1; then
    echo "[$(date)] Error: pvesm command not found. Ensure this script is running on a Proxmox VE node" | tee -a "${LOGFILE:-/dev/stderr}"
    exit 1
  fi
  local server_ip
  server_ip=$(get_server_ip)
  local filtered_dataset_list=()
  for dataset_full_path in "${NFS_DATASET_LIST[@]}"; do
    local pool_name=$(echo "$dataset_full_path" | cut -d'/' -f1)
    if zpool list "$pool_name" >/dev/null 2>&1; then
      filtered_dataset_list+=("$dataset_full_path")
      echo "[$(date)] Will add NFS storage for dataset: $dataset_full_path (pool $pool_name exists)" >> "${LOGFILE:-/dev/stderr}"
    else
      echo "[$(date)] Skipping NFS storage addition for dataset: $dataset_full_path (pool $pool_name does not exist)" >> "${LOGFILE:-/dev/stderr}"
    fi
  done
  for dataset_full_path in "${filtered_dataset_list[@]}"; do
    local storage_info="${DATASET_STORAGE_TYPES[$dataset_full_path]}"
    if [[ -z "$storage_info" ]]; then
      echo "[$(date)] Skipping $dataset_full_path for NFS storage (not defined in DATASET_STORAGE_TYPES)" >> "${LOGFILE:-/dev/stderr}"
      continue
    fi
    local storage_type=$(echo "$storage_info" | cut -d':' -f1)
    local content_type=$(echo "$storage_info" | cut -d':' -f2)
    if [[ "$storage_type" != "nfs" ]]; then
      echo "[$(date)] Skipping $dataset_full_path for NFS storage (defined as $storage_type in DATASET_STORAGE_TYPES)" >> "${LOGFILE:-/dev/stderr}"
      continue
    fi
    local storage_name="nfs-$(echo "$dataset_full_path" | tr '/' '-')"
    local mount_path_name=$(echo "$dataset_full_path" | tr '/' '-')
    local export_path="$MOUNT_POINT_BASE/$mount_path_name"
    echo "[$(date)] Checking if export $export_path is available on $server_ip..." >> "${LOGFILE:-/dev/stderr}"
    if ! showmount -e "$server_ip" | grep -q "$(echo "$export_path" | sed 's/\//\\\//g')"; then
      echo "[$(date)] Error: NFS export $export_path not available on $server_ip according to showmount" | tee -a "${LOGFILE:-/dev/stderr}"
      echo "[$(date)] Debug: Output of 'showmount -e $server_ip':" >> "${LOGFILE:-/dev/stderr}"
      showmount -e "$server_ip" 2>&1 >> "${LOGFILE:-/dev/stderr}"
      echo "[$(date)] Debug: Checking if NFS service is running:" >> "${LOGFILE:-/dev/stderr}"
      systemctl is-active nfs-server nfs-kernel-server 2>&1 >> "${LOGFILE:-/dev/stderr}"
      exit 1
    fi
    echo "[$(date)] Confirmed export $export_path is available on $server_ip" >> "${LOGFILE:-/dev/stderr}"
    if pvesm status | grep -q "^$storage_name "; then
      echo "[$(date)] Proxmox storage $storage_name already exists, skipping addition" >> "${LOGFILE:-/dev/stderr}"
      continue
    fi
    local local_mount="/mnt/nfs/$storage_name"
    mkdir -p "$local_mount" || { echo "[$(date)] Error: Failed to create local mount point $local_mount for Proxmox NFS storage" | tee -a "${LOGFILE:-/dev/stderr}"; exit 1; }
    echo "[$(date)] Adding NFS storage $storage_name to Proxmox..." >> "${LOGFILE:-/dev/stderr}"
    retry_command "pvesm add nfs $storage_name --server $server_ip --export $export_path --content $content_type --path $local_mount --options vers=4,soft,timeo=30,retrans=3" || {
      echo "[$(date)] Error: Failed to add NFS storage $storage_name using pvesm" | tee -a "${LOGFILE:-/dev/stderr}"
      echo "[$(date)] Debug: pvesm command that failed:" >> "${LOGFILE:-/dev/stderr}"
      echo "pvesm add nfs $storage_name --server $server_ip --export $export_path --content $content_type --path $local_mount --options vers=4,soft,timeo=30,retrans=3" >> "${LOGFILE:-/dev/stderr}"
      exit 1
    }
    echo "[$(date)] Successfully added NFS storage $storage_name for $export_path at $local_mount with content $content_type" >> "${LOGFILE:-/dev/stderr}"
  done
  if [[ ${#filtered_dataset_list[@]} -eq 0 ]]; then
    echo "[$(date)] Warning: No NFS datasets found for existing pools. No Proxmox storage added" >> "${LOGFILE:-/dev/stderr}"
  fi
}

# main: Executes NFS setup steps
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_nfs-1.9", "keywords": ["nfs", "proxmox"], "comment_type": "block"}
# Algorithm: NFS setup orchestration
# Coordinates package installation, exports, firewall, storage addition, and optional reboot
# Keywords: [nfs, proxmox, setup]
main() {
  # setup_logging # Assume handled by orchestrator
  check_root
  install_nfs_packages
  configure_nfs_exports
  configure_nfs_firewall
  add_nfs_storage
  if [[ "$NO_REBOOT" == false ]]; then
    echo "[$(date)] Forcing reboot to apply NFS changes in 10 seconds. Press Ctrl+C to cancel" | tee -a "${LOGFILE:-/dev/stderr}"
    sleep 10
    reboot
  else
    echo "[$(date)] Reboot skipped due to --no-reboot flag. Please reboot manually to apply NFS changes" | tee -a "${LOGFILE:-/dev/stderr}"
  fi
}

main
echo "[$(date)] Successfully completed NFS setup" >> "${LOGFILE:-/dev/stderr}"
exit 0