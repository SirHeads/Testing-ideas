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
generate_rule_string() {
    local rule_json="$1"
    local type=$(echo "$rule_json" | jq -r '.type // ""')
    local action=$(echo "$rule_json" | jq -r '.action // ""')
    local proto=$(echo "$rule_json" | jq -r '.proto // ""')
    local source=$(echo "$rule_json" | jq -r '.source // ""')
    local dest=$(echo "$rule_json" | jq -r '.dest // ""')
    local port=$(echo "$rule_json" | jq -r '.port // ""')
    local comment=$(echo "$rule_json" | jq -r '.comment // ""')

    local rule_string="${type^^} ${action}"
    [ -n "$proto" ] && rule_string+=" -p ${proto}"
    [ -n "$source" ] && rule_string+=" -source ${source}"
    [ -n "$dest" ] && rule_string+=" -dest ${dest}"
    [ -n "$port" ] && rule_string+=" -dport ${port}"
    [ -n "$comment" ] && rule_string+=" # ${comment}"
    
    echo "$rule_string"
}

main() {
    local HYPERVISOR_CONFIG_FILE="$1"
    log_info "Configuring global firewall settings..."

    local PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)
    local LXC_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_lxc_configs.json"
    local VM_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_vm_configs.json"
    local STACKS_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_stacks_config.json"

    # Read the desired firewall state from the declarative configuration file.
    local firewall_enabled=$(jq -r '.shared_volumes.firewall.enabled' "$HYPERVISOR_CONFIG_FILE")
    if [ "$firewall_enabled" != "true" ]; then
        log_info "Firewall is not enabled in the global config. Disabling..."
        pve-firewall stop
        return 0
    fi

    # Ensure the firewall configuration directory exists
    mkdir -p /etc/pve/firewall

    # Start the firewall service to ensure it's running before we apply rules.
    pve-firewall start

    # Read the desired firewall state from the declarative configuration file.
    local input_policy=$(jq -r '.shared_volumes.firewall.default_input_policy' "$HYPERVISOR_CONFIG_FILE")
    local output_policy=$(jq -r '.shared_volumes.firewall.default_output_policy' "$HYPERVISOR_CONFIG_FILE")

    # Create a temporary file for the new firewall configuration
    TMP_FW_CONFIG=$(mktemp)

    # Write the [OPTIONS] section to the temporary file
    log_info "Generating firewall configuration..."
    cat <<EOF > "$TMP_FW_CONFIG"
[OPTIONS]
enable: 1
policy_in: $input_policy
policy_out: $output_policy
EOF

    # Append the [RULES] section to the temporary file
    echo "" >> "$TMP_FW_CONFIG"
    echo "[RULES]" >> "$TMP_FW_CONFIG"

    # 1. Add global rules from hypervisor config
    log_info "Aggregating global firewall rules..."
    jq -c '.shared_volumes.firewall.global_firewall_rules[]?' "$HYPERVISOR_CONFIG_FILE" | while read -r rule; do
        generate_rule_string "$rule" >> "$TMP_FW_CONFIG"
    done

    # 2. Add rules from LXC configs
    log_info "Aggregating LXC firewall rules..."
    jq -c '.lxc_configs[].firewall.rules[]?' "$LXC_CONFIG_FILE" | while read -r rule; do
        generate_rule_string "$rule" >> "$TMP_FW_CONFIG"
    done

    # 3. Add rules from VM configs
    log_info "Aggregating VM firewall rules..."
    jq -c '.vms[].firewall.rules[]?' "$VM_CONFIG_FILE" | while read -r rule; do
        generate_rule_string "$rule" >> "$TMP_FW_CONFIG"
    done

    # 4. Add rules from Docker Compose files via VM assignments
    log_info "Aggregating Docker stack firewall rules..."
    jq -c '.vms[] | select(.docker_stacks)?' "$VM_CONFIG_FILE" | while read -r vm; do
        local vm_ip=$(echo "$vm" | jq -r '.network_config.ip' | cut -d'/' -f1)
        echo "$vm" | jq -c '.docker_stacks[]?' | while read -r stack_ref; do
            local stack_name=$(echo "$stack_ref" | jq -r '.name')
            local compose_path=$(jq -r ".docker_stacks.\"$stack_name\".compose_file_path" "$STACKS_CONFIG_FILE")
            
            if [ -f "${PHOENIX_BASE_DIR}/${compose_path}" ]; then
                # Use yq to parse docker-compose.yml for ports, with jq-compatible syntax
                cat "${PHOENIX_BASE_DIR}/${compose_path}" | yq -r '.services | to_entries[] | .value.ports[]?' | while read -r port_mapping; do
                    # Format is either "HOST:CONTAINER" or just "CONTAINER"
                    local host_port=$(echo "$port_mapping" | cut -d':' -f1)
                    local rule=$(jq -n \
                        --arg dest "$vm_ip" \
                        --arg port "$host_port" \
                        '{type: "in", action: "ACCEPT", proto: "tcp", source: "10.0.0.12", dest: $dest, port: $port, comment: "Allow Traefik to access Docker stack '\'$stack_name\''"}')
                    generate_rule_string "$rule" >> "$TMP_FW_CONFIG"
                done
            else
                log_warn "Compose file not found for stack '$stack_name': ${PHOENIX_BASE_DIR}/${compose_path}"
            fi
        done
    done

    # Replace the existing firewall configuration with the new one
    log_info "Applying new firewall configuration from temporary file..."
    cat "$TMP_FW_CONFIG" > /etc/pve/firewall/cluster.fw
    rm "$TMP_FW_CONFIG"

    # Restart the firewall to apply all changes at once
    log_info "Restarting Proxmox firewall to apply all changes..."
    pve-firewall restart

    log_info "Global firewall settings configured successfully."
}

main "$@"