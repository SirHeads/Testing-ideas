#!/bin/bash
#
# File: phoenix_hypervisor_clone_lxc.sh
# Description: Clones an LXC container from a specified template container's ZFS snapshot.
# Version: 0.1.0
# Author: Heads, Qwen3-coder (AI Assistant)
#
# This script handles the `pct clone` command to create a new LXC container based on
# a snapshot of an existing template container. It configures the new container
# with settings derived from its specific configuration block.
#
# Usage: ./phoenix_hypervisor_clone_lxc.sh <SOURCE_CTID> <SOURCE_SNAPSHOT_NAME> <TARGET_CTID> <LXC_CONFIG_FILE> <TARGET_CONFIG_BLOCK_JSON>
# Example: ./phoenix_hypervisor_clone_lxc.sh 902 docker-snapshot 910 /path/to/phoenix_lxc_configs.json '{"name":"MyApp","memory_mb":4096,...}'
#
# Arguments:
#   $1 - SOURCE_CTID (integer): The Container ID of the template container to clone from.
#   $2 - SOURCE_SNAPSHOT_NAME (string): The name of the ZFS snapshot of the source container to use.
#   $3 - TARGET_CTID (integer): The Container ID for the new container to be created.
#   $4 - LXC_CONFIG_FILE (string): Path to the main LXC configuration JSON file (for reference, if needed).
#   $5 - TARGET_CONFIG_BLOCK_JSON (string): The JSON string representing the configuration block for the *target* container.
#                                        This should be passed by the orchestrator and contains the specific settings
#                                        (name, IP, resources, features, etc.) for the new container.
#
# Requirements:
#   - pct (Proxmox VE Container Toolkit)
#   - jq (for parsing JSON if needed)
#   - Access to Proxmox host and defined storage paths
#   - The source container and its specified snapshot must exist.
#
# Exit Codes:
#   0: Success (Container cloned and configured successfully)
#   1: General error
#   2: Invalid input arguments
#   3: Source container or snapshot does not exist
#   4: pct clone command failed
#   5: Post-clone configuration adjustments failed

# =====================================================================================
# main()
#   Content:
#     - Entry point.
#     - Calls parse_arguments to get SOURCE_CTID, SOURCE_SNAPSHOT_NAME, TARGET_CTID, LXC_CONFIG_FILE, TARGET_CONFIG_BLOCK_JSON.
#     - Calls validate_inputs to check argument validity and existence of source/snapshot.
#     - Calls construct_pct_clone_command using TARGET_CTID, SOURCE_CTID, SOURCE_SNAPSHOT_NAME, and TARGET_CONFIG_BLOCK_JSON.
#     - Calls execute_pct_clone to run the constructed command.
#     - Calls apply_post_clone_configurations (if needed, e.g., for specific network adjustments not handled perfectly by clone).
#     - Calls exit_script.
#   Purpose: Controls the overall flow of the LXC cloning process.
# =====================================================================================

# --- Main Script Execution Starts Here ---

# =====================================================================================
# parse_arguments()
#   Content:
#     - Check the number of command-line arguments. Expect exactly 5.
#     - If incorrect number of arguments, log a usage error message and call exit_script 2.
#     - Assign arguments to variables:
#         SOURCE_CTID=$1
#         SOURCE_SNAPSHOT_NAME=$2
#         TARGET_CTID=$3
#         LXC_CONFIG_FILE=$4 # Might be needed for complex lookups, but TARGET_CONFIG_BLOCK_JSON should have most needed info.
#         TARGET_CONFIG_BLOCK_JSON=$5
#     - Log the received arguments (source, target, snapshot name).
#   Purpose: Retrieves and stores the input arguments for the script.
# =====================================================================================

# =====================================================================================
# validate_inputs()
#   Content:
#     - Validate that SOURCE_CTID, TARGET_CTID are positive integers. If not, log error and call exit_script 2.
#     - Validate that SOURCE_SNAPSHOT_NAME, LXC_CONFIG_FILE, and TARGET_CONFIG_BLOCK_JSON are non-empty strings. If not, log error and call exit_script 2.
#     - Check if the source container exists: `pct status "$SOURCE_CTID" > /dev/null 2>&1`.
#         - If it does not exist, log error and call exit_script 3.
#     - Check if the specified snapshot exists on the source container.
#         - This might involve `pct snapshot list "$SOURCE_CTID"` and parsing the output with `jq` or `grep`.
#         - If the snapshot does not exist, log error and call exit_script 3.
#     - (Optional) Validate the JSON syntax of TARGET_CONFIG_BLOCK_JSON using `jq empty <<< "$TARGET_CONFIG_BLOCK_JSON"`. If invalid, log error and call exit_script 2.
#     - Log validation passed.
#   Purpose: Ensures all inputs are present, valid, and that the source container and snapshot exist.
# =====================================================================================

# =====================================================================================
# construct_pct_clone_command()
#   Content:
#     - Log starting construction of the pct clone command.
#     - Initialize an empty array or string for the command: PCT_CLONE_CMD=("pct" "clone").
#     - Add positional arguments: SOURCE_CTID, TARGET_CTID.
#     - Add the snapshot argument: --snapshot "$SOURCE_SNAPSHOT_NAME".
#     - Extract arguments from TARGET_CONFIG_BLOCK_JSON using `jq`:
#         - --hostname: `jq -r '.name' <<< "$TARGET_CONFIG_BLOCK_JSON"`
#         - --memory: `jq -r '.memory_mb' <<< "$TARGET_CONFIG_BLOCK_JSON"`
#         - --cores: `jq -r '.cores' <<< "$TARGET_CONFIG_BLOCK_JSON"`
#         - --storage: `jq -r '.storage_pool' <<< "$TARGET_CONFIG_BLOCK_JSON"`
#         - Potentially --rootfs size if resizing is needed/desired (e.g., `jq -r '.storage_size_gb' <<< "$TARGET_CONFIG_BLOCK_JSON"` -> `storage_pool:size`).
#         - --features: `jq -r '.features' <<< "$TARGET_CONFIG_BLOCK_JSON"`
#         - --hostname: `jq -r '.name' <<< "$TARGET_CONFIG_BLOCK_JSON"` (if not already set by --hostname, or to be safe).
#         - --unprivileged: Map `jq -r '.unprivileged' <<< "$TARGET_CONFIG_BLOCK_JSON"` (boolean `true`/`false`) to `1`/`0`.
#         - Network configuration is trickier with clone. `pct clone` primarily clones the config.
#             - The orchestrator should ensure the source template's config is generic enough.
#             - Post-clone adjustments might be needed for IP/MAC. This script can handle that.
#             - For now, assume basic clone. If specific network settings are critical and not handled by post-clone, they could be added here,
#               but it's often easier post-clone. Let's lean towards post-clone for network.
#     - Combine arguments into the final command string or ensure the array is correctly formed.
#     - Log the constructed command string (for debugging).
#   Purpose: Dynamically builds the full `pct clone` command string based on the target container's specific configuration.
# =====================================================================================

# =====================================================================================
# execute_pct_clone()
#   Content:
#     - Log executing the pct clone command.
#     - Execute the command stored in PCT_CLONE_CMD (e.g., `"${PCT_CLONE_CMD[@]}"` if it's an array).
#     - Capture the exit code.
#     - If the exit code is 0:
#         - Log successful execution of pct clone.
#     - If the exit code is non-zero:
#         - Log a fatal error indicating `pct clone` failed for TARGET_CTID, including the command that was run and the exit code.
#         - Call exit_script 4.
#   Purpose: Runs the constructed `pct clone` command and handles its success or failure.
# =====================================================================================

# =====================================================================================
# apply_post_clone_configurations()
#   Content:
#     - Log applying post-clone configurations for TARGET_CTID.
#     - Extract specific network settings from TARGET_CONFIG_BLOCK_JSON:
#         - IP: `jq -r '.network_config.ip' <<< "$TARGET_CONFIG_BLOCK_JSON"`
#         - Gateway: `jq -r '.network_config.gw' <<< "$TARGET_CONFIG_BLOCK_JSON"`
#         - MAC: `jq -r '.mac_address' <<< "$TARGET_CONFIG_BLOCK_JSON"`
#         - Interface name (usually eth0): `jq -r '.network_config.name' <<< "$TARGET_CONFIG_BLOCK_JSON"`
#     - Use `pct set` commands to apply these specific settings to the newly cloned container.
#         - Example: `pct set "$TARGET_CTID" -net0 "name=eth0,bridge=vmbr0,ip=10.0.0.110/24,gw=10.0.0.1,hwaddr=52:54:00:67:89:A0"`
#         - Construct the network string dynamically from the extracted values.
#         - Execute `pct set "$TARGET_CTID" -net0 "$CONSTRUCTED_NETWORK_STRING"`.
#         - Capture exit code. Handle failure (log, exit_script 5).
#     - (Optional) Apply other specific settings if `pct clone` doesn't capture them perfectly (e.g., very specific mounts, descriptions).
#     - Log post-clone configurations applied.
#   Purpose: Fine-tunes the configuration of the newly cloned container to match its specific requirements, especially network settings.
# =====================================================================================

# =====================================================================================
# exit_script(exit_code)
#   Content:
#     - Accept an integer exit_code.
#     - If exit_code is 0:
#         - Log a success message (e.g., "Container TARGET_CTID cloned from SOURCE_CTID@SOURCE_SNAPSHOT_NAME successfully").
#     - If exit_code is non-zero:
#         - Log a failure message indicating the script encountered an error, specifying the stage if possible.
#     - Ensure logs are flushed.
#     - Exit the script with the provided exit_code.
#   Purpose: Provides a single point for script termination, ensuring final logging and correct exit status.
# =====================================================================================