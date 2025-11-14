#!/bin/bash
#
# File: hypervisor_feature_setup_firewall.sh
# Description: This script configures the Proxmox VE firewall in a hierarchical and declarative manner.
#              It reads the desired state from the project's JSON configuration files and generates
#              separate, clean firewall configurations for the cluster, the host, and each guest (VM/LXC).
#
# Version: 2.0.0
# Author: Roo

set -e

# --- SCRIPT INITIALIZATION ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# =====================================================================================
# Function: generate_cluster_firewall_config
# Description: Generates the top-level cluster firewall configuration.
# =====================================================================================
generate_cluster_firewall_config() {
    log_info "Generating cluster-level firewall configuration..."
    local input_policy=$(get_global_config_value '.shared_volumes.firewall.default_input_policy')
    local output_policy=$(get_global_config_value '.shared_volumes.firewall.default_output_policy')
    local cluster_fw_file="/etc/pve/firewall/cluster.fw"

    cat <<EOF > "$cluster_fw_file"
[OPTIONS]
enable: 1
policy_in: $input_policy
policy_out: $output_policy

[RULES]
IN ACCEPT -i lo
EOF

    get_global_config_value '.shared_volumes.firewall.global_firewall_rules[]?' | jq -c . | while read -r rule; do
        generate_rule_string "$rule" >> "$cluster_fw_file"
    done
    log_success "Cluster firewall configuration generated at $cluster_fw_file"
}

# =====================================================================================
# Function: generate_guest_firewall_config
# Description: Generates the guest-level firewall configuration for a specific VM or LXC.
# =====================================================================================
generate_guest_firewall_config() {
    local guest_type="$1" # "lxc" or "vm"
    local guest_id="$2"
    local config_file="$3"
    local guest_fw_file="/etc/pve/firewall/${guest_id}.fw"

    log_info "Generating firewall configuration for ${guest_type^^} ${guest_id}..."

    local firewall_config
    if [ "$guest_type" == "lxc" ]; then
        firewall_config=$(jq -r --arg ctid "$guest_id" '.lxc_configs[$ctid].firewall' "$config_file")
    else
        firewall_config=$(jq -r --argjson vmid "$guest_id" '.vms[] | select(.vmid == $vmid) | .firewall' "$config_file")
    fi

    if [ -z "$firewall_config" ] || [ "$(echo "$firewall_config" | jq -r '.enabled')" != "true" ]; then
        log_info "Firewall is not enabled for ${guest_type^^} ${guest_id}. Skipping."
        # Ensure the file doesn't exist or is empty if disabled
        > "$guest_fw_file"
        return
    fi

    cat <<EOF > "$guest_fw_file"
[OPTIONS]
enable: 1

[RULES]
EOF

    echo "$firewall_config" | jq -c '.rules[]?' | while read -r rule; do
        generate_rule_string "$rule" >> "$guest_fw_file"
    done
    log_success "Guest firewall configuration generated at $guest_fw_file"
}

# =====================================================================================
# Function: main
# Description: Main entry point for the script.
# =====================================================================================
main() {
    log_info "Starting declarative firewall configuration..."

    # 1. Generate the cluster-level configuration
    generate_cluster_firewall_config

    # 2. Generate guest-level configurations for all LXCs
    jq -r '.lxc_configs | keys[]' "$LXC_CONFIG_FILE" | while read -r ctid; do
        generate_guest_firewall_config "lxc" "$ctid" "$LXC_CONFIG_FILE"
    done

    # 3. Generate guest-level configurations for all VMs
    jq -r '.vms[].vmid' "$VM_CONFIG_FILE" | while read -r vmid; do
        generate_guest_firewall_config "vm" "$vmid" "$VM_CONFIG_FILE"
    done

    # 4. Reload the firewall to apply all changes
    log_info "Reloading Proxmox firewall to apply all generated configurations..."
    pve-firewall restart

    log_success "Declarative firewall configuration completed successfully."
}

main "$@"