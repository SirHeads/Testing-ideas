# Metadata: {"chunk_id": "phoenix_create_storage-1.0", "keywords": ["proxmox", "storage", "zfs", "directory"], "comment_type": "block"}
#!/bin/bash
# phoenix_create_storage.sh
# Creates Proxmox VE storage definitions for configured ZFS datasets and directories
# Version: 1.0.2 (Fixed incorrect -shared flag for ZFS storage, aligned with config changes)
# Author: Assistant, based on Heads, Grok, Devstral's work

# Main: Configures Proxmox VE storage definitions for ZFS and directory-based storage
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_create_storage-1.1", "keywords": ["proxmox", "storage"], "comment_type": "block"}
# Algorithm: Storage definition creation
# Loads configuration, iterates through datasets, creates ZFS or directory storage based on type
# Keywords: [proxmox, storage, zfs, directory]
# TODO: Implement robust storage ID mapping and NFS storage support

# Source common functions and configuration
# Assumes LOGFILE is set by the orchestrator (create_phoenix.sh)
# shellcheck source=/dev/null
if [[ -f /usr/local/bin/common.sh ]]; then
    source /usr/local/bin/common.sh || { echo "[$(date)] Error: Failed to source common.sh" | tee -a /dev/stderr; exit 1; }
else
    echo "[$(date)] Error: common.sh not found at /usr/local/bin/common.sh" | tee -a /dev/stderr
    exit 1
fi

# shellcheck source=/dev/null
if [[ -f /usr/local/bin/phoenix_config.sh ]]; then
    source /usr/local/bin/phoenix_config.sh || { echo "[$(date)] Error: Failed to source phoenix_config.sh" | tee -a /dev/stderr; exit 1; }
else
    echo "[$(date)] Error: phoenix_config.sh not found at /usr/local/bin/phoenix_config.sh" | tee -a /dev/stderr
    exit 1
fi

# Ensure the script is run as root
check_root

# Setup logging
# Metadata: {"chunk_id": "phoenix_create_storage-1.2", "keywords": ["logging"], "comment_type": "block"}
LOGFILE="${LOGFILE:-/var/log/proxmox_setup.log}"
echo "[$(date)] Starting phoenix_create_storage.sh" >> "$LOGFILE"

# create_zfs_storage: Creates a ZFS storage definition in Proxmox VE
# Args: $1: Storage ID, $2: ZFS Pool/Dataset, $3: Content types, $4: Disable (0 or 1, default 0)
# Returns: 0 on success or if storage exists, 1 on failure
# Metadata: {"chunk_id": "phoenix_create_storage-1.3", "keywords": ["zfs", "storage"], "comment_type": "block"}
# Algorithm: ZFS storage creation
# Checks if storage exists, creates ZFS storage with specified parameters
# Keywords: [zfs, storage, proxmox]
create_zfs_storage() {
    local storage_id="$1"
    local zfs_pool="$2"
    local content="$3"
    local disable="${4:-0}"
    if [[ -z "$storage_id" || -z "$zfs_pool" || -z "$content" ]]; then
        echo "[$(date)] Error: create_zfs_storage requires storage_id, zfs_pool, and content." | tee -a "$LOGFILE"
        return 1
    fi
    if pvesm status | grep -q "^$storage_id:"; then
        echo "[$(date)] Info: Proxmox storage '$storage_id' already exists, skipping creation." >> "$LOGFILE"
        return 0
    fi
    echo "[$(date)] Creating ZFS storage: ID=$storage_id, Pool/Dataset=$zfs_pool, Content=$content" >> "$LOGFILE"
    if pvesm add zfspool "$storage_id" -pool "$zfs_pool" -content "$content" -disable "$disable"; then
        echo "[$(date)] Successfully created ZFS storage '$storage_id'." >> "$LOGFILE"
    else
        echo "[$(date)] Error: Failed to create ZFS storage '$storage_id'." | tee -a "$LOGFILE"
        return 1
    fi
}

# create_directory_storage: Creates a directory-based storage definition in Proxmox VE
# Args: $1: Storage ID, $2: Path, $3: Content types, $4: Disable (0 or 1, default 0), $5: Shared (0 or 1, default 1), $6: NFS Server (optional), $7: NFS Export (optional)
# Returns: 0 on success or if storage exists, 1 on failure
# Metadata: {"chunk_id": "phoenix_create_storage-1.4", "keywords": ["directory", "storage"], "comment_type": "block"}
create_directory_storage() {
    local storage_id="$1"
    local path="$2"
    local content="$3"
    local disable="${4:-0}"
    local shared="${5:-1}"
    local server="${6:-}"
    local export_path="${7:-}"
    if [[ -z "$storage_id" || -z "$path" || -z "$content" ]]; then
        echo "[$(date)] Error: create_directory_storage requires storage_id, path, and content." | tee -a "$LOGFILE"
        return 1
    fi
    if pvesm status | grep -q "^$storage_id:"; then
        echo "[$(date)] Info: Proxmox storage '$storage_id' already exists, skipping creation." >> "$LOGFILE"
        return 0
    fi
    local cmd="pvesm add dir $storage_id -path $path -content $content -disable $disable -shared $shared"
    if [[ -n "$server" ]]; then
        cmd="$cmd -server $server"
    fi
    if [[ -n "$export_path" ]]; then
        cmd="$cmd -export $export_path"
    fi
    echo "[$(date)] Creating Directory storage: ID=$storage_id, Path=$path, Content=$content" >> "$LOGFILE"
    if eval "$cmd"; then
        echo "[$(date)] Successfully created Directory storage '$storage_id'." >> "$LOGFILE"
    else
        echo "[$(date)] Error: Failed to create Directory storage '$storage_id'." | tee -a "$LOGFILE"
        return 1
    fi
}

# get_content_type_for_dataset: Determines content type for a dataset from configuration
# Args: $1: Full dataset path (e.g., quickOS/vm-disks)
# Returns: Content type string (e.g., "images")
# Metadata: {"chunk_id": "phoenix_create_storage-1.5", "keywords": ["dataset", "content"], "comment_type": "block"}
get_content_type_for_dataset() {
    local full_dataset_path="$1"
    local storage_type_content=""
    if [[ -n "${DATASET_STORAGE_TYPES[$full_dataset_path]}" ]]; then
        storage_type_content="${DATASET_STORAGE_TYPES[$full_dataset_path]#*:}"
        if [[ "$storage_type_content" == "${DATASET_STORAGE_TYPES[$full_dataset_path]}" ]]; then
            storage_type_content="images"
        fi
    else
        echo "[$(date)] Warning: Unknown storage type/content for dataset '$full_dataset_path'. Using 'images'." >> "$LOGFILE"
        storage_type_content="images"
    fi
    echo "$storage_type_content"
}

# get_storage_type_for_dataset: Determines storage type for a dataset from configuration
# Args: $1: Full dataset path (e.g., quickOS/vm-disks)
# Returns: Storage type string (e.g., "zfspool", "dir")
# Metadata: {"chunk_id": "phoenix_create_storage-1.6", "keywords": ["dataset", "storage"], "comment_type": "block"}
get_storage_type_for_dataset() {
    local full_dataset_path="$1"
    local storage_type=""
    if [[ -n "${DATASET_STORAGE_TYPES[$full_dataset_path]}" ]]; then
        storage_type="${DATASET_STORAGE_TYPES[$full_dataset_path]%:*}"
        if [[ "$storage_type" == "${DATASET_STORAGE_TYPES[$full_dataset_path]}" ]]; then
            storage_type="dir"
        fi
    else
        echo "[$(date)] Warning: Unknown storage type for dataset '$full_dataset_path'. Using 'dir'." >> "$LOGFILE"
        storage_type="dir"
    fi
    echo "$storage_type"
}

# Main execution
# Metadata: {"chunk_id": "phoenix_create_storage-1.7", "keywords": ["proxmox", "storage"], "comment_type": "block"}
# Algorithm: Storage creation loop
# Iterates through datasets, determines storage and content types, creates appropriate storage
# Keywords: [proxmox, storage, dataset]
# TODO: Enhance storage ID derivation logic
load_config
echo "[$(date)] Configuration variables loaded for storage creation." >> "$LOGFILE"
echo "[$(date)] Starting to iterate through configured datasets for storage creation." >> "$LOGFILE"
for full_dataset_path in "${!DATASET_STORAGE_TYPES[@]}"; do
    echo "[$(date)] Processing dataset: $full_dataset_path" >> "$LOGFILE"
    STORAGE_TYPE=$(get_storage_type_for_dataset "$full_dataset_path")
    CONTENT_TYPE=$(get_content_type_for_dataset "$full_dataset_path")
    DEFAULT_STORAGE_ID="${full_dataset_path//\//-}"
    if [[ "$DEFAULT_STORAGE_ID" == "${QUICKOS_POOL}-"* ]]; then
        STORAGE_ID="${DEFAULT_STORAGE_ID/${QUICKOS_POOL}-}"
    elif [[ "$DEFAULT_STORAGE_ID" == "${FASTDATA_POOL}-"* ]]; then
        STORAGE_ID="${DEFAULT_STORAGE_ID/${FASTDATA_POOL}-}"
    else
        STORAGE_ID="$DEFAULT_STORAGE_ID"
    fi
    echo "[$(date)] Derived Storage ID: $STORAGE_ID, Type: $STORAGE_TYPE, Content: $CONTENT_TYPE" >> "$LOGFILE"
    case "$STORAGE_TYPE" in
        "zfspool")
            create_zfs_storage "$STORAGE_ID" "$full_dataset_path" "$CONTENT_TYPE"
            ;;
        "dir")
            POOL_NAME="${full_dataset_path%%/*}"
            DATASET_NAME="${full_dataset_path#*/}"
            MOUNTPOINT="/$POOL_NAME/$DATASET_NAME"
            create_directory_storage "$STORAGE_ID" "$MOUNTPOINT" "$CONTENT_TYPE"
            ;;
        *)
            echo "[$(date)] Warning: Unsupported storage type '$STORAGE_TYPE' for dataset '$full_dataset_path'. Skipping." >> "$LOGFILE"
            ;;
    esac
done

# Placeholder for storageNFS
# Metadata: {"chunk_id": "phoenix_create_storage-1.8", "keywords": ["nfs", "storage"], "comment_type": "block"}
# TODO: Implement NFS storage creation logic if re-enabled
# As per request, storageNFS remains disabled

echo "[$(date)] Completed phoenix_create_storage.sh" >> "$LOGFILE"
exit 0