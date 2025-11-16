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
# Function: ensure_bridge_firewall_enabled
# Description: Ensures that the Proxmox bridge firewall is enabled. This is the
#              best practice for security as it allows the per-guest firewall
#              rules to control traffic between guests on the same bridge.
# =====================================================================================
ensure_bridge_firewall_enabled() {
    log_info "Ensuring Proxmox bridge firewall is enabled for vmbr0..."
    local interfaces_file="/etc/network/interfaces"

    # Dynamically discover the primary bridge port.
    local bridge_port=$(brctl show vmbr0 | awk 'NR>1 {print $NF}' | head -n1)
    if [ -z "$bridge_port" ]; then
        log_fatal "Could not dynamically determine the bridge port for vmbr0. Cannot enable bridge firewall."
    fi
    log_info "Discovered primary bridge port for vmbr0: ${bridge_port}"

    # Create a backup of the original file, but only if one doesn't already exist
    if [ ! -f "${interfaces_file}.bak" ]; then
        cp "$interfaces_file" "${interfaces_file}.bak"
    fi

    # Use a marker to check if the block is already present
    local firewall_marker="# PHOENIX_BRIDGE_FIREWALL_ENABLED"
    if grep -q "$firewall_marker" "$interfaces_file"; then
        log_info "Bridge firewall configuration already present. No changes needed."
        return 0
    fi

    # Create a temporary file to perform operations, ensuring atomicity
    local temp_file
    temp_file=$(mktemp)
    cp "$interfaces_file" "$temp_file"

    # Remove any old, conflicting lines from the temporary file
    sed -i '/bridge-fw-nf-disable 1/d' "$temp_file"
    sed -i '/bridge-ports/d' "$temp_file"
    sed -i '/bridge-stp/d' "$temp_file"
    sed -i '/bridge-fd/d' "$temp_file"

    # Define the full, correct block to be inserted
    local bridge_config_block
    bridge_config_block=$(cat <<EOF
        bridge_ports ${bridge_port}
        bridge-stp off
        bridge-fd 0
        ${firewall_marker}
EOF
)

    # Use awk to find the 'iface vmbr0' line and insert the block after it, reading from the cleaned temp file
    awk -v block="$bridge_config_block" '
    /iface vmbr0 inet static/ {
        print;
        print block;
        next;
    }
    { print }
    ' "$temp_file" > "$interfaces_file"

    # Clean up the temporary file
    rm "$temp_file"

    log_info "Successfully updated network configuration to enable bridge firewall. Applying changes..."
    if ! ifreload -a; then
        log_error "Failed to reload network configuration. Restoring from backup."
        mv "${interfaces_file}.bak" "$interfaces_file"
        log_fatal "Network reload failed. The original configuration has been restored."
    fi
    
    log_success "Network configuration reloaded successfully with bridge firewall enabled."
}

# =====================================================================================
# Function: clear_existing_firewall_configs
# Description: Wipes all existing .fw files to ensure a clean slate.
# =====================================================================================
clear_existing_firewall_configs() {
    log_info "Clearing all existing firewall configuration files..."
    local firewall_dir="/etc/pve/firewall"
    
    # Use find to delete all .fw files. This is safe even if none exist.
    find "$firewall_dir" -type f -name "*.fw" -delete
    
    log_success "All .fw files have been removed."
}

# =====================================================================================
# Function: generate_cluster_firewall_config
# Description: Generates the top-level cluster firewall configuration.
# =====================================================================================
generate_cluster_firewall_config() {
    log_info "Generating cluster-level firewall configuration..."
    local input_policy=$(get_global_config_value '.firewall.default_input_policy')
    local output_policy=$(get_global_config_value '.firewall.default_output_policy')
    local cluster_fw_file="/etc/pve/firewall/cluster.fw"

    cat <<EOF > "$cluster_fw_file"
[OPTIONS]
enable: 1
policy_in: $input_policy
policy_out: $output_policy

[RULES]
IN ACCEPT -i lo
EOF

    get_global_config_value '.firewall.global_firewall_rules[]?' | jq -c . | while read -r rule; do
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

    # 1. Ensure the network interfaces and bridge firewall are correctly configured.
    ensure_bridge_firewall_enabled

    # 2. Wipe all existing .fw files to ensure a clean, idempotent run.
    clear_existing_firewall_configs

    # 3. Generate the cluster-level configuration.
    generate_cluster_firewall_config

    # 4. Generate guest-level configurations for all LXCs.
    jq -r '.lxc_configs | keys[]' "$LXC_CONFIG_FILE" | while read -r ctid; do
        generate_guest_firewall_config "lxc" "$ctid" "$LXC_CONFIG_FILE"
    done

    # 5. Generate guest-level configurations for all VMs.
    jq -r '.vms[].vmid' "$VM_CONFIG_FILE" | while read -r vmid; do
        generate_guest_firewall_config "vm" "$vmid" "$VM_CONFIG_FILE"
    done

    # 6. Create the host-level firewall configuration file.
    local nodename=$(hostname)
    local host_fw_file="/etc/pve/firewall/${nodename}.fw"
    log_info "Ensuring host-level firewall is enabled at ${host_fw_file}..."
    cat <<EOF > "$host_fw_file"
[OPTIONS]
enable: 1
EOF

    # 7. Reload the firewall to apply all changes.
    log_info "Reloading Proxmox firewall to apply all generated configurations..."
    pve-firewall restart

    log_success "Declarative firewall configuration completed successfully."
}

main "$@"