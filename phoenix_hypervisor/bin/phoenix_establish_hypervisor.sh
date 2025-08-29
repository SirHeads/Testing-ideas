#!/bin/bash
#
# File: phoenix_establish_hypervisor.sh
# Description: Orchestrator script for creating and configuring LXC containers and templates for an AI Toolbox using ZFS snapshots.
# Version: 0.3.0 (Reflects full snapshot template hierarchy and cloning logic)
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script automates the creation/cloning of LXC containers and templates based on configurations defined in
# phoenix_lxc_configs.json. It leverages ZFS snapshots for optimized creation, handles Proxmox setup,
# conditional NVIDIA/Docker setup, and specific container/template customization.
#
# Usage: ./phoenix_establish_hypervisor.sh
# Requirements:
#   - jq (for JSON parsing)
#   - ajv-cli (for JSON schema validation)
#   - pct (Proxmox VE Container Toolkit)
#   - Access to Proxmox host and defined storage paths
#   - ZFS storage pool configured for LXC
#
# Exit Codes:
#   0: Success
#   1: General error
#   2: Configuration validation error
#   3: Host setup error
#   4: Critical script missing
#   5: Critical container/template processing failure

# =====================================================================================
# main()
#   Content:
#     - Entry point.
#     - Calls load_and_validate_configs.
#     - Calls initialize_environment.
#     - Calls run_initial_host_setup.
#     - Calls process_lxc_containers.
#     - Calls finalize_and_exit.
#   Purpose: Controls overall flow of the orchestrator.
# =====================================================================================

# --- Main Script Execution Starts Here ---

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

# =====================================================================================
# initialize_environment()
#   Content:
#     - Define main log file path (e.g., /var/log/phoenix_hypervisor.log).
#     - Initialize/Clear the main log file.
#     - Log script start message with timestamp/version.
#     - Source common library functions from /usr/local/phoenix_hypervisor/lib/.
#         Example: source /usr/local/phoenix_hypervisor/lib/common_functions.sh
#         Handle failure to source.
#     - (Optional/Implied) Read debug_mode and rollback_on_failure flags.
#   Purpose: Prepares runtime environment (logging, utilities, flags).
# =====================================================================================

# =====================================================================================
# run_initial_host_setup()
#   Content:
#     - Define hardcoded path: SETUP_SCRIPT="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_initial_setup.sh"
#     - Check if SETUP_SCRIPT exists and is executable. Fatal error if not.
#     - Execute the script: "$SETUP_SCRIPT"
#     - Capture its exit code ($?).
#     - If exit code is non-zero, log fatal error (host setup failed) and exit orchestrator.
#   Purpose: Ensures Proxmox host has necessary tools (jq, curl, ajv-cli) and configs.
# =====================================================================================

# =====================================================================================
# process_lxc_containers()
#   Content:
#     - Get list of CTIDs from lxc_configs (e.g., jq 'keys | map(tonumber)' "$LXC_CONFIG_FILE"). Sorting numerically is assumed to respect template dependencies.
#     - Iterate through the list of CTIDs.
#     - For each CTID:
#         - Extract specific config_block (e.g., jq -r --arg ctid "$CTID" '.lxc_configs[$ctid]' "$LXC_CONFIG_FILE").
#         - Call process_single_lxc "$CTID" "$config_block".
#         - Capture exit code from process_single_lxc.
#         - (Critical Error Handling) If process_single_lxc fails critically (e.g., a template fails), log the error and exit the orchestrator to prevent dependent containers from failing.
#         - (Independent Error Handling) If process_single_lxc fails for a standalone container, log the error and continue with the next CTID.
#   Purpose: Main loop, orchestrates the creation/configuration/cloning of each LXC container/template, generally respecting numerical order for dependencies.
# =====================================================================================

# =====================================================================================
# process_single_lxc(CTID, config_block)
#   Content:
#     - Log start of processing for CTID (e.g., "Processing container/template CTID: <name>").
#     - Determine action based on config_block:
#         - Check if config_block.is_template is true.
#         - If IS_TEMPLATE:
#             - Call create_or_clone_template "$CTID" "$config_block".
#         - If NOT IS_TEMPLATE:
#             - Call clone_standard_container "$CTID" "$config_block".
#     - Capture exit code from the action (create_or_clone_template or clone_standard_container).
#     - If the action (create/clone) was successful or indicates the container already existed/configured:
#         - Call wait_for_lxc_ready "$CTID".
#         - Capture exit code. If NOT successful, log error and return critical failure code.
#         - If wait was successful:
#             - (Conditional Setups - Post Clone/Create): These might be skipped if cloning handles them, but idempotent checks ensure safety.
#                 - Call setup_lxc_nvidia "$CTID" "$config_block". # Only if needed and not fully handled by cloning.
#                 - Capture exit code. Handle non-critical failure.
#                 - Call setup_lxc_docker "$CTID" "$config_block". # Only if needed and not fully handled by cloning.
#                 - Capture exit code. Handle non-critical failure.
#             - Call run_specific_setup_script "$CTID".
#             - Capture exit code. Handle non-critical failure.
#             - Call finalize_container_state "$CTID". # Shutdown, snapshot (configured-state), restart.
#             - Capture exit code. Handle critical failure (if this step fails, it's a problem).
#     - Log completion/skipping/failure for CTID.
#     - Return appropriate exit code:
#         - 0: Success (container/template processed).
#         - Non-zero: Failure. Differentiate between critical (stops process) and non-critical (continues).
#     - Handle errors (logging, potential rollback for CTID, decide to continue or halt based on error type).
#   Purpose: Manages the end-to-end process for a single LXC container or template, determining if it's created, cloned from a base, or is a standard container cloned from a template.
# =====================================================================================

# =====================================================================================
# create_or_clone_template(CTID, config_block)
#   Content:
#     - Log starting template processing for CTID.
#     - Check if config_block.clone_from_template_ctid exists.
#     - If CLONE_FROM_TEMPLATE_CTID exists:
#         - Extract source CTID from config_block.clone_from_template_ctid.
#         - Determine the source template's snapshot name by re-parsing lxc_configs for the source CTID and getting its template_snapshot_name.
#             - Example: SOURCE_SNAPSHOT_NAME=$(jq -r --arg s_ctid "$SOURCE_CTID" '.lxc_configs[$s_ctid].template_snapshot_name' "$LXC_CONFIG_FILE")
#         - Define hardcoded path: CLONE_SCRIPT="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_clone_lxc.sh"
#         - Check if CLONE_SCRIPT exists and is executable. Fatal error if not.
#         - Execute script: "$CLONE_SCRIPT" "$SOURCE_CTID" "$SOURCE_SNAPSHOT_NAME" "$CTID" # Pass key config details or the whole config_block if needed.
#         - Capture and handle its exit status. Log success/failure.
#         - If cloning failed, log error and return non-zero exit code.
#         - If cloning succeeded, log success.
#     - If CLONE_FROM_TEMPLATE_CTID does NOT exist (Base Template):
#         - Define hardcoded path: CREATE_SCRIPT="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_create_lxc.sh"
#         - Perform idempotency check: pct status "$CTID" > /dev/null 2>&1
#         - If container does NOT exist:
#             - Check if CREATE_SCRIPT exists and is executable. Fatal error if not.
#             - Execute script: "$CREATE_SCRIPT" "$CTID"
#             - Capture and handle its exit status. Log success/failure.
#             - If creation failed, log error and return non-zero exit code.
#             - If creation succeeded, log success.
#         - If container DOES exist, log that base creation is skipped for CTID.
#     - # Template Setup Steps (run regardless of whether it was just created/cloned or already existed, idempotency handles it)
#     - If creation/cloning was successful or container existed:
#         - Call wait_for_lxc_ready "$CTID".
#         - Capture exit code. If NOT successful, log error and return critical failure code.
#         - If wait was successful:
#             - Call setup_lxc_nvidia "$CTID" "$config_block". # If needed for the template.
#             - Capture exit code. Handle non-critical failure.
#             - Call setup_lxc_docker "$CTID" "$config_block". # If needed for the template.
#             - Capture exit code. Handle non-critical failure.
#             - Call run_specific_setup_script "$CTID". # This script is responsible for finalizing the template env and creating its snapshot.
#             - Capture exit code. Handle critical failure (template snapshot creation is critical).
#     - Return appropriate exit code (0 for success, non-zero for any failure).
#   Purpose: Handles the specific logic for creating or cloning a template container. If it's a base template, it uses creation. If it's a derived template, it uses cloning. Its specific setup script creates the template snapshot.
# =====================================================================================

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

# =====================================================================================
# create_lxc_container(CTID, config_block)
#   Content:
#     - Define hardcoded path: CREATE_SCRIPT="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_create_lxc.sh"
#     - Perform idempotency check: pct status "$CTID" > /dev/null 2>&1
#     - If container does NOT exist:
#         - Check if CREATE_SCRIPT exists and is executable. Fatal error if not.
#         - Execute script: "$CREATE_SCRIPT" "$CTID"
#         - Capture and handle its exit status. Log success/failure.
#         - If creation failed, log error and return non-zero exit code.
#         - If creation succeeded, log success.
#     - If container DOES exist, log that creation is skipped for CTID.
#     - Return appropriate exit code (0 for success or already exists, non-zero for failure).
#   Purpose: Ensures base LXC container CTID is created via pct create, skipping if already present. (Used primarily by base templates or if direct creation is needed).
# =====================================================================================

# =====================================================================================
# wait_for_lxc_ready(CTID)
#   Content:
#     - Log waiting message for CTID.
#     - Define timeout (e.g., 120s) and polling interval (e.g., 5s).
#     - Initialize counter/end time.
#     - Implement while loop:
#         - Check pct status "$CTID" to ensure it's 'running'.
#         - If running, attempt pct exec "$CTID" -- uptime > /dev/null 2>&1.
#         - If pct exec succeeds (exit code 0), container is ready. Break loop.
#         - If not ready, sleep for interval.
#         - Check if timeout exceeded. If so, log timeout error for CTID, return failure code.
#     - If loop exits successfully, log CTID is ready.
#     - Return appropriate exit code (0 for ready, non-zero for timeout/error).
#   Purpose: Ensures LXC CTID is fully booted and responsive before configuring software inside or proceeding.
# =====================================================================================

# =====================================================================================
# setup_lxc_nvidia(CTID, config_block)
#   Content:
#     - Define hardcoded path: NVIDIA_SCRIPT="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_nvidia.sh"
#     - Extract gpu_assignment from config_block (e.g., GPU_ASSIGNMENT=$(echo "$config_block" | jq -r '.gpu_assignment')).
#     - Check GPU_ASSIGNMENT. If it is NOT "none":
#         - Check if NVIDIA_SCRIPT exists and is executable. Fatal error if not.
#         - Execute script: "$NVIDIA_SCRIPT" "$CTID" "$NVIDIA_DRIVER_VERSION" "$NVIDIA_REPO_URL" "$NVIDIA_RUNFILE_URL" # Pass Runfile URL
#         - Capture and handle its exit status. Log success/failure.
#         - Return exit code from NVIDIA_SCRIPT.
#     - If GPU_ASSIGNMENT is "none", log that NVIDIA setup is skipped for CTID.
#     - Return appropriate exit code (0 for success/skipped, non-zero for failure).
#   Purpose: Conditionally configures NVIDIA drivers/tools in LXC CTID based on gpu_assignment. Passes global NVIDIA settings including the runfile URL.
# =====================================================================================

# =====================================================================================
# setup_lxc_docker(CTID, config_block)
#   Content:
#     - Define hardcoded path: DOCKER_SCRIPT="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_docker.sh"
#     - Extract features from config_block (e.g., FEATURES=$(echo "$config_block" | jq -r '.features')).
#     - Check FEATURES for substring nesting=1.
#     - If nesting=1 is found:
#         - Check if DOCKER_SCRIPT exists and is executable. Fatal error if not.
#         - Extract portainer_role (e.g., PORTAINER_ROLE=$(echo "$config_block" | jq -r '.portainer_role')).
#         - Extract network_config.portainer_server_ip and portainer_agent_port from HYPERVISOR_CONFIG_FILE or pass them. # Needed by Docker script.
#             - PORTAINER_SERVER_IP=$(jq -r '.network.portainer_server_ip' "$HYPERVISOR_CONFIG_FILE")
#             - PORTAINER_AGENT_PORT=$(jq -r '.network.portainer_agent_port' "$HYPERVISOR_CONFIG_FILE")
#         - Execute script: "$DOCKER_SCRIPT" "$CTID" "$PORTAINER_ROLE" "$PORTAINER_SERVER_IP" "$PORTAINER_AGENT_PORT" # Pass Portainer details
#         - Capture and handle its exit status. Log success/failure.
#         - Return exit code from DOCKER_SCRIPT.
#     - If nesting=1 is not found, log that Docker setup is skipped for CTID.
#     - Return appropriate exit code (0 for success/skipped, non-zero for failure).
#   Purpose: Conditionally installs/configures Docker in LXC CTID if nesting=1. Passes portainer_role and network details.
# =====================================================================================

# =====================================================================================
# run_specific_setup_script(CTID)
#   Content:
#     - Define hardcoded path pattern: SPECIFIC_SCRIPT="/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_setup_${CTID}.sh"
#     - Check if SPECIFIC_SCRIPT exists and is executable.
#     - If it exists:
#         - Log running specific setup script for CTID.
#         - Execute script: "$SPECIFIC_SCRIPT" "$CTID"
#         - Capture and handle its exit status. Log success/failure.
#         - Return exit code from SPECIFIC_SCRIPT.
#     - If it does not exist, log that no specific setup script was found for CTID.
#     - Return appropriate exit code (0 for success/skipped, non-zero for failure if script existed but failed).
#   Purpose: Allows optional, container-specific customization. For templates, this includes creating the template snapshot. For standard containers, this is final unique setup.
# =====================================================================================

# =====================================================================================
# finalize_container_state(CTID)
#   Content:
#     - Log finalizing state for CTID.
#     - Execute: pct shutdown "$CTID"
#     - Wait for shutdown (e.g., poll pct status).
#         - Implement a loop with timeout to check if status is 'stopped'.
#     - If shutdown failed/timed out, log error and return failure code.
#     - Execute: pct snapshot create "$CTID" "configured-state"
#     - Capture exit code. If failed, log error and return failure code.
#     - Execute: pct start "$CTID"
#     - Wait for start (e.g., poll pct status).
#         - Implement a loop with timeout to check if status is 'running'.
#     - If start failed/timed out, log error and return failure code.
#     - Log state finalized for CTID.
#     - Return appropriate exit code (0 for success, non-zero for failure).
#   Purpose: Ensures every container/template takes a final "configured-state" snapshot after its specific setup is complete.
# =====================================================================================

# =====================================================================================
# finalize_and_exit()
#   Content:
#     - Log summary message indicating orchestrator run is complete.
#     - Print summary of actions (number of containers/templates processed, list of CTIDs, errors).
#     - Ensure main log file is flushed/closed.
#     - Exit script with appropriate code:
#         - 0: Success (all targeted containers/templates processed).
#         - Non-zero: Critical failure occurred during processing.
#   Purpose: Cleans up, reports final status, terminates orchestrator.
# =====================================================================================