#!/bin/bash
#
# File: phoenix_establish_hypervisor.sh
# Description: Orchestrates the creation and configuration of LXC containers and templates for an AI Toolbox.
#              This script leverages ZFS snapshots for efficient container management and supports
#              conditional NVIDIA and Docker setups. Comments are optimized for Retrieval Augmented Generation (RAG),
#              facilitating effective chunking and vector database indexing.
# Version: 0.3.0 (Reflects full snapshot template hierarchy and cloning logic)
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script automates the end-to-end lifecycle of LXC containers and templates, from initial Proxmox host setup
# to specific container customization. It reads configurations from `phoenix_lxc_configs.json` and
# `phoenix_hypervisor_config.json` to ensure consistent and reproducible deployments.
#
# Usage:
#   ./phoenix_hypervisor_establish_hypervisor.sh
#
# Requirements:
#   - Proxmox VE host environment.
#   - `jq` for JSON parsing.
#   - `ajv-cli` for JSON schema validation.
#   - `pct` (Proxmox VE Container Toolkit) for LXC management.
#   - Configured ZFS storage pool for LXC.
#   - Network access for package installations and external resource downloads.
#   - Configuration files:
#     - `/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json`
#     - `/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`
#     - `/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.schema.json`
#
# Exit Codes:
#   0: Success
#   1: General error
#   2: Configuration validation error
#   3: Host setup error
#   4: Critical script missing
#   5: Critical container/template processing failure

# --- Global Variables and Constants ---
HYPERVISOR_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json"
LXC_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json"
LXC_CONFIG_SCHEMA_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.schema.json"
MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"

# Global variables for NVIDIA settings
NVIDIA_DRIVER_VERSION=""
NVIDIA_REPO_URL=""
NVIDIA_RUNFILE_URL=""

# --- Logging Functions ---
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] phoenix_establish_hypervisor.sh: $*" | tee -a "$MAIN_LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] phoenix_establish_hypervisor.sh: $*" | tee -a "$MAIN_LOG_FILE" >&2
}

# --- Exit Function ---
exit_script() {
    local exit_code=$1
    if [ "$exit_code" -eq 0 ]; then
        log_info "Orchestrator completed successfully."
    else
        log_error "Orchestrator failed with exit code $exit_code."
    fi
    exit "$exit_code"
}

# =====================================================================================
# load_and_validate_configs()
#   Content:
#     - Define hardcoded paths:
#         HYPERVISOR_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json"
#         LXC_CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json"
#         LXC_CONFIG_SCHEMA_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.schema.json"
#     - Check if HYPERVISOR_CONFIG_FILE exists. Fatal error if not.
#     - Load HYPERVISOR_CONFIG_FILE (for future behavior flags).
#     - Check if LXC_CONFIG_FILE exists. Fatal error if not.
#     - Load LXC_CONFIG_FILE (e.g., using jq).
#     - Check if LXC_CONFIG_SCHEMA_FILE exists. Fatal error if not.
#     - Validate LXC_CONFIG_FILE against LXC_CONFIG_SCHEMA_FILE using ajv CLI.
#         Command example: ajv validate -s "$LXC_CONFIG_SCHEMA_FILE" -d "$LXC_CONFIG_FILE"
#         Fatal error if validation fails.
#     - Extract global NVIDIA settings:
#         NVIDIA_DRIVER_VERSION=$(jq -r '.nvidia_driver_version' "$LXC_CONFIG_FILE")
#         NVIDIA_REPO_URL=$(jq -r '.nvidia_repo_url' "$LXC_CONFIG_FILE")
#         NVIDIA_RUNFILE_URL=$(jq -r '.nvidia_runfile_url' "$LXC_CONFIG_FILE") # New
#     - Store LXC_CONFIG_FILE path and parsed data globally.
#   Purpose: Ensures configs are present, valid, and extracts global settings. Halts on critical failures.
# =====================================================================================
load_and_validate_configs() {
    log_info "Loading and validating configuration files..."

    # Pre-check for jq
    if ! command -v jq &> /dev/null; then
        log_error "FATAL: 'jq' command not found. Please install jq to proceed. Exiting."
        exit_script 4
    fi
    log_info "'jq' command found."

    # Pre-check for ajv
    if ! command -v ajv &> /dev/null; then
        log_error "FATAL: 'ajv' command not found. Please install ajv-cli to proceed. Exiting."
        exit_script 4
    fi
    log_info "'ajv' command found."

    if [ ! -f "$HYPERVISOR_CONFIG_FILE" ]; then
        log_error "FATAL: Hypervisor configuration file not found at $HYPERVISOR_CONFIG_FILE."
        exit_script 2
    fi
    log_info "Hypervisor config file found: $HYPERVISOR_CONFIG_FILE"

    # Load HYPERVISOR_CONFIG_FILE (for future use of behavior flags, etc.)
    # For now, just ensure it's readable JSON
    if ! jq empty < "$HYPERVISOR_CONFIG_FILE" > /dev/null 2>&1; then
        log_error "FATAL: Hypervisor configuration file $HYPERVISOR_CONFIG_FILE is not a valid JSON file or is unreadable."
        exit_script 2
    fi

    if [ ! -f "$LXC_CONFIG_FILE" ]; then
        log_error "FATAL: LXC configuration file not found at $LXC_CONFIG_FILE."
        exit_script 2
    fi
    log_info "LXC config file found: $LXC_CONFIG_FILE"

    if [ ! -f "$LXC_CONFIG_SCHEMA_FILE" ]; then
        log_error "FATAL: LXC configuration schema file not found at $LXC_CONFIG_SCHEMA_FILE."
        exit_script 2
    fi
    log_info "LXC config schema file found: $LXC_CONFIG_SCHEMA_FILE"

    log_info "Validating $LXC_CONFIG_FILE against $LXC_CONFIG_SCHEMA_FILE using ajv-cli..."
    if ! ajv validate -s "$LXC_CONFIG_SCHEMA_FILE" -d "$LXC_CONFIG_FILE"; then
        log_error "FATAL: LXC configuration validation failed. Please check $LXC_CONFIG_FILE against $LXC_CONFIG_SCHEMA_FILE."
        exit_script 2
    fi
    log_info "LXC configuration validated successfully."

    NVIDIA_DRIVER_VERSION=$(jq -r '.nvidia_driver_version' "$LXC_CONFIG_FILE")
    NVIDIA_REPO_URL=$(jq -r '.nvidia_repo_url' "$LXC_CONFIG_FILE")
    NVIDIA_RUNFILE_URL=$(jq -r '.nvidia_runfile_url' "$LXC_CONFIG_FILE")

    if [ -z "$NVIDIA_DRIVER_VERSION" ] || [ -z "$NVIDIA_REPO_URL" ] || [ -z "$NVIDIA_RUNFILE_URL" ]; then
        log_error "WARNING: Global NVIDIA settings (driver version, repo URL, runfile URL) are incomplete in $LXC_CONFIG_FILE. NVIDIA setup might fail if required."
    else
        log_info "Global NVIDIA settings extracted."
    fi
    log_info "Configuration files loaded and validated."
}

# =====================================================================================
# Function: initialize_environment
# Description: Sets up the script's execution environment. This includes initializing
#              the main log file and logging the script's start. This function ensures
#              a clean and traceable execution context.
#
# Parameters: None
#
# Global Variables Modified: None (primarily interacts with the file system for logging)
#
# Exit Conditions: None (critical errors handled by logging functions)
#
# RAG Keywords: environment setup, logging initialization, script execution context.
# =====================================================================================
# =====================================================================================
initialize_environment() {
    # Initialize/Clear the main log file
    > "$MAIN_LOG_FILE"
    log_info "Orchestrator script started: phoenix_establish_hypervisor.sh (Version: 0.3.0)"
    # No common library functions to source yet, as per clarification.
    # Debug mode and rollback flags will be read from HYPERVISOR_CONFIG_FILE when needed.
    log_info "Environment initialized."
}

# =====================================================================================
# Function: run_initial_host_setup
# Description: Executes the `phoenix_hypervisor_initial_setup.sh` script to prepare
#              the Proxmox host environment. This includes verifying essential tools
#              (jq, curl, ajv-cli) and core configuration files.
#
# Parameters: None
#
# Dependencies:
#   - `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_initial_setup.sh`
#
# Exit Conditions:
#   - Exits with code 3 if the initial host setup script fails.
#   - Exits with code 4 if the setup script is missing or not executable.
#
# RAG Keywords: host setup, Proxmox environment, tool verification, initial configuration.
# =====================================================================================
# =====================================================================================
run_initial_host_setup() {
    log_info "Running initial host setup script..."
    local setup_script="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_initial_setup.sh"

    if [ ! -f "$setup_script" ]; then
        log_error "FATAL: Initial host setup script not found at $setup_script."
        exit_script 4
    fi
    if [ ! -x "$setup_script" ]; then
        log_error "FATAL: Initial host setup script at $setup_script is not executable."
        exit_script 4
    fi

    if ! "$setup_script"; then
        log_error "FATAL: Initial host setup failed. Check logs for $setup_script for details."
        exit_script 3
    fi
    log_info "Initial host setup completed successfully."
}

# =====================================================================================
# Function: process_lxc_containers
# Description: Iterates through all defined LXC containers and templates in `phoenix_lxc_configs.json`
#              and orchestrates their creation, cloning, and configuration. Processing order
#              is based on CTID to respect potential template dependencies.
#
# Parameters: None
#
# Dependencies:
#   - `process_single_lxc()`: Called for each container/template.
#   - `jq`: Used for parsing LXC configuration data.
#
# Exit Conditions:
#   - Exits with code 5 if a critical template processing failure occurs, preventing cascading issues.
#   - Logs errors for standard container failures but continues processing other containers.
#
# RAG Keywords: LXC orchestration, container lifecycle, template dependencies, error handling, configuration processing.
# =====================================================================================
# =====================================================================================
process_lxc_containers() {
    log_info "Starting to process LXC containers and templates..."
    local ctid_list=$(jq -r '.lxc_configs | keys[] | tonumber' "$LXC_CONFIG_FILE" | sort -n)

    for ctid in $ctid_list; do
        local config_block=$(jq -r --arg ctid "$ctid" '.lxc_configs[$ctid | tostring]' "$LXC_CONFIG_FILE")
        local container_name=$(jq -r '.name' <<< "$config_block")
        log_info "Processing CTID: $ctid (Name: $container_name)"

        if ! process_single_lxc "$ctid" "$config_block"; then
            local is_template=$(jq -r '.is_template // false' <<< "$config_block")
            if [ "$is_template" == "true" ]; then
                log_error "FATAL: Template container $ctid ($container_name) failed to process. Halting orchestration to prevent cascading failures."
                exit_script 5
            else
                log_error "ERROR: Standard container $ctid ($container_name) failed to process. Continuing with next container."
            fi
        fi
    done
    log_info "Finished processing all LXC containers and templates."
}

# =====================================================================================
# Function: process_single_lxc
# Description: Manages the end-to-end processing for a single LXC container or template.
#              This includes determining whether to create a new base template, clone from
#              an existing template, and then applying conditional setups (NVIDIA, Docker)
#              and specific customization scripts. Finally, it ensures the container's
#              state is finalized with a "configured-state" snapshot.
#
# Parameters:
#   - $1 (CTID): The Container ID of the LXC container or template.
#   - $2 (config_block): A JSON string containing the specific configuration for the CTID.
#
# Dependencies:
#   - `create_or_clone_template()`: For template creation/cloning.
#   - `clone_standard_container()`: For standard container cloning.
#   - `wait_for_lxc_ready()`: Ensures container is operational.
#   - `setup_lxc_nvidia()`: Conditionally configures NVIDIA.
#   - `setup_lxc_docker()`: Conditionally configures Docker.
#   - `run_specific_setup_script()`: Executes CTID-specific setup.
#   - `finalize_container_state()`: Shuts down, snapshots, and restarts the container.
#   - `jq`: Used for parsing configuration data.
#
# Exit Conditions:
#   - Returns 1 for critical failures (e.g., template creation/cloning failure, container not ready, finalization failure).
#   - Returns 0 for success or non-critical failures (e.g., standard container cloning failure, optional setup script failure).
#
# RAG Keywords: LXC container processing, template management, container cloning, NVIDIA setup, Docker setup,
#               customization scripts, container state finalization, ZFS snapshot, error handling.
# =====================================================================================
# =====================================================================================
process_single_lxc() {
    local ctid="$1"
    local config_block="$2"
    local container_name=$(jq -r '.name' <<< "$config_block")
    local is_template=$(jq -r '.is_template // false' <<< "$config_block")
    local exit_status=0

    log_info "Starting processing for CTID: $ctid (Name: $container_name, Is Template: $is_template)"

    if [ "$is_template" == "true" ]; then
        if ! create_or_clone_template "$ctid" "$config_block"; then
            log_error "Failed to create or clone template $ctid ($container_name)."
            return 1 # Critical failure for templates
        fi
    else
        if ! clone_standard_container "$ctid" "$config_block"; then
            log_error "Failed to clone standard container $ctid ($container_name)."
            return 0 # Non-critical failure for standard containers
        fi
    fi

    # If creation/cloning was successful or container existed
    log_info "Waiting for container $ctid to be ready..."
    if ! wait_for_lxc_ready "$ctid"; then
        log_error "FATAL: Container $ctid did not become ready after creation/cloning."
        return 1 # Critical failure
    fi

    # Conditional Setups
    local gpu_assignment=$(jq -r '.gpu_assignment // "none"' <<< "$config_block")
    if [ "$gpu_assignment" != "none" ]; then
        log_info "Running NVIDIA setup for $ctid..."
        if ! setup_lxc_nvidia "$ctid" "$config_block"; then
            log_error "WARNING: NVIDIA setup failed for $ctid. Continuing with next step."
        fi
    fi

    local features=$(jq -r '.features // ""' <<< "$config_block")
    if [[ "$features" == *"nesting=1"* ]]; then
        log_info "Running Docker setup for $ctid..."
        if ! setup_lxc_docker "$ctid" "$config_block"; then
            log_error "WARNING: Docker setup failed for $ctid. Continuing with next step."
        fi
    fi

    log_info "Running specific setup script for $ctid (if exists)..."
    if ! run_specific_setup_script "$ctid"; then
        log_error "WARNING: Specific setup script failed for $ctid. Continuing with next step."
    fi

    log_info "Finalizing container state for $ctid..."
    if ! finalize_container_state "$ctid"; then
        log_error "FATAL: Failed to finalize state (shutdown, snapshot, restart) for $ctid."
        return 1 # Critical failure
    fi

    log_info "Successfully processed CTID: $ctid ($container_name)."
    return 0
}

# =====================================================================================
# Function: create_or_clone_template
# Description: Manages the creation or cloning of LXC template containers.
#              If `clone_from_template_ctid` is specified in the config, it clones
#              from an existing template's snapshot. Otherwise, it creates a new
#              base template. This function ensures the template is ready for
#              subsequent configuration and snapshotting.
#
# Parameters:
#   - $1 (CTID): The Container ID of the template to create or clone.
#   - $2 (config_block): A JSON string containing the specific configuration for the template.
#
# Dependencies:
#   - `phoenix_hypervisor_clone_lxc.sh`: Used for cloning existing templates.
#   - `phoenix_hypervisor_create_lxc.sh`: Used for creating base templates.
#   - `jq`: Used for parsing configuration data.
#
# Exit Conditions:
#   - Returns 1 for critical failures (e.g., source snapshot not found, script missing/not executable, cloning/creation failure).
#   - Returns 0 for success.
#
# RAG Keywords: LXC template creation, container cloning, base template, derived template,
#               ZFS snapshot, template hierarchy, idempotency, error handling.
# =====================================================================================
# =====================================================================================
create_or_clone_template() {
    local ctid="$1"
    local config_block="$2"
    local clone_from_template_ctid=$(jq -r '.clone_from_template_ctid // ""' <<< "$config_block")
    local exit_status=0

    log_info "Processing template CTID: $ctid"

    if [ -n "$clone_from_template_ctid" ]; then
        local source_snapshot_name=$(jq -r --arg s_ctid "$clone_from_template_ctid" '.lxc_configs[$s_ctid | tostring].template_snapshot_name // ""' "$LXC_CONFIG_FILE")
        if [ -z "$source_snapshot_name" ]; then
            log_error "FATAL: Source template snapshot name not found for CTID $clone_from_template_ctid."
            return 1
        fi
        log_info "Cloning template $ctid from $clone_from_template_ctid@$source_snapshot_name"
        local clone_script="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_clone_lxc.sh"
        if [ ! -f "$clone_script" ] || [ ! -x "$clone_script" ]; then
            log_error "FATAL: Clone script not found or not executable: $clone_script"
            return 1
        fi
        if ! "$clone_script" "$clone_from_template_ctid" "$source_snapshot_name" "$ctid" "$LXC_CONFIG_FILE" "$config_block"; then
            log_error "Failed to clone template $ctid from $clone_from_template_ctid@$source_snapshot_name."
            return 1
        fi
    else
        log_info "Creating base template CTID: $ctid"
        local create_script="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_create_lxc.sh"
        if [ ! -f "$create_script" ] || [ ! -x "$create_script" ]; then
            log_error "FATAL: Create script not found or not executable: $create_script"
            return 1
        fi
        if ! "$create_script" "$ctid"; then
            log_error "Failed to create base template $ctid."
            return 1
        fi
    fi

    # Template Setup Steps (run regardless of whether it was just created/cloned or already existed, idempotency handles it)
    # These steps are handled by process_single_lxc after this function returns.
    return 0
}

# =====================================================================================
# clone_standard_container(CTID, config_block)
#   Content:
#     - Log starting standard container cloning for CTID.
#     - Determine the best source template CTID and its snapshot name.
#         - Check if config_block.clone_from_template_ctid exists.
#         - If it exists:
#             - Use that CTID as the source.
#             - Determine the source template's snapshot name by re-parsing lxc_configs for the source CTID and getting its template_snapshot_name.
#         - If it does NOT exist:
#             - Analyze config_block (e.g., gpu_assignment, features like nesting=1, vllm_model) to determine the best existing template.
#             - This logic might involve checking for Docker (nesting=1), GPU (gpu_assignment != "none"), vLLM (vllm_model exists) in a hierarchy.
#             - For example: if Docker and GPU and vLLM -> use 920's snapshot. If Docker and GPU -> use 903's snapshot. If just Docker -> use 902's. If just GPU -> use 901's. Base -> use 900's.
#             - Determine the corresponding SOURCE_CTID and SOURCE_SNAPSHOT_NAME.
#     - Define hardcoded path: CLONE_SCRIPT="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_clone_lxc.sh"
#     - Check if CLONE_SCRIPT exists and is executable. Fatal error if not.
#     - Execute script: "$CLONE_SCRIPT" "$SOURCE_CTID" "$SOURCE_SNAPSHOT_NAME" "$CTID" # Pass key config details or the whole config_block if needed.
#     - Capture and handle its exit status. Log success/failure.
#     - If cloning failed, log error and return non-zero exit code.
#     - If cloning succeeded, log success.
#     - # Standard Container Setup Steps (run after successful cloning)
#     - If cloning was successful:
#         - Call wait_for_lxc_ready "$CTID".
#         - Capture exit code. If NOT successful, log error and return critical failure code.
#         - If wait was successful:
#             # Conditional setups are less likely needed here if cloning is comprehensive, but idempotent checks are safe.
#             # Call setup_lxc_nvidia "$CTID" "$config_block". # Unlikely needed.
#             # Capture exit code. Handle non-critical failure.
#             # Call setup_lxc_docker "$CTID" "$config_block". # Unlikely needed.
#             # Capture exit code. Handle non-critical failure.
#             - Call run_specific_setup_script "$CTID". # For final, unique container configuration.
#             - Capture exit code. Handle non-critical failure.
#     - Return appropriate exit code (0 for success, non-zero for any failure).
#   Purpose: Clones a standard (non-template) LXC container from a suitable pre-existing template snapshot.
# =====================================================================================
clone_standard_container() {
    local ctid="$1"
    local config_block="$2"
    local source_ctid=""
    local source_snapshot_name=""
    local exit_status=0

    log_info "Cloning standard container CTID: $ctid"

    local explicit_clone_from=$(jq -r '.clone_from_template_ctid // ""' <<< "$config_block")
    if [ -n "$explicit_clone_from" ]; then
        source_ctid="$explicit_clone_from"
        source_snapshot_name=$(jq -r --arg s_ctid "$source_ctid" '.lxc_configs[$s_ctid | tostring].template_snapshot_name // ""' "$LXC_CONFIG_FILE")
        if [ -z "$source_snapshot_name" ]; then
            log_error "FATAL: Explicit source template snapshot name not found for CTID $source_ctid."
            return 1
        fi
        log_info "Using explicit clone source: $source_ctid@$source_snapshot_name"
    else
        # Intelligent selection logic
        local needs_docker=$(jq -r '.features // ""' <<< "$config_block" | grep -q "nesting=1" && echo "true" || echo "false")
        local needs_gpu=$(jq -r '.gpu_assignment // "none"' <<< "$config_block" | grep -q "none" || echo "true")
        local needs_vllm=$(jq -r '.vllm_model // ""' <<< "$config_block" | grep -q "." && echo "true" || echo "false") # Check if vllm_model is not empty

        if [ "$needs_docker" == "true" ] && [ "$needs_gpu" == "true" ] && [ "$needs_vllm" == "true" ]; then
            source_ctid="920" # Assuming 920 is Docker+GPU+vLLM template
        elif [ "$needs_docker" == "true" ] && [ "$needs_gpu" == "true" ]; then
            source_ctid="903" # Assuming 903 is Docker+GPU template
        elif [ "$needs_docker" == "true" ]; then
            source_ctid="902" # Assuming 902 is Docker template
        elif [ "$needs_gpu" == "true" ]; then
            source_ctid="901" # Assuming 901 is GPU template
        else
            source_ctid="900" # Assuming 900 is Base OS template
        fi

        source_snapshot_name=$(jq -r --arg s_ctid "$source_ctid" '.lxc_configs[$s_ctid | tostring].template_snapshot_name // ""' "$LXC_CONFIG_FILE")
        if [ -z "$source_snapshot_name" ]; then
            log_error "FATAL: Automatically determined source template snapshot name not found for CTID $source_ctid."
            return 1
        fi
        log_info "Automatically determined clone source: $source_ctid@$source_snapshot_name"
    fi

    local clone_script="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_clone_lxc.sh"
    if [ ! -f "$clone_script" ] || [ ! -x "$clone_script" ]; then
        log_error "FATAL: Clone script not found or not executable: $clone_script"
        return 1
    fi

    if ! "$clone_script" "$source_ctid" "$source_snapshot_name" "$ctid" "$LXC_CONFIG_FILE" "$config_block"; then
        log_error "Failed to clone standard container $ctid from $source_ctid@$source_snapshot_name."
        return 0 # Non-critical failure for standard containers
    fi

    # Standard Container Setup Steps (run after successful cloning) are handled by process_single_lxc
    return 0
}

# =====================================================================================
# Function: create_lxc_container
# Description: Ensures a base LXC container is created using `pct create`. This function
#              is idempotent, meaning it will skip creation if the container already exists.
#              It is primarily used for establishing base templates or when direct container
#              creation is required.
#
# Parameters:
#   - $1 (CTID): The Container ID of the LXC container to create.
#   - $2 (config_block): A JSON string containing the specific configuration for the CTID.
#                        (Note: This parameter is currently not directly used within this function,
#                        but is kept for consistency with other processing functions.)
#
# Dependencies:
#   - `phoenix_hypervisor_create_lxc.sh`: Executes the actual container creation.
#
# Exit Conditions:
#   - Returns 1 for critical failures (e.g., create script missing/not executable, container creation failure).
#   - Returns 0 for success or if the container already exists.
#
# RAG Keywords: LXC container creation, base container, idempotency, Proxmox `pct create`, error handling.
# =====================================================================================
# =====================================================================================
create_lxc_container() {
    local ctid="$1"
    local config_block="$2" # Not directly used here, but kept for consistency if needed later
    local create_script="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_create_lxc.sh"

    log_info "Ensuring base LXC container $ctid is created."

    if [ ! -f "$create_script" ] || [ ! -x "$create_script" ]; then
        log_error "FATAL: Create script not found or not executable: $create_script"
        return 1
    fi

    # The create_lxc.sh script handles its own idempotency and exits 0 if container exists
    if ! "$create_script" "$ctid"; then
        log_error "Failed to create LXC container $ctid."
        return 1
    fi
    log_info "LXC container $ctid creation process completed."
    return 0
}

# =====================================================================================
# Function: wait_for_lxc_ready
# Description: Waits for a specified LXC container to be fully booted and responsive.
#              It periodically checks the container's status and attempts to execute
#              a simple command (`uptime`) inside it to confirm readiness.
#
# Parameters:
#   - $1 (CTID): The Container ID of the LXC container to monitor.
#
# Exit Conditions:
#   - Returns 0 if the container becomes ready within the timeout period.
#   - Returns 1 if the container does not become ready within the timeout period.
#
# RAG Keywords: LXC container readiness, boot status, container monitoring, timeout,
#               Proxmox `pct status`, `pct exec`, error handling.
# =====================================================================================
# =====================================================================================
wait_for_lxc_ready() {
    local ctid="$1"
    local timeout=180 # 3 minutes
    local interval=5  # 5 seconds
    local elapsed_time=0

    log_info "Waiting for container $ctid to be ready (timeout: ${timeout}s)..."

    while [ "$elapsed_time" -lt "$timeout" ]; do
        if pct status "$ctid" | grep -q "status: running"; then
            if pct exec "$ctid" -- uptime > /dev/null 2>&1; then
                log_info "Container $ctid is ready."
                return 0
            fi
        fi
        sleep "$interval"
        elapsed_time=$((elapsed_time + interval))
    done

    log_error "FATAL: Container $ctid did not become ready within ${timeout} seconds."
    return 1
}

# =====================================================================================
# Function: setup_lxc_nvidia
# Description: Conditionally configures NVIDIA drivers and tools within an LXC container
#              if `gpu_assignment` is specified in the container's configuration.
#              It delegates the actual setup to the common NVIDIA script, passing
#              global NVIDIA settings.
#
# Parameters:
#   - $1 (CTID): The Container ID where NVIDIA setup should be performed.
#   - $2 (config_block): A JSON string containing the specific configuration for the CTID,
#                        including `gpu_assignment`.
#
# Dependencies:
#   - `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_common_nvidia.sh`: The common script for NVIDIA setup.
#   - Global variables: `NVIDIA_DRIVER_VERSION`, `NVIDIA_REPO_URL`, `NVIDIA_RUNFILE_URL`.
#   - `jq`: Used for parsing configuration data.
#
# Exit Conditions:
#   - Returns 0 if NVIDIA setup is skipped or completes successfully.
#   - Returns 1 for critical failures (e.g., NVIDIA script missing/not executable).
#   - Returns the exit code of the common NVIDIA script if it fails.
#
# RAG Keywords: NVIDIA setup, GPU configuration, LXC container, driver installation,
#               CUDA toolkit, conditional execution, error handling.
# =====================================================================================
# =====================================================================================
setup_lxc_nvidia() {
    local ctid="$1"
    local config_block="$2"
    local nvidia_script="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_common_nvidia.sh"
    local gpu_assignment=$(jq -r '.gpu_assignment // "none"' <<< "$config_block")

    if [ "$gpu_assignment" == "none" ]; then
        log_info "NVIDIA setup skipped for CTID $ctid (gpu_assignment is 'none')."
        return 0
    fi

    if [ ! -f "$nvidia_script" ] || [ ! -x "$nvidia_script" ]; then
        log_error "FATAL: NVIDIA setup script not found or not executable: $nvidia_script"
        return 1 # Critical failure
    fi

    log_info "Executing NVIDIA setup for CTID $ctid..."
    # Pass global NVIDIA settings as environment variables
    GPU_ASSIGNMENT="$gpu_assignment" \
    NVIDIA_DRIVER_VERSION="$NVIDIA_DRIVER_VERSION" \
    NVIDIA_REPO_URL="$NVIDIA_REPO_URL" \
    NVIDIA_RUNFILE_URL="$NVIDIA_RUNFILE_URL" \
    "$nvidia_script" "$ctid"
    local exit_status=$?

    if [ "$exit_status" -ne 0 ]; then
        log_error "NVIDIA setup script failed for CTID $ctid with exit code $exit_status."
        return "$exit_status"
    fi
    log_info "NVIDIA setup for CTID $ctid completed successfully."
    return 0
}

# =====================================================================================
# Function: setup_lxc_docker
# Description: Conditionally installs and configures Docker within an LXC container
#              if the `nesting=1` feature is enabled in the container's configuration.
#              It also passes Portainer-specific details (role, server IP, agent port)
#              to the common Docker setup script.
#
# Parameters:
#   - $1 (CTID): The Container ID where Docker setup should be performed.
#   - $2 (config_block): A JSON string containing the specific configuration for the CTID,
#                        including `features` and `portainer_role`.
#
# Dependencies:
#   - `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_common_docker.sh`: The common script for Docker setup.
#   - `HYPERVISOR_CONFIG_FILE`: Used to extract global Portainer network settings.
#   - `jq`: Used for parsing configuration data.
#
# Exit Conditions:
#   - Returns 0 if Docker setup is skipped or completes successfully.
#   - Returns 1 for critical failures (e.g., Docker script missing/not executable).
#   - Returns the exit code of the common Docker script if it fails.
#
# RAG Keywords: Docker installation, Portainer configuration, LXC container,
#               nesting feature, containerization, conditional execution, error handling.
# =====================================================================================
# =====================================================================================
setup_lxc_docker() {
    local ctid="$1"
    local config_block="$2"
    local docker_script="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_common_docker.sh"
    local features=$(jq -r '.features // ""' <<< "$config_block")
    local portainer_role=$(jq -r '.portainer_role // "none"' <<< "$config_block")

    if [[ ! "$features" == *"nesting=1"* ]]; then
        log_info "Docker setup skipped for CTID $ctid (nesting=1 feature not found)."
        return 0
    fi

    if [ ! -f "$docker_script" ] || [ ! -x "$docker_script" ]; then
        log_error "FATAL: Docker setup script not found or not executable: $docker_script"
        return 1 # Critical failure
    fi

    local portainer_server_ip=$(jq -r '.network.portainer_server_ip // ""' "$HYPERVISOR_CONFIG_FILE")
    local portainer_agent_port=$(jq -r '.network.portainer_agent_port // ""' "$HYPERVISOR_CONFIG_FILE")

    log_info "Executing Docker setup for CTID $ctid..."
    # Pass Portainer details as environment variables
    PORTAINER_ROLE="$portainer_role" \
    PORTAINER_SERVER_IP="$portainer_server_ip" \
    PORTAINER_AGENT_PORT="$portainer_agent_port" \
    "$docker_script" "$ctid"
    local exit_status=$?

    if [ "$exit_status" -ne 0 ]; then
        log_error "Docker setup script failed for CTID $ctid with exit code $exit_status."
        return "$exit_status"
    fi
    log_info "Docker setup for CTID $ctid completed successfully."
    return 0
}

# =====================================================================================
# Function: run_specific_setup_script
# Description: Executes an optional, container-specific setup script for a given CTID.
#              These scripts are used for unique customizations. For template containers,
#              this script is responsible for creating the final template snapshot.
#              For standard containers, it performs any final, unique configurations.
#
# Parameters:
#   - $1 (CTID): The Container ID for which to run the specific setup script.
#
# Dependencies:
#   - `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_${CTID}.sh`: The specific setup script (if it exists).
#
# Exit Conditions:
#   - Returns 0 if no specific script is found, or if the script executes successfully.
#   - Returns 1 if the specific script exists but fails during execution.
#
# RAG Keywords: container customization, template snapshot, unique configuration,
#               LXC setup script, conditional execution, error handling.
# =====================================================================================
# =====================================================================================
run_specific_setup_script() {
    local ctid="$1"
    local specific_script="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_${ctid}.sh" # Using lxc_ prefix for consistency

    if [ ! -f "$specific_script" ] || [ ! -x "$specific_script" ]; then
        log_info "No specific setup script found or executable for CTID $ctid ($specific_script). Skipping."
        return 0
    fi

    log_info "Executing specific setup script for CTID $ctid: $specific_script"
    if ! "$specific_script" "$ctid"; then
        log_error "Specific setup script $specific_script failed for CTID $ctid."
        return 1 # Non-critical failure
    fi
    log_info "Specific setup script for CTID $ctid completed successfully."
    return 0
}

# =====================================================================================
# Function: finalize_container_state
# Description: Finalizes the state of an LXC container or template by performing
#              a controlled shutdown, creating a "configured-state" ZFS snapshot,
#              and then restarting the container. This ensures a consistent and
#              recoverable state after all setup procedures are complete.
#
# Parameters:
#   - $1 (CTID): The Container ID of the LXC container to finalize.
#
# Dependencies:
#   - `pct`: Proxmox VE Container Toolkit commands (`pct shutdown`, `pct snapshot create`, `pct start`, `pct status`).
#
# Exit Conditions:
#   - Returns 0 if the container state is finalized successfully.
#   - Returns 1 for any critical failure during shutdown, snapshot creation, or restart.
#
# RAG Keywords: container state, ZFS snapshot, LXC shutdown, LXC restart,
#               configured state, idempotency, error handling.
# =====================================================================================
# =====================================================================================
finalize_container_state() {
    local ctid="$1"
    local timeout=60 # seconds
    local interval=3 # seconds
    local elapsed_time=0

    log_info "Finalizing container state for CTID: $ctid (Shutdown, Snapshot, Restart)"

    log_info "Shutting down container $ctid..."
    if ! pct shutdown "$ctid"; then
        log_error "FATAL: Failed to initiate shutdown for container $ctid."
        return 1
    fi

    elapsed_time=0
    while [ "$elapsed_time" -lt "$timeout" ]; do
        if pct status "$ctid" | grep -q "status: stopped"; then
            log_info "Container $ctid is stopped."
            break
        fi
        sleep "$interval"
        elapsed_time=$((elapsed_time + interval))
    done
    if [ "$elapsed_time" -ge "$timeout" ]; then
        log_error "FATAL: Container $ctid did not stop within ${timeout} seconds."
        return 1
    fi

    log_info "Creating 'configured-state' snapshot for container $ctid..."
    if ! pct snapshot create "$ctid" "configured-state"; then
        log_error "FATAL: Failed to create 'configured-state' snapshot for container $ctid."
        return 1
    fi

    log_info "Starting container $ctid..."
    if ! pct start "$ctid"; then
        log_error "FATAL: Failed to start container $ctid."
        return 1
    fi

    elapsed_time=0
    while [ "$elapsed_time" -lt "$timeout" ]; do
        if pct status "$ctid" | grep -q "status: running"; then
            log_info "Container $ctid is running."
            break
        fi
        sleep "$interval"
        elapsed_time=$((elapsed_time + interval))
    done
    if [ "$elapsed_time" -ge "$timeout" ]; then
        log_error "FATAL: Container $ctid did not start within ${timeout} seconds."
        return 1
    fi

    log_info "Container $ctid state finalized."
    return 0
}

# =====================================================================================
# Function: finalize_and_exit
# Description: Performs final cleanup and reports the overall status of the orchestrator's run.
#              This includes logging a summary message and exiting the script with an
#              appropriate status code.
#
# Parameters: None
#
# Exit Conditions:
#   - Exits with code 0 for successful completion of all targeted operations.
#   - Exits with a non-zero code if critical failures occurred during processing.
#
# RAG Keywords: script finalization, exit status, orchestration summary, error reporting.
# =====================================================================================
# =====================================================================================
finalize_and_exit() {
    log_info "Orchestrator run complete."
    # In a more advanced version, we'd track successes/failures and print a summary.
    exit_script 0
}

# =====================================================================================
# Function: main
# Description: The main entry point of the Phoenix Hypervisor orchestrator script.
#              It sequentially calls functions to initialize the environment, load and
#              validate configurations, perform initial host setup, process all LXC
#              containers and templates, and finalize the script's execution.
#
# Parameters: None
#
# Dependencies:
#   - `initialize_environment()`
#   - `load_and_validate_configs()`
#   - `run_initial_host_setup()`
#   - `process_lxc_containers()`
#   - `finalize_and_exit()`
#
# RAG Keywords: main function, script entry point, orchestration flow, LXC management.
# =====================================================================================
# =====================================================================================
main() {
    initialize_environment
    load_and_validate_configs
    run_initial_host_setup
    process_lxc_containers
    finalize_and_exit
}

# Call the main function
main