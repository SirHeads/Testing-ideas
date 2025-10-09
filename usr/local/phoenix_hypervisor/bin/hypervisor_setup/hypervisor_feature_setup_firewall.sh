#!/bin/bash

# File: hypervisor_feature_setup_firewall.sh
# Description: This script configures the global, datacenter-level firewall settings for the Proxmox VE host.
#              It operates in a declarative manner, reading the desired state from the main `phoenix_hypervisor_config.json` file.
#              The script can enable or disable the firewall service and set the default inbound and outbound policies (e.g., ACCEPT, DROP).
#              This is a key part of the hypervisor setup process, establishing the baseline security posture for the entire cluster
#              before any guest-specific rules are applied.
#
# Dependencies:
#   - /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh: For shared logging and utility functions.
#   - `jq`: For parsing the JSON configuration file.
#   - `pve-firewall`: The Proxmox VE firewall command-line tool.
#
# Inputs:
#   - A path to a JSON configuration file (e.g., `phoenix_hypervisor_config.json`) passed as the first command-line argument.
#   - The JSON file is expected to contain a `.firewall` object with:
#     - `enabled`: A boolean (`true` or `false`) to enable or disable the firewall service.
#     - `default_input_policy`: The default policy for incoming traffic (e.g., "ACCEPT", "DROP").
#     - `default_output_policy`: The default policy for outgoing traffic (e.g., "ACCEPT", "DROP").
#
# Outputs:
#   - Starts or stops the `pve-firewall` service.
#   - Sets the default input and output policies at the cluster level.
#   - Logs its progress to standard output.
#   - Exit Code: 0 on success.

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Main Logic ---
main() {
    log_info "Configuring global firewall settings..."

    # Read the desired firewall state from the declarative configuration file.
    local firewall_enabled=$(jq -r '.firewall.enabled' "$HYPERVISOR_CONFIG_FILE")
    if [ "$firewall_enabled" != "true" ]; then
        log_info "Firewall is not enabled in the global config. Disabling..."
        pve-firewall stop
        return 0
    fi

    log_info "Enabling Proxmox firewall..."
    pve-firewall start

    # Read the default policies for inbound and outbound traffic.
    local input_policy=$(jq -r '.firewall.default_input_policy' "$HYPERVISOR_CONFIG_FILE")
    local output_policy=$(jq -r '.firewall.default_output_policy' "$HYPERVISOR_CONFIG_FILE")

    # Apply the default input policy to the entire cluster.
    log_info "Setting default input policy to: $input_policy"
    pve-firewall set /cluster/firewall/options -policy_in "$input_policy"

    # Apply the default output policy to the entire cluster.
    log_info "Setting default output policy to: $output_policy"
    pve-firewall set /cluster/firewall/options -policy_out "$output_policy"

    # Apply global firewall rules
    log_info "Applying global firewall rules..."
    local rules
    rules=$(jq -c '.firewall.global_firewall_rules[]?' "$HYPERVISOR_CONFIG_FILE")
    if [ -n "$rules" ]; then
        echo "$rules" | while read -r rule; do
            local type=$(echo "$rule" | jq -r '.type')
            local action=$(echo "$rule" | jq -r '.action')
            local source=$(echo "$rule" | jq -r '.source')
            local dest=$(echo "$rule" | jq -r '.dest')
            local proto=$(echo "$rule" | jq -r '.proto')
            local port=$(echo "$rule" | jq -r '.port')

            log_info "Adding rule: type=$type, action=$action, source=$source, dest=$dest, proto=$proto, port=$port"
            pve-firewall set /cluster/firewall/rules -type "$type" -action "$action" -source "$source" -dest "$dest" -proto "$proto" -dport "$port"
        done
    else
        log_info "No global firewall rules to apply."
    fi

    log_info "Global firewall settings configured successfully."
}

main "$@"