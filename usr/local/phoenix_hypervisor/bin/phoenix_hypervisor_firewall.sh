#!/bin/bash
#
# File: phoenix_hypervisor_firewall.sh
# Description: Manages firewall rules for LXC containers by directly editing the config file.

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
# --- Source common utilities ---
# Get the absolute path of the script
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
# Get the directory containing the script
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
# Source the common utilities
source "${SCRIPT_DIR}/phoenix_hypervisor_common_utils.sh"

# --- Main Logic ---
main() {
    local ctid="$1"
    log_info "Applying firewall rules for CTID: $ctid by editing config file."

    local firewall_enabled=$(jq_get_value "$ctid" ".firewall.enabled")
    local conf_file="/etc/pve/lxc/${ctid}.conf"

    if [ ! -f "$conf_file" ]; then
        log_fatal "Container configuration file not found at $conf_file."
    fi

    # --- Clear Existing Rules ---
    log_info "Deleting existing firewall rules for CTID $ctid from config..."
    sed -i '/^net\[.\]:/d' "$conf_file"

    # --- Build the full net0 configuration string ---
    local net0_name=$(jq_get_value "$ctid" ".network_config.name")
    local net0_bridge=$(jq_get_value "$ctid" ".network_config.bridge")
    local net0_ip=$(jq_get_value "$ctid" ".network_config.ip")
    local net0_gw=$(jq_get_value "$ctid" ".network_config.gw")
    local mac_address=$(jq_get_value "$ctid" ".mac_address")
    local net0_string="name=${net0_name},bridge=${net0_bridge},ip=${net0_ip},gw=${net0_gw},hwaddr=${mac_address}"

    if [ "$firewall_enabled" != "true" ]; then
        log_info "Firewall is not enabled in the JSON config for CTID $ctid. Ensuring it is disabled on net0 interface via pct."
        pct set "$ctid" --net0 "${net0_string},firewall=0"
        return 0
    fi

    # --- Enable Firewall ---
    log_info "Ensuring firewall is enabled for CTID $ctid on net0 interface via pct..."
    pct set "$ctid" --net0 "${net0_string},firewall=1"

    # --- Add New Rules ---
    local rules=$(jq_get_value "$ctid" ".firewall.rules")
    if [ -z "$rules" ]; then
        log_info "No firewall rules to apply for CTID $ctid."
        return 0
    fi

    local rule_json
    local i=0
    echo "$rules" | while read -r rule_json; do
        local type=$(echo "$rule_json" | jq -r '.type')
        local action=$(echo "$rule_json" | jq -r '.action')
        local source=$(echo "$rule_json" | jq -r '.source // ""')
        local dest=$(echo "$rule_json" | jq -r '.dest // ""')
        local proto=$(echo "$rule_json" | jq -r '.proto // ""')
        local port=$(echo "$rule_json" | jq -r '.port // ""')

        local rule_string="net[$i]: $type $action"
        [ -n "$source" ] && rule_string+=" -source $source"
        [ -n "$dest" ] && rule_string+=" -dest $dest"
        [ -n "$proto" ] && rule_string+=" -proto $proto"
        [ -n "$port" ] && rule_string+=" -dport $port"

        log_info "Adding rule to $conf_file: $rule_string"
        echo "$rule_string" >> "$conf_file"
        i=$((i+1))
    done

    log_info "Firewall rules applied successfully for CTID $ctid."
}

main "$@"