#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_dns_server.sh
# Description: This feature script installs and configures dnsmasq on an LXC container
#              to provide internal DNS resolution for the Phoenix Hypervisor environment.
#

# --- SCRIPT INITIALIZATION ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- MAIN LOGIC ---
main() {
    local CTID="$1"
    log_info "Starting dnsmasq setup for CTID: $CTID"

    # --- Disable systemd-resolved ---
    log_info "Disabling systemd-resolved..."
    pct_exec "$CTID" -- systemctl disable systemd-resolved
    pct_exec "$CTID" -- systemctl stop systemd-resolved

    # --- Install dnsmasq ---
    log_info "Installing dnsmasq..."
    pct_exec "$CTID" -- apt-get update
    pct_exec "$CTID" -- apt-get install -y dnsmasq

    # --- Configure dnsmasq ---
    log_info "Configuring dnsmasq..."
    local dnsmasq_config="
# Listen on the bridge interface and localhost
listen-address=127.0.0.1,$(jq_get_value "$CTID" ".network_config.ip" | cut -d'/' -f1)

# Add internal host records
address=/phoenix.local/10.0.0.153
address=/*.phoenix.local/10.0.0.153
address=/ca.internal.thinkheads.ai/10.0.0.10

# Use Google's public DNS for external queries
server=8.8.8.8
server=8.8.4.4
"
    # Use a temporary file to write the configuration
    local temp_conf
    temp_conf=$(mktemp)
    echo "$dnsmasq_config" > "$temp_conf"
    pct push "$CTID" "$temp_conf" "/etc/dnsmasq.conf"
    rm "$temp_conf"

    # --- Restart dnsmasq ---
    log_info "Restarting dnsmasq service..."
    pct_exec "$CTID" -- systemctl restart dnsmasq

    log_info "dnsmasq setup complete for CTID: $CTID"
}

# --- SCRIPT EXECUTION ---
main "$@"