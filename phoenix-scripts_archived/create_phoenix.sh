# Metadata: {"chunk_id": "create_phoenix-1.0", "keywords": ["proxmox", "vm_rebuild", "orchestration"], "comment_type": "block"}
#!/bin/bash
# create_phoenix.sh
# Orchestrates the execution of all Proxmox VE setup scripts for the Phoenix server
# Version: 1.3.0 (Integrated phoenix_create_storage.sh, Added phoenix_fly.sh and reboot)
# Author: Heads, Grok, Devstral

# Main: Orchestrates Proxmox VE setup for Phoenix server
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "create_phoenix-1.1", "keywords": ["orchestration", "proxmox"], "comment_type": "block"}
# Algorithm: Script orchestration
# Sources configs, prompts for credentials and drives, executes setup scripts, runs animation, reboots
# Keywords: [orchestration, proxmox, zfs]
# TODO: Implement retry mechanism for failed scripts and enhance password validation

# Configuration
# Metadata: {"chunk_id": "create_phoenix-1.2", "keywords": ["config"], "comment_type": "block"}
LOGFILE="/var/log/proxmox_setup.log"
STATE_FILE="/var/log/proxmox_setup_state"

# Source common functions and configuration
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh" | tee -a "$LOGFILE"; exit 1; }
echo "[$(date)] Common functions sourced" >> "$LOGFILE"
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh" | tee -a "$LOGFILE"; exit 1; }
echo "[$(date)] Configuration file sourced" >> "$LOGFILE"

# Load configuration variables
load_config
echo "[$(date)] Configuration variables loaded and validated" >> "$LOGFILE"

# check_root: Ensures script runs as root
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "create_phoenix-1.3", "keywords": ["root", "auth"], "comment_type": "block"}
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root" | tee -a "$LOGFILE"
        exit 1
    fi
    echo "[$(date)] Verified script is running as root" >> "$LOGFILE"
}

# prompt_for_credentials: Prompts for admin and SMB credentials if not set
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "create_phoenix-1.4", "keywords": ["credentials", "auth"], "comment_type": "block"}
# Algorithm: Credential prompting
# Prompts for admin username, password, SMB password, and SSH key
# Keywords: [credentials, auth]
# TODO: Add regex for complex password validation
prompt_for_credentials() {
    if [[ -z "$ADMIN_USERNAME" ]]; then
        read -p "Enter admin username for phoenix_create_admin_user.sh [heads]: " ADMIN_USERNAME
        ADMIN_USERNAME=${ADMIN_USERNAME:-heads}
        echo "[$(date)] Set ADMIN_USERNAME to $ADMIN_USERNAME" >> "$LOGFILE"
    fi
    if [[ -z "$ADMIN_PASSWORD" ]]; then
        read -s -p "Enter password for admin user (min 8 chars, 1 special char) [Kick@$$2025]: " ADMIN_PASSWORD
        echo
        ADMIN_PASSWORD=${ADMIN_PASSWORD:-'Kick@$$2025'}
        if [[ ! "$ADMIN_PASSWORD" =~ [[:punct:]] ]] || [[ ${#ADMIN_PASSWORD} -lt 8 ]]; then
            echo "Error: Password must be at least 8 characters long and contain at least one special character." | tee -a "$LOGFILE"
            exit 1
        fi
        echo "[$(date)] Set ADMIN_PASSWORD (validated)" >> "$LOGFILE"
    fi
    if [[ -z "$SMB_PASSWORD" ]]; then
        read -s -p "Enter password for SMB user ($SMB_USER) [Kick@$$2025]: " SMB_PASSWORD
        echo
        SMB_PASSWORD=${SMB_PASSWORD:-'Kick@$$2025'}
        if [[ ! "$SMB_PASSWORD" =~ [[:punct:]] ]] || [[ ${#SMB_PASSWORD} -lt 8 ]]; then
            echo "Error: SMB Password must be at least 8 characters long and contain at least one special character." | tee -a "$LOGFILE"
            exit 1
        fi
        echo "[$(date)] Set SMB_PASSWORD (validated)" >> "$LOGFILE"
    fi
    if [[ -z "$ADMIN_SSH_PUBLIC_KEY" ]]; then
        read -p "Enter path to SSH public key file for admin user (or press Enter to skip): " ADMIN_SSH_PUBLIC_KEY_PATH
        if [[ -n "$ADMIN_SSH_PUBLIC_KEY_PATH" ]] && [[ -f "$ADMIN_SSH_PUBLIC_KEY_PATH" ]]; then
            ADMIN_SSH_PUBLIC_KEY=$(cat "$ADMIN_SSH_PUBLIC_KEY_PATH")
            echo "[$(date)] Loaded SSH public key from $ADMIN_SSH_PUBLIC_KEY_PATH" >> "$LOGFILE"
        else
            ADMIN_SSH_PUBLIC_KEY=""
            echo "[$(date)] No SSH public key provided or file not found, skipping SSH key setup." >> "$LOGFILE"
        fi
    fi
}

# prompt_for_drives: Prompts for drive selection for ZFS pools
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "create_phoenix-1.5", "keywords": ["drives", "zfs"], "comment_type": "block"}
# Algorithm: Drive selection
# Discovers NVMe drives, deduplicates, prompts for quickOS and fastData drives
# Keywords: [drives, zfs, nvme]
# TODO: Add support for non-NVMe drives
prompt_for_drives() {
    if [[ -n "$QUICKOS_DRIVES_INPUT" ]] && [[ -n "$FASTDATA_DRIVE_INPUT" ]]; then
        echo "[$(date)] Drive selections provided via environment variables, skipping prompts." >> "$LOGFILE"
        return 0
    fi
    mapfile -t all_nvme_links < <(ls -1 /dev/disk/by-id/nvme-* 2>/dev/null | grep -v -E '\-part[0-9]+$' || true)
    if [[ ${#all_nvme_links[@]} -eq 0 ]]; then
        echo "[$(date)] Error: No NVMe drives found in /dev/disk/by-id/" | tee -a "$LOGFILE"
        exit 1
    fi
    declare -A best_link_for_device
    for link_path in "${all_nvme_links[@]}"; do
        device_node=$(readlink -f "$link_path" 2>/dev/null)
        if [[ -z "$device_node" ]] || [[ ! -b "$device_node" ]]; then
            continue
        fi
        link_name=$(basename "$link_path")
        current_is_model_serial=false
        if [[ "$link_name" == nvme-*Samsung* || "$link_name" == nvme-*Crucial* || "$link_name" == nvme-*Intel* || "$link_name" == nvme-*WD* ]]; then
             current_is_model_serial=true
        fi
        existing_link="${best_link_for_device[$device_node]}"
        if [[ -z "$existing_link" ]] || { [[ "$current_is_model_serial" == true ]] && [[ "$existing_link" != nvme-*Samsung* ]] && [[ "$existing_link" != nvme-*Crucial* ]] && [[ "$existing_link" != nvme-*Intel* ]] && [[ "$existing_link" != nvme-*WD* ]]; }; then
            best_link_for_device["$device_node"]="$link_path"
        fi
    done
    available_drives=()
    for drive_link_path in "${best_link_for_device[@]}"; do
         available_drives+=("$drive_link_path")
    done
    if [[ ${#available_drives[@]} -eq 0 ]]; then
        echo "[$(date)] Error: No usable NVMe drives found after deduplication." | tee -a "$LOGFILE"
        exit 1
    fi
    echo "Available NVMe drives:"
    for i in "${!available_drives[@]}"; do
        drive_path=$(readlink -f "${available_drives[$i]}")
        size=$(lsblk -dn -o SIZE "$drive_path" 2>/dev/null || echo "Unknown")
        echo "  $((i+1)). ${available_drives[$i]##*/} ($size)"
    done
    while true; do
        read -p "Enter two numbers for quickOS pool drives (e.g., 1 2): " QUICKOS_DRIVES_INPUT
        if [[ $QUICKOS_DRIVES_INPUT =~ ^[0-9]+[[:space:]]+[0-9]+$ ]]; then
            read -ra quickos_indices <<< "$QUICKOS_DRIVES_INPUT"
            idx1=$((quickos_indices[0] - 1))
            idx2=$((quickos_indices[1] - 1))
            if [[ $idx1 -ge 0 ]] && [[ $idx1 -lt ${#available_drives[@]} ]] && \
               [[ $idx2 -ge 0 ]] && [[ $idx2 -lt ${#available_drives[@]} ]] && \
               [[ $idx1 -ne $idx2 ]]; then
                QUICKOS_DRIVE1="${available_drives[$idx1]}"
                QUICKOS_DRIVE2="${available_drives[$idx2]}"
                echo "[$(date)] Selected quickOS drives: ${QUICKOS_DRIVE1##*/}, ${QUICKOS_DRIVE2##*/}" >> "$LOGFILE"
                break
            fi
        fi
        echo "Invalid input. Please enter two different numbers corresponding to available drives."
    done
    remaining_drives=()
    for drive in "${available_drives[@]}"; do
        if [[ "$drive" != "$QUICKOS_DRIVE1" ]] && [[ "$drive" != "$QUICKOS_DRIVE2" ]]; then
            remaining_drives+=("$drive")
        fi
    done
    if [[ ${#remaining_drives[@]} -eq 0 ]]; then
        echo "[$(date)] Error: No remaining drives available for fastData pool." | tee -a "$LOGFILE"
        exit 1
    fi
    echo "Available NVMe drives (excluding quickOS drives):"
    for i in "${!remaining_drives[@]}"; do
        drive_path=$(readlink -f "${remaining_drives[$i]}")
        size=$(lsblk -dn -o SIZE "$drive_path" 2>/dev/null || echo "Unknown")
        echo "  $((i+1)). ${remaining_drives[$i]##*/} ($size)"
    done
    while true; do
        read -p "Enter number for fastData pool drive (e.g., 3): " FASTDATA_DRIVE_INPUT
        if [[ $FASTDATA_DRIVE_INPUT =~ ^[0-9]+$ ]]; then
            idx=$((FASTDATA_DRIVE_INPUT - 1))
            if [[ $idx -ge 0 ]] && [[ $idx -lt ${#remaining_drives[@]} ]]; then
                FASTDATA_DRIVE="${remaining_drives[$idx]}"
                echo "[$(date)] Selected fastData drive: ${FASTDATA_DRIVE##*/}" >> "$LOGFILE"
                break
            fi
        fi
        echo "Invalid input. Please enter a number corresponding to an available drive."
    done
    export QUICKOS_DRIVE1 QUICKOS_DRIVE2 FASTDATA_DRIVE
    QUICKOS_DRIVES_VALIDATED="$QUICKOS_DRIVE1 $QUICKOS_DRIVE2"
    FASTDATA_DRIVE_VALIDATED="$FASTDATA_DRIVE"
    export QUICKOS_DRIVES_VALIDATED FASTDATA_DRIVE_VALIDATED
}

# validate_drives: Validates selected drives are not in use by ZFS
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "create_phoenix-1.6", "keywords": ["drives", "zfs"], "comment_type": "block"}
validate_drives() {
    echo "[$(date)] Validating selected drives are not in use by existing ZFS pools..." >> "$LOGFILE"
    ALL_SELECTED_DRIVES=("$QUICKOS_DRIVE1" "$QUICKOS_DRIVE2" "$FASTDATA_DRIVE")
    for drive_path in "${ALL_SELECTED_DRIVES[@]}"; do
        if zpool status | grep -q "$(basename "$drive_path")"; then
             echo "[$(date)] Error: Drive $drive_path is already in use by another ZFS pool." | tee -a "$LOGFILE"
             exit 1
        fi
    done
    echo "[$(date)] Drive validation passed." >> "$LOGFILE"
}

# is_script_completed: Checks if a script has been completed
# Args: $1: Script command
# Returns: 0 if completed, 1 if not
# Metadata: {"chunk_id": "create_phoenix-1.7", "keywords": ["state", "execution"], "comment_type": "block"}
is_script_completed() {
    local script_cmd="$1"
    if [[ -f "$STATE_FILE" ]] && grep -Fxq "$script_cmd" "$STATE_FILE"; then
        return 0
    else
        return 1
    fi
}

# mark_script_completed: Marks a script as completed in the state file
# Args: $1: Script command
# Returns: None
# Metadata: {"chunk_id": "create_phoenix-1.8", "keywords": ["state", "execution"], "comment_type": "block"}
mark_script_completed() {
    local script_cmd="$1"
    echo "$script_cmd" >> "$STATE_FILE"
    echo "[$(date)] Marked script as completed: $script_cmd" >> "$LOGFILE"
}

# cleanup_state: Removes state file after completion
# Args: None
# Returns: None
# Metadata: {"chunk_id": "create_phoenix-1.9", "keywords": ["state", "cleanup"], "comment_type": "block"}
cleanup_state() {
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        echo "[$(date)] Removed state file: $STATE_FILE" >> "$LOGFILE"
    fi
}

# Main execution
# Metadata: {"chunk_id": "create_phoenix-1.10", "keywords": ["orchestration"], "comment_type": "block"}
# Algorithm: Script execution loop
# Executes scripts in order, skips completed ones, cleans up state
# Keywords: [orchestration, execution]
# TODO: Avoid 'local' in loop to prevent scope issues
touch "$LOGFILE" || { echo "Error: Cannot create log file $LOGFILE"; exit 1; }
chmod 644 "$LOGFILE"
echo "[$(date)] Initialized logging for create_phoenix.sh" >> "$LOGFILE"
touch "$STATE_FILE" || { echo "Error: Cannot create state file $STATE_FILE" | tee -a "$LOGFILE"; exit 1; }
chmod 644 "$STATE_FILE"
check_root
prompt_for_credentials
prompt_for_drives
validate_drives
SCRIPTS_TO_RUN=(
    "/usr/local/bin/phoenix_proxmox_initial_setup.sh"
    "/usr/local/bin/phoenix_install_nvidia_driver.sh"
    "/usr/local/bin/phoenix_create_admin_user.sh -u \"$ADMIN_USERNAME\" -p \"$ADMIN_PASSWORD\"${ADMIN_SSH_PUBLIC_KEY:+ -s \"$ADMIN_SSH_PUBLIC_KEY\"}"
    "if ! dpkg-query -W zfsutils-linux > /dev/null 2>&1; then apt-get update && apt-get install -y zfsutils-linux; fi"
    "/usr/local/bin/phoenix_setup_zfs_pools.sh -q \"$QUICKOS_DRIVES_VALIDATED\" -f \"$FASTDATA_DRIVE_VALIDATED\""
    "/usr/local/bin/phoenix_setup_zfs_datasets.sh"
    "/usr/local/bin/phoenix_create_storage.sh"
    "/usr/local/bin/phoenix_setup_nfs.sh --no-reboot"
    "/usr/local/bin/phoenix_setup_samba.sh -p \"$SMB_PASSWORD\""
)
echo "[$(date)] Starting script execution loop..." >> "$LOGFILE"
for script_cmd in "${SCRIPTS_TO_RUN[@]}"; do
    script_path_to_check=""
    exit_code=0
    echo "[$(date)] Checking script: $script_cmd" >> "$LOGFILE"
    if is_script_completed "$script_cmd"; then
        echo "[$(date)] Skipping completed script: $script_cmd" >> "$LOGFILE"
        continue
    fi
    script_path_to_check=$(echo "$script_cmd" | awk '{print $1}')
    if [[ -n "$script_path_to_check" ]] && [[ "$script_path_to_check" != "if" ]] && [[ ! -f "$script_path_to_check" ]]; then
        echo "[$(date)] Error: Script file not found: $script_path_to_check" | tee -a "$LOGFILE"
        exit 1
    fi
    echo "[$(date)] Executing: $script_cmd" >> "$LOGFILE"
    eval "$script_cmd"
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo "[$(date)] Error: Failed to execute $script_cmd (exit code: $exit_code). Exiting." | tee -a "$LOGFILE"
        exit 1
    fi
    mark_script_completed "$script_cmd"
done
echo "[$(date)] All scripts executed successfully." >> "$LOGFILE"
cleanup_state
echo "Phoenix Proxmox VE setup completed successfully. State file removed for clean manual rerun." | tee -a "$LOGFILE"

# Run Phoenix animation and reboot
# Metadata: {"chunk_id": "create_phoenix-1.11", "keywords": ["animation", "reboot"], "comment_type": "block"}
# TODO: Add error handling for animation failure
if [[ ! -x "/usr/local/bin/phoenix_fly.sh" ]]; then
    echo "[$(date)] Warning: /usr/local/bin/phoenix_fly.sh not found or not executable. Skipping animation." | tee -a "$LOGFILE"
else
    echo "[$(date)] Running Phoenix animation..." >> "$LOGFILE"
    /usr/local/bin/phoenix_fly.sh "Setup complete. Rebooting now. You no longer need root access."
fi
echo "[$(date)] Initiating system reboot..." >> "$LOGFILE"
nohup bash -c 'sleep 2; reboot' &>/dev/null &
echo "[$(date)] Reboot command issued. Exiting setup script." >> "$LOGFILE"
exit 0