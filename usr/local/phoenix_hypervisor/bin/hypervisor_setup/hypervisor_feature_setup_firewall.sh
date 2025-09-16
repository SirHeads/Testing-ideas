#!/bin/bash
#
# File: hypervisor_feature_setup_firewall.sh
# Description: Configures the Proxmox firewall at the datacenter level.

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# --- Main Logic ---
main() {
    log_info "Configuring global firewall settings..."

    local firewall_enabled=$(jq -r '.firewall.enabled' "$HYPERVISOR_CONFIG_FILE")
    if [ "$firewall_enabled" != "true" ]; then
        log_info "Firewall is not enabled in the global config. Disabling..."
        pve-firewall stop
        return 0
    fi

    log_info "Enabling Proxmox firewall..."
    pve-firewall start

    local input_policy=$(jq -r '.firewall.default_input_policy' "$HYPERVISOR_CONFIG_FILE")
    local output_policy=$(jq -r '.firewall.default_output_policy' "$HYPERVISOR_CONFIG_FILE")

    log_info "Setting default input policy to: $input_policy"
    pve-firewall set /cluster/firewall/options -policy_in "$input_policy"

    log_info "Setting default output policy to: $output_policy"
    pve-firewall set /cluster/firewall/options -policy_out "$output_policy"

    log_info "Global firewall settings configured successfully."
}

main "$@"