#!/bin/bash
#
# File: hypervisor_feature_setup_dns_server.sh
# Description: This feature script installs and configures dnsmasq on the Proxmox host
#              to provide centralized internal DNS resolution for the Phoenix Hypervisor environment.
#

# --- SCRIPT INITIALIZATION ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- MAIN LOGIC ---
main() {
    log_info "Starting dnsmasq setup for the Proxmox host."

    # --- Install dnsmasq ---
    log_info "Installing dnsmasq..."
    if ! apt-get update -y || ! apt-get install -y dnsmasq; then
        log_fatal "Failed to install dnsmasq on the hypervisor."
    fi

    # --- Configure dnsmasq ---
    log_info "Configuring dnsmasq..."
    local dnsmasq_config_file="/etc/dnsmasq.d/phoenix.conf"
    
    # Get the IP of the Nginx gateway and Step-CA from the LXC config
    local step_ca_ip=$(jq -r '.lxc_configs."103".network_config.ip' "${PHOENIX_BASE_DIR}/etc/phoenix_lxc_configs.json" | cut -d'/' -f1)

    if [ -z "$step_ca_ip" ]; then
        log_fatal "Could not read IP address for Step-CA from lxc_configs.json."
    fi

    log_info "Creating dnsmasq configuration at ${dnsmasq_config_file}..."
    {
        echo "# Phoenix Hypervisor Internal DNS Configuration"
        echo "# This file is managed automatically. Do not edit manually."
        echo ""
        echo "# Listen on localhost and the primary bridge interface"
        echo "listen-address=127.0.0.1,10.0.0.13"
        echo ""
        echo "# --- Explicit DNS Records ---"
        
        # Add records from VM configs
        jq -r '.vms[] | .dns_records[]? | "address=/\(.hostname)/\(.ip)"' "${PHOENIX_BASE_DIR}/etc/phoenix_vm_configs.json"
        
        # Add records from LXC configs
        jq -r '.lxc_configs | to_entries[] | .value.dns_records[]? | "address=/\(.hostname)/\(.ip)"' "${PHOENIX_BASE_DIR}/etc/phoenix_lxc_configs.json"

        echo ""
        echo "# --- Service-Specific Records ---"
        echo "# Route Step-CA traffic directly"
        echo "address=/ca.internal.thinkheads.ai/${step_ca_ip}"
        echo ""
        echo "# --- Upstream DNS ---"
        echo "# Use Google's public DNS for external queries"
        echo "server=8.8.8.8"
        echo "server=8.8.4.4"
    } > "${dnsmasq_config_file}"

    # --- Restart dnsmasq ---
    log_info "Restarting dnsmasq service..."
    if ! systemctl restart dnsmasq; then
        log_fatal "Failed to restart dnsmasq service."
    fi
    
    if ! systemctl enable dnsmasq; then
        log_fatal "Failed to enable dnsmasq service."
    fi

    log_info "dnsmasq setup on the Proxmox host is complete."
}

# --- SCRIPT EXECUTION ---
main "$@"