#!/bin/bash
#
# File: phoenix_hypervisor_lxc_900.sh
# Description: Finalizes the setup for LXC container 900 (BaseTemplate) and creates
#              the foundational 'base-snapshot' ZFS snapshot. This script installs
#              essential base packages and performs basic OS configuration. Comments
#              are optimized for Retrieval Augmented Generation (RAG), facilitating
#              effective chunking and vector database indexing.
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script is a critical part of the Phoenix Hypervisor's template hierarchy.
# The 'base-snapshot' created here serves as the immutable foundation for all
# subsequent LXC templates and derived containers, ensuring consistency across deployments.
#
# Usage:
#   ./phoenix_hypervisor_lxc_900.sh <CTID>
#
# Arguments:
#   - CTID (integer): The Container ID, which must be `900` for the BaseTemplate.
#
# Requirements:
#   - Proxmox VE host environment with `pct` command available.
#   - LXC container `900` must be pre-created and in a running state.
#   - `jq` for potential JSON parsing (though not directly used in this script's current version).
#   - Internet access within the container for package installations.
#   - Appropriate permissions to manage LXC containers and ZFS snapshots.
#
# Exit Codes:
#   0: Success (Setup completed, snapshot created or already existed).
#   1: General error.
#   2: Invalid input arguments.
#   3: Container 900 does not exist or is not accessible.
#   4: OS update/installation failed.
#   5: Snapshot creation failed.
#   6: Container shutdown/start failed.

# --- Global Variables and Constants ---
MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"

# --- Logging Functions ---
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] phoenix_hypervisor_lxc_900.sh: $*" | tee -a "$MAIN_LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] phoenix_hypervisor_lxc_900.sh: $*" | tee -a "$MAIN_LOG_FILE" >&2
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
CTID=""
SNAPSHOT_NAME="base-snapshot" # Defined in requirements

# =====================================================================================
# Function: parse_arguments
# Description: Parses and validates the command-line arguments, expecting a single
#              argument representing the Container ID (CTID).
#
# Parameters:
#   - $@: All command-line arguments.
#
# Global Variables Modified:
#   - `CTID`: Stores the Container ID extracted from the arguments.
#
# Exit Conditions:
#   - Exits with code 2 if an incorrect number of arguments is provided.
#
# RAG Keywords: argument parsing, command-line interface, script input, CTID.
# =====================================================================================
# =====================================================================================
parse_arguments() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1"
    log_info "Received CTID: $CTID"
}

# =====================================================================================
# Function: validate_inputs
# Description: Validates the provided Container ID (CTID) to ensure it is a positive
#              integer and, specifically, that it matches `900` as this script is
#              tailored for the BaseTemplate. A warning is logged if the CTID is not 900.
#
# Parameters: None (operates on global script variable `CTID`)
#
# Exit Conditions:
#   - Exits with code 2 if `CTID` is not a valid positive integer.
#
# RAG Keywords: input validation, CTID validation, BaseTemplate, script specificity.
# =====================================================================================
# =====================================================================================
validate_inputs() {
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [ "$CTID" -le 0 ]; then
        log_error "FATAL: Invalid CTID '$CTID'. Must be a positive integer."
        exit_script 2
    fi
    if [ "$CTID" -ne 900 ]; then
        log_error "WARNING: This script is specifically designed for CTID 900 (BaseTemplate). Proceeding, but verify usage."
    fi
    log_info "Input validation passed."
}

# =====================================================================================
# Function: check_container_exists
# Description: Verifies the existence and manageability of the target LXC container
#              (CTID 900). This is a crucial sanity check before proceeding with
#              any configuration or snapshot operations.
#
# Parameters: None (operates on global script variable `CTID`)
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct status`).
#
# Exit Conditions:
#   - Exits with code 3 if the container does not exist or is not accessible.
#
# RAG Keywords: container existence, LXC status, BaseTemplate, Proxmox `pct`, error handling.
# =====================================================================================
# =====================================================================================
check_container_exists() {
    log_info "Checking for existence of container CTID: $CTID"
    if ! pct status "$CTID" > /dev/null 2>&1; then
        log_error "FATAL: Container $CTID does not exist or is not accessible."
        exit_script 3
    fi
    log_info "Container $CTID exists."
}

# =====================================================================================
# Function: check_if_snapshot_exists
# Description: Checks if the 'base-snapshot' ZFS snapshot already exists for the
#              target container (CTID 900). This function ensures idempotency,
#              preventing redundant snapshot creation if the setup was previously completed.
#
# Parameters: None (operates on global script variables `CTID` and `SNAPSHOT_NAME`)
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct snapshot list`).
#   - `grep`: Used for parsing snapshot list output.
#
# Exit Conditions:
#   - Exits with code 0 if the 'base-snapshot' already exists.
#   - Continues execution if the snapshot does not exist.
#
# RAG Keywords: ZFS snapshot, idempotency, base template, container state, Proxmox `pct`.
# =====================================================================================
# =====================================================================================
check_if_snapshot_exists() {
    log_info "Checking if snapshot '$SNAPSHOT_NAME' already exists for container $CTID."
    local pct_listsnapshot_output
    pct_listsnapshot_output=$(pct listsnapshot "$CTID" 2>&1)
    log_info "Output of 'pct listsnapshot $CTID': $pct_listsnapshot_output"
    if echo "$pct_listsnapshot_output" | grep -q "^$SNAPSHOT_NAME$"; then
        log_info "Snapshot '$SNAPSHOT_NAME' already exists for container $CTID. Skipping entire setup."
        exit_script 0
    else
        log_info "Snapshot '$SNAPSHOT_NAME' does not exist. Proceeding with setup."
    fi
}

# =====================================================================================
# Function: perform_base_os_setup
# Description: Performs essential operating system setup within the BaseTemplate
#              LXC container (CTID 900). This includes updating package lists,
#              upgrading existing packages, and installing a set of fundamental
#              utility packages.
#
# Parameters: None (operates on global script variable `CTID`)
#
# Dependencies:
#   - `pct exec`: For executing commands inside the LXC container.
#   - `apt-get`: For package management within the Debian-based container.
#
# Exit Conditions:
#   - Exits with code 4 if any `apt-get` command (update, upgrade, install) fails.
#
# RAG Keywords: base OS setup, package management, apt-get, LXC container,
#               utility installation, system configuration, error handling.
# =====================================================================================
# =====================================================================================
perform_base_os_setup() {
    log_info "Performing base OS setup inside container CTID: $CTID"
    

    local essential_packages=("curl" "wget" "vim" "htop" "jq" "git" "rsync" "s-tui" "gnupg" "locales")

    log_info "Updating package lists inside container $CTID..."
    if ! pct exec "$CTID" -- apt-get update; then
        log_error "FATAL: Failed to update package lists inside container $CTID."
        exit_script 4
    fi

    log_info "Upgrading essential packages inside container $CTID..."
    if ! pct exec "$CTID" -- apt-get upgrade -y; then
        log_error "FATAL: Failed to upgrade essential packages inside container $CTID."
        exit_script 4
    fi

    log_info "Installing essential utility packages inside container $CTID..."
    if ! pct exec "$CTID" -- apt-get install -y "${essential_packages[@]}"; then
        log_error "FATAL: Failed to install essential utility packages inside container $CTID."
        exit_script 4
    fi

    log_info "Base OS setup completed successfully for container $CTID."

    log_info "Configuring en_US.UTF-8 locale inside container $CTID..."
    if ! pct exec "$CTID" -- bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen"; then log_error "Failed to add en_US.UTF-8 to /etc/locale.gen." && exit_script 4; fi
    if ! pct exec "$CTID" -- locale-gen; then log_error "Failed to generate locales." && exit_script 4; fi
    if ! pct exec "$CTID" -- update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8; then log_error "Failed to update system locale." && exit_script 4; fi
    log_info "en_US.UTF-8 locale configured successfully."
}

# =====================================================================================
# Function: shutdown_container
# Description: Safely shuts down the specified LXC container (CTID). It initiates
#              the shutdown process using `pct shutdown` and then polls the container's
#              status until it reaches a 'stopped' state or a timeout occurs.
#
# Parameters:
#   - $1 (CTID): The Container ID of the LXC container to shut down.
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct shutdown`, `pct status`).
#
# Exit Conditions:
#   - Exits with code 6 if the shutdown initiation fails or if the container
#     does not stop within the defined timeout.
#
# RAG Keywords: container shutdown, LXC management, Proxmox `pct`, graceful shutdown,
#               timeout, error handling.
# =====================================================================================
# =====================================================================================
shutdown_container() {
    local ctid="$1"
    local timeout=60 # seconds
    local interval=3 # seconds
    local elapsed_time=0

    log_info "Initiating shutdown of container $ctid..."
    if ! pct shutdown "$ctid"; then
        log_error "FATAL: Failed to initiate shutdown for container $ctid."
        exit_script 6
    fi

    log_info "Waiting for container $ctid to stop..."
    while [ "$elapsed_time" -lt "$timeout" ]; do
        if pct status "$ctid" | grep -q "status: stopped"; then
            log_info "Container $ctid is stopped."
            return 0
        fi
        sleep "$interval"
        elapsed_time=$((elapsed_time + interval))
    done

    log_error "FATAL: Container $ctid did not stop within ${timeout} seconds."
    exit_script 6
}

# =====================================================================================
# Function: create_base_snapshot
# Description: Creates the 'base-snapshot' ZFS snapshot for the specified LXC container
#              (CTID 900). This snapshot serves as the foundational, immutable state
#              from which all other templates and containers in the Phoenix Hypervisor
#              hierarchy will be cloned.
#
# Parameters: None (operates on global script variables `CTID` and `SNAPSHOT_NAME`)
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct snapshot`).
#
# Exit Conditions:
#   - Exits with code 5 if the snapshot creation fails.
#
# RAG Keywords: ZFS snapshot, base template, container imaging, immutable infrastructure,
#               Proxmox `pct`, error handling.
# =====================================================================================
# =====================================================================================
create_base_snapshot() {
    log_info "Creating ZFS snapshot '$SNAPSHOT_NAME' for container $CTID..."
    if ! pct snapshot "$CTID" "$SNAPSHOT_NAME"; then
        log_error "FATAL: Failed to create snapshot '$SNAPSHOT_NAME' for container $CTID."
        exit_script 5
    fi
    log_info "Snapshot '$SNAPSHOT_NAME' created successfully for container $CTID."
}

# =====================================================================================
# Function: start_container
# Description: Restarts the specified LXC container (CTID) after the ZFS snapshot
#              has been successfully created. It initiates the startup using `pct start`
#              and then polls the container's status until it reaches a 'running' state
#              or a timeout occurs.
#
# Parameters:
#   - $1 (CTID): The Container ID of the LXC container to start.
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit (`pct start`, `pct status`).
#
# Exit Conditions:
#   - Exits with code 6 if the startup initiation fails or if the container
#     does not start within the defined timeout.
#
# RAG Keywords: container startup, LXC management, Proxmox `pct`, container restart,
#               timeout, error handling.
# =====================================================================================
# =====================================================================================
start_container() {
    local ctid="$1"
    local timeout=60 # seconds
    local interval=3 # seconds
    local elapsed_time=0

    log_info "Starting container $ctid after snapshot creation..."
    if ! pct start "$ctid"; then
        log_error "FATAL: Failed to start container $ctid."
        exit_script 6
    fi

    log_info "Waiting for container $ctid to start..."
    while [ "$elapsed_time" -lt "$timeout" ]; do
        if pct status "$ctid" | grep -q "status: running"; then
            log_info "Container $ctid is running."
            return 0
        fi
        sleep "$interval"
        elapsed_time=$((elapsed_time + interval))
    done

    log_error "FATAL: Container $ctid did not start within ${timeout} seconds."
    exit_script 6
}

# =====================================================================================
# Function: main
# Description: The main entry point for the BaseTemplate (CTID 900) setup script.
#              It orchestrates the entire process of preparing the base template,
#              including argument parsing, input validation, checking for existing
#              snapshots, performing OS setup, shutting down, creating the
#              'base-snapshot', and restarting the container.
#
# Parameters:
#   - $@: All command-line arguments passed to the script.
#
# Dependencies:
#   - `parse_arguments()`
#   - `validate_inputs()`
#   - `check_container_exists()`
#   - `check_if_snapshot_exists()`
#   - `perform_base_os_setup()`
#   - `shutdown_container()`
#   - `create_base_snapshot()`
#   - `start_container()`
#   - `exit_script()`
#
# RAG Keywords: main function, script entry point, BaseTemplate setup, ZFS snapshot,
#               OS configuration, LXC management.
# =====================================================================================
# =====================================================================================
main() {
    parse_arguments "$@"
    validate_inputs
    check_container_exists
    check_if_snapshot_exists # Exits 0 if snapshot already exists

    perform_base_os_setup "$CTID"
    shutdown_container "$CTID"
    create_base_snapshot "$CTID"
    start_container "$CTID"

    exit_script 0
}

# Call the main function
main "$@"