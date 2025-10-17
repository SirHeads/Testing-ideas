#!/bin/bash
#
# File: hypervisor_feature_setup_dns_server.sh
# Description: This script sets up a dnsmasq server on the Proxmox host
#              to provide split-horizon DNS for the Phoenix Hypervisor environment.
#
# Version: 1.0.0
# Author: Roo

set -e

# --- SCRIPT INITIALIZATION ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# Source common utilities
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# =====================================================================================
# Function: setup_dns_server
# Description: Installs and configures dnsmasq based on the declarative configuration.
# =====================================================================================
setup_dns_server() {
    log_info "Starting dnsmasq server setup..."

    local DNS_CONFIG=$(get_global_config_value '.dns_server')
    if [ "$(echo "$DNS_CONFIG" | jq -r '.enabled')" != "true" ]; then
        log_info "DNS server setup is disabled in the configuration. Skipping."
        return
    fi

    log_info "Installing dnsmasq..."
    apt-get update
    apt-get install -y dnsmasq

    log_info "Configuring dnsmasq..."
    local DNSMASQ_CONF="/etc/dnsmasq.conf"
    local DNSMASQ_HOSTS_DIR="/etc/dnsmasq.d"

    # Create a backup of the original dnsmasq.conf
    [ -f "$DNSMASQ_CONF" ] && mv "$DNSMASQ_CONF" "${DNSMASQ_CONF}.bak"

    # Create a new dnsmasq.conf
    cat > "$DNSMASQ_CONF" <<EOF
# General dnsmasq settings
port=53
domain-needed
bogus-priv
strict-order

# Point to our custom hosts directory
conf-dir=${DNSMASQ_HOSTS_DIR},*.conf
EOF

    # Add upstream DNS servers
    echo "$DNS_CONFIG" | jq -r '.upstream_servers[]' | while read -r server; do
        echo "server=${server}" >> "$DNSMASQ_CONF"
    done

    # Create the hosts directory
    mkdir -p "$DNSMASQ_HOSTS_DIR"
    rm -f ${DNSMASQ_HOSTS_DIR}/*.conf

    # Generate dnsmasq configuration from JSON
    echo "$DNS_CONFIG" | jq -c '.authoritative_zones[]' | while read -r zone; do
        local ZONE_NAME=$(echo "$zone" | jq -r '.zone_name')
        local CONF_FILE="${DNSMASQ_HOSTS_DIR}/${ZONE_NAME}.conf"
        log_info "Generating configuration for zone: ${ZONE_NAME}"

        echo "# Zone file for ${ZONE_NAME}" > "$CONF_FILE"
        echo "$zone" | jq -c '.records[]' | while read -r record; do
            local HOSTNAME=$(echo "$record" | jq -r '.hostname')
            local IP_INTERNAL=$(echo "$record" | jq -r '.ip_internal // ""')
            local IP_EXTERNAL=$(echo "$record" | jq -r '.ip_external // ""')
            local FQDN="${HOSTNAME}.${ZONE_NAME}"

            if [ -n "$IP_INTERNAL" ]; then
                echo "address=/${FQDN}/${IP_INTERNAL}" >> "$CONF_FILE"
            fi
            if [ -n "$IP_EXTERNAL" ]; then
                echo "address=/${FQDN}/${IP_EXTERNAL}" >> "$CONF_FILE"
            fi
        done
    done

    log_info "Restarting dnsmasq service..."
    systemctl restart dnsmasq
    systemctl enable dnsmasq

    log_info "Switching /etc/resolv.conf to use localhost for DNS..."
    echo "nameserver 127.0.0.1" > /etc/resolv.conf || log_fatal "Failed to overwrite /etc/resolv.conf."

    log_success "dnsmasq server setup completed successfully."
}

# --- Main execution ---
setup_dns_server