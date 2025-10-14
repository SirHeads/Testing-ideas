#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_nat_gateway.sh
# Description: This feature script configures the LXC container as a NAT gateway,
#              enabling other containers on the same bridge to access the internet.
#

# --- SCRIPT INITIALIZATION ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- MAIN LOGIC ---
main() {
    local CTID="$1"
    log_info "Configuring NAT gateway for CTID: $CTID"

    # --- Enable IP Forwarding and NAT ---
    log_info "Enabling IP forwarding and configuring NAT..."
    pct_exec "$CTID" -- sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    pct_exec "$CTID" -- sysctl -p
    pct_exec "$CTID" -- apt-get update
    pct_exec "$CTID" -- apt-get install -y iptables-persistent
    pct_exec "$CTID" -- iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
    pct_exec "$CTID" -- bash -c "iptables-save > /etc/iptables/rules.v4"

    log_info "NAT gateway configuration complete for CTID: $CTID"
}

# --- SCRIPT EXECUTION ---
main "$@"