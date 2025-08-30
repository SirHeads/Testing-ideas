#!/bin/bash
#
# File: phoenix_hypervisor_clone_lxc.sh
# Description: Clones an LXC container from a specified ZFS snapshot of a template container.
#              This script automates the `pct clone` command and applies post-clone configurations
#              based on a provided JSON configuration block. Comments are optimized for
#              Retrieval Augmented Generation (RAG), facilitating effective chunking and
#              vector database indexing.
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script is a core component of the Phoenix Hypervisor, enabling rapid deployment
# of new LXC containers from pre-configured templates. It ensures that cloned containers
# inherit base settings and then receive specific customizations, particularly network
# configurations.
#
# Usage:
#   ./phoenix_hypervisor_clone_lxc.sh <SOURCE_CTID> <SOURCE_SNAPSHOT_NAME> <TARGET_CTID> <LXC_CONFIG_FILE> <TARGET_CONFIG_BLOCK_JSON>
#
# Arguments:
#   - SOURCE_CTID (integer): The Container ID of the template container to clone from.
#   - SOURCE_SNAPSHOT_NAME (string): The name of the ZFS snapshot on the source container to use for cloning.
#   - TARGET_CTID (integer): The Container ID for the new LXC container to be created.
#   - LXC_CONFIG_FILE (string): Absolute path to the main LXC configuration JSON file.
#   - TARGET_CONFIG_BLOCK_JSON (string): A JSON string containing the full configuration
#                                         block for the *target* container, as defined
#                                         in `phoenix_lxc_configs.json`. This includes
#                                         settings like name, memory, cores, storage,
#                                         network configuration, and features.
#
# Requirements:
#   - Proxmox VE host environment with `pct` command available.
#   - `jq` for robust JSON parsing.
#   - The specified `SOURCE_CTID` and `SOURCE_SNAPSHOT_NAME` must exist on the Proxmox host.
#   - Appropriate permissions to manage LXC containers and ZFS snapshots.
#
# Exit Codes:
#   0: Success (Container cloned and configured successfully)
#   1: General error
#   2: Invalid input arguments
#   3: Source container or snapshot does not exist
#   4: pct clone command failed
#   5: Post-clone configuration adjustments failed

# --- Global Variables and Constants ---
MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"

# --- Logging Functions ---
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] phoenix_hypervisor_clone_lxc.sh: $*" | tee -a "$MAIN_LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] phoenix_hypervisor_clone_lxc.sh: $*" | tee -a "$MAIN_LOG_FILE" >&2
}

# --- Exit Function ---
exit_script() {
    local exit_code=$1
    if [ "$exit_code" -eq 0 ]; then
        log_info "Script completed successfully."
    else
        log_error "Script failed with exit code $exit_code."
    fi
    exit "$exit_code"
}

# --- Script Variables ---
SOURCE_CTID=""
SOURCE_SNAPSHOT_NAME=""
TARGET_CTID=""
LXC_CONFIG_FILE=""
TARGET_CONFIG_BLOCK_JSON=""
PCT_CLONE_CMD=()

# =====================================================================================
# Function: parse_arguments
# Description: Parses and validates the command-line arguments provided to the script.
#              It expects exactly five arguments: source CTID, source snapshot name,
#              target CTID, LXC configuration file path, and the target container's
#              JSON configuration block.
#
# Parameters:
#   - $@: All command-line arguments.
#
# Global Variables Modified:
#   - `SOURCE_CTID`: Stores the source container ID.
#   - `SOURCE_SNAPSHOT_NAME`: Stores the name of the ZFS snapshot to clone from.
#   - `TARGET_CTID`: Stores the target container ID.
#   - `LXC_CONFIG_FILE`: Stores the path to the main LXC configuration file.
#   - `TARGET_CONFIG_BLOCK_JSON`: Stores the JSON configuration block for the target container.
#
# Exit Conditions:
#   - Exits with code 2 if an incorrect number of arguments is provided.
#
# RAG Keywords: argument parsing, command-line interface, script input, LXC cloning parameters.
# =====================================================================================
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 5 ]; then
        log_error "Usage: $0 <SOURCE_CTID> <SOURCE_SNAPSHOT_NAME> <TARGET_CTID> <LXC_CONFIG_FILE> <TARGET_CONFIG_BLOCK_JSON>"
        exit_script 2
    fi
    SOURCE_CTID="$1"
    SOURCE_SNAPSHOT_NAME="$2"
    TARGET_CTID="$3"
    LXC_CONFIG_FILE="$4"
    TARGET_CONFIG_BLOCK_JSON="$5"
    log_info "Received arguments: SOURCE_CTID=$SOURCE_CTID, SOURCE_SNAPSHOT_NAME=$SOURCE_SNAPSHOT_NAME, TARGET_CTID=$TARGET_CTID"
}

# =====================================================================================
# Function: validate_inputs
# Description: Validates all input arguments to ensure they are correctly formatted
#              and that the specified source container and its ZFS snapshot exist.
#              This prevents cloning operations from proceeding with invalid or
#              non-existent resources.
#
# Parameters: None (operates on global script variables set by `parse_arguments`)
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct status`, `pct snapshot list`).
#   - `jq`: Used for validating the JSON syntax of `TARGET_CONFIG_BLOCK_JSON`.
#
# Exit Conditions:
#   - Exits with code 2 for invalid input argument formats or empty strings.
#   - Exits with code 3 if the source container or its specified snapshot does not exist.
#
# RAG Keywords: input validation, argument checking, source container, ZFS snapshot,
#               JSON validation, error handling, script robustness.
# =====================================================================================
# =====================================================================================
validate_inputs() {
    if ! [[ "$SOURCE_CTID" =~ ^[0-9]+$ ]] || [ "$SOURCE_CTID" -le 0 ]; then
        log_error "FATAL: Invalid SOURCE_CTID '$SOURCE_CTID'. Must be a positive integer."
        exit_script 2
    fi
    if ! [[ "$TARGET_CTID" =~ ^[0-9]+$ ]] || [ "$TARGET_CTID" -le 0 ]; then
        log_error "FATAL: Invalid TARGET_CTID '$TARGET_CTID'. Must be a positive integer."
        exit_script 2
    fi
    if [ -z "$SOURCE_SNAPSHOT_NAME" ] || [ -z "$LXC_CONFIG_FILE" ] || [ -z "$TARGET_CONFIG_BLOCK_JSON" ]; then
        log_error "FATAL: One or more required arguments are empty."
        exit_script 2
    fi
    if ! jq -e . >/dev/null 2>&1 <<<"$TARGET_CONFIG_BLOCK_JSON"; then
        log_error "FATAL: TARGET_CONFIG_BLOCK_JSON is not a valid JSON string."
        exit_script 2
    fi

    log_info "Checking for existence of source container CTID: $SOURCE_CTID"
    if ! pct status "$SOURCE_CTID" > /dev/null 2>&1; then
        log_error "FATAL: Source container $SOURCE_CTID does not exist."
        exit_script 3
    fi

    log_info "Checking for existence of snapshot '$SOURCE_SNAPSHOT_NAME' on container $SOURCE_CTID"
    if ! pct snapshot list "$SOURCE_CTID" | grep -q "$SOURCE_SNAPSHOT_NAME"; then
        log_error "FATAL: Snapshot '$SOURCE_SNAPSHOT_NAME' not found on source container $SOURCE_CTID."
        exit_script 3
    fi

    log_info "Input validation passed."
}

# =====================================================================================
# Function: construct_pct_clone_command
# Description: Dynamically builds the `pct clone` command array based on the provided
#              source and target container IDs, snapshot name, and the target container's
#              JSON configuration block. This includes setting hostname, memory, cores,
#              storage, features, and unprivileged status. Network configuration is
#              handled in a post-clone step.
#
# Parameters: None (operates on global script variables)
#
# Global Variables Modified:
#   - `PCT_CLONE_CMD`: An array storing the constructed `pct clone` command and its arguments.
#
# Dependencies:
#   - `jq`: Used for extracting configuration values from `TARGET_CONFIG_BLOCK_JSON`.
#
# RAG Keywords: `pct clone` command, LXC container cloning, command construction,
#               container resources, Proxmox configuration, JSON parsing.
# =====================================================================================
# =====================================================================================
construct_pct_clone_command() {
    log_info "Constructing pct clone command for TARGET_CTID: $TARGET_CTID"

    local hostname=$(jq -r '.name' <<< "$TARGET_CONFIG_BLOCK_JSON")
    local memory_mb=$(jq -r '.memory_mb' <<< "$TARGET_CONFIG_BLOCK_JSON")
    local cores=$(jq -r '.cores' <<< "$TARGET_CONFIG_BLOCK_JSON")
    local storage_pool=$(jq -r '.storage_pool' <<< "$TARGET_CONFIG_BLOCK_JSON")
    local features=$(jq -r '.features' <<< "$TARGET_CONFIG_BLOCK_JSON")
    local unprivileged_bool=$(jq -r '.unprivileged' <<< "$TARGET_CONFIG_BLOCK_JSON")
    local unprivileged_val=$([ "$unprivileged_bool" == "true" ] && echo "1" || echo "0")

    PCT_CLONE_CMD=(
        pct clone "$SOURCE_CTID" "$TARGET_CTID"
        --snapshot "$SOURCE_SNAPSHOT_NAME"
        --hostname "$hostname"
        --memory "$memory_mb"
        --cores "$cores"
        --storage "$storage_pool"
        --features "$features"
        --unprivileged "$unprivileged_val"
    )
    log_info "Constructed pct clone command: ${PCT_CLONE_CMD[*]}"
}

# =====================================================================================
# Function: execute_pct_clone
# Description: Executes the pre-constructed `pct clone` command to create the new
#              LXC container from the specified template snapshot. It captures
#              and handles the command's exit status.
#
# Parameters: None (operates on global script variable `PCT_CLONE_CMD`)
#
# Dependencies:
#   - `PCT_CLONE_CMD`: Must be populated by `construct_pct_clone_command()`.
#
# Exit Conditions:
#   - Exits with code 4 if the `pct clone` command fails.
#
# RAG Keywords: `pct clone` execution, LXC container creation, command execution,
#               error handling, Proxmox CLI.
# =====================================================================================
# =====================================================================================
execute_pct_clone() {
    log_info "Executing pct clone command for TARGET_CTID: $TARGET_CTID"
    if ! "${PCT_CLONE_CMD[@]}"; then
        log_error "FATAL: 'pct clone' command failed for TARGET_CTID $TARGET_CTID. Command: ${PCT_CLONE_CMD[*]}"
        exit_script 4
    fi
    log_info "'pct clone' command executed successfully for TARGET_CTID $TARGET_CTID."
}

# =====================================================================================
# Function: apply_post_clone_configurations
# Description: Applies specific configurations to the newly cloned LXC container that
#              are not fully handled by the `pct clone` command itself. This primarily
#              includes detailed network settings (IP address, gateway, MAC address,
#              and bridge) extracted from the target container's configuration block.
#
# Parameters: None (operates on global script variables)
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct set`).
#   - `jq`: Used for extracting network configuration values from `TARGET_CONFIG_BLOCK_JSON`.
#
# Exit Conditions:
#   - Exits with code 5 if the `pct set` command fails to apply network configurations.
#
# RAG Keywords: post-clone configuration, network settings, LXC customization,
#               IP address, MAC address, Proxmox `pct set`, error handling.
# =====================================================================================
# =====================================================================================
apply_post_clone_configurations() {
    log_info "Applying post-clone configurations for TARGET_CTID: $TARGET_CTID"

    local net0_name=$(jq -r '.network_config.name' <<< "$TARGET_CONFIG_BLOCK_JSON")
    local net0_bridge=$(jq -r '.network_config.bridge' <<< "$TARGET_CONFIG_BLOCK_JSON")
    local net0_ip=$(jq -r '.network_config.ip' <<< "$TARGET_CONFIG_BLOCK_JSON")
    local net0_gw=$(jq -r '.network_config.gw' <<< "$TARGET_CONFIG_BLOCK_JSON")
    local mac_address=$(jq -r '.mac_address' <<< "$TARGET_CONFIG_BLOCK_JSON")
    local net0_string="name=${net0_name},bridge=${net0_bridge},ip=${net0_ip},gw=${net0_gw},hwaddr=${mac_address}"

    log_info "Setting network configuration for TARGET_CTID $TARGET_CTID: $net0_string"
    if ! pct set "$TARGET_CTID" --net0 "$net0_string"; then
        log_error "FATAL: 'pct set' command failed to apply network configuration for TARGET_CTID $TARGET_CTID."
        exit_script 5
    fi
    log_info "Post-clone configurations applied successfully."
}

# =====================================================================================
# Function: main
# Description: The main entry point for the LXC container cloning script.
#              It orchestrates the entire cloning process by parsing arguments,
#              validating inputs, constructing and executing the `pct clone` command,
#              and applying any necessary post-clone configurations.
#
# Parameters:
#   - $@: All command-line arguments passed to the script.
#
# Dependencies:
#   - `parse_arguments()`
#   - `validate_inputs()`
#   - `construct_pct_clone_command()`
#   - `execute_pct_clone()`
#   - `apply_post_clone_configurations()`
#   - `exit_script()`
#
# RAG Keywords: main function, script entry point, LXC cloning flow, Proxmox automation.
# =====================================================================================
# =====================================================================================
main() {
    parse_arguments "$@"
    validate_inputs
    construct_pct_clone_command
    execute_pct_clone
    apply_post_clone_configurations
    exit_script 0
}

# Call the main function
main "$@"