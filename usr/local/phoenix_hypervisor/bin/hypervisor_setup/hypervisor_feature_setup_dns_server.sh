#!/bin/bash
#
# File: hypervisor_feature_setup_dns_server.sh
# Description: This script sets up a dnsmasq server on the Proxmox host
#              to provide a unified, internal-only DNS view for the Phoenix Hypervisor environment.
#
# Version: 12.0.0
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
    log_info "Starting unified dnsmasq server setup..."
    local LXC_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_lxc_configs.json"
    local VM_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_vm_configs.json"
    
    local DNS_CONFIG=$(get_global_config_value '.dns_server')
    if [ "$(echo "$DNS_CONFIG" | jq -r '.enabled')" != "true" ]; then
        log_info "DNS server setup is disabled in the configuration. Skipping."
        return
    fi

    # --- Pre-flight Check for Port 53 ---
    log_info "Checking if port 53 is in use..."
    if lsof -i :53 &> /dev/null; then
        log_warn "Port 53 is currently in use. Identifying the process..."
        local blocking_service=""
        
        if systemctl is-active systemd-resolved &> /dev/null; then
            blocking_service="systemd-resolved"
        elif systemctl is-active dnsmasq &> /dev/null; then
            blocking_service="dnsmasq"
        fi

        if [ "$blocking_service" == "systemd-resolved" ]; then
            log_warn "Process 'systemd-resolved' detected on port 53. Stopping and disabling..."
            systemctl stop systemd-resolved
            systemctl disable systemd-resolved
            # Ensure the stub file is unlinked
            rm -f /etc/resolv.conf
            # Recreate a basic resolv.conf to allow package installation to work
            echo "nameserver 1.1.1.1" > /etc/resolv.conf
            log_success "systemd-resolved stopped and disabled."
        elif [ "$blocking_service" == "dnsmasq" ]; then
            log_warn "Process 'dnsmasq' is already running on port 53. Stopping it to reconfigure..."
            systemctl stop dnsmasq
            log_success "Existing dnsmasq service stopped."
        else
            # Fallback: Identify process name via lsof if systemctl check fails
            local blocking_process=$(lsof -i :53 -t | head -n 1 | xargs ps -p -o comm=)
            log_error "Port 53 is occupied by unknown process '$blocking_process'. Please stop it manually."
            exit 1
        fi
    else
        log_info "Port 53 is free."
    fi

    log_info "Installing dnsmasq..."
    apt-get update > /dev/null
    apt-get install -y dnsmasq > /dev/null
    log_info "Configuring dnsmasq for a single, internal-only view..."
    local DNSMASQ_CONF="/etc/dnsmasq.conf"
    local DNSMASQ_CONFIG_DIR="/etc/dnsmasq.d"
    # Create a backup of the original dnsmasq.conf
    [ -f "$DNSMASQ_CONF" ] && mv "$DNSMASQ_CONF" "${DNSMASQ_CONF}.bak.$(date +%s)"
    # Create a new dnsmasq.conf
    cat > "$DNSMASQ_CONF" <<EOF
# General dnsmasq settings
port=53
domain-needed
bogus-priv
strict-order
# Never forward plain names (without a dot or domain part)
domain-needed
# Never forward addresses in the non-routed address spaces.
bogus-priv
# Prevent DNS-rebind attacks
stop-dns-rebind
# Do not read /etc/resolv.conf for upstream servers
no-resolv
# Do not forward queries for the internal domain
local=/internal.thinkheads.ai/
# Listen on the host's primary IP address
listen-address=127.0.0.1,$(get_global_config_value '.network.interfaces.address' | cut -d'/' -f1)
# Include configuration files from /etc/dnsmasq.d
conf-dir=${DNSMASQ_CONFIG_DIR},*.conf
EOF
    # Add upstream DNS servers
    echo "$DNS_CONFIG" | jq -r '.upstream_servers[]' | while read -r server; do
        echo "server=${server}" >> "$DNSMASQ_CONF"
    done
    # Create the config directory and clean up any old files
    mkdir -p "$DNSMASQ_CONFIG_DIR"
    rm -f ${DNSMASQ_CONFIG_DIR}/*
    # --- BEGIN UNIFIED AGGREGATION LOGIC ---
    log_info "Aggregating all DNS records for internal view..."
    # Create a single combined JSON object of all records
    # --- New Stack Discovery Logic ---
    local STACKS_DIR="${PHOENIX_BASE_DIR}/stacks"
    local discovered_stacks_json="[]"
    if [ -d "$STACKS_DIR" ]; then
        for stack_dir in "$STACKS_DIR"/*/; do
            if [ -d "$stack_dir" ]; then
                local manifest_file="${stack_dir}phoenix.json"
                if [ -f "$manifest_file" ]; then
                    local manifest_content=$(jq -c . "$manifest_file")
                    discovered_stacks_json=$(echo "$discovered_stacks_json" | jq --argjson content "$manifest_content" '. + [$content]')
                fi
            fi
        done
    fi

    local ALL_RECORDS_JSON=$(jq -n \
        --argjson stacks "$discovered_stacks_json" \
        --argjson lxc_config "$(cat "$LXC_CONFIG_FILE")" \
        --argjson vm_config "$(cat "$VM_CONFIG_FILE")" \
        '
        # Get gateway and traefik IPs
        ($lxc_config.lxc_configs | to_entries[] | select(.value.name == "Nginx-Phoenix") | .value.network_config.ip | split("/")[0]) as $gateway_ip |
        ($lxc_config.lxc_configs | to_entries[] | select(.value.name == "Traefik-Internal") | .value.network_config.ip | split("/")[0]) as $traefik_ip |
        [
            # --- Public Gateway Services (All point to Nginx) ---
            # These are the hostnames that are exposed to the outside world (even if "outside" is just the Proxmox host)
            ($stacks[] | .environments.production.services | values[] | .traefik_labels[]? | select(startswith("traefik.http.routers.")) | select(contains(".rule=Host(`")) | capture("Host\\(`(?<hostname>[^`]+)`\\)") | { "hostname": .hostname, "ip": $traefik_ip }),
            ($lxc_config.lxc_configs | values[] | select(.traefik_service.name?) | { "hostname": "\(.traefik_service.name).internal.thinkheads.ai", "ip": $traefik_ip }),
            ($vm_config.vms[] | select(.traefik_service.name?) | { "hostname": "\(.traefik_service.name).internal.thinkheads.ai", "ip": $traefik_ip }),
            { "hostname": "portainer.internal.thinkheads.ai", "ip": $traefik_ip },
            { "hostname": "traefik.internal.thinkheads.ai", "ip": $traefik_ip },

            # --- Internal Services ---
            # These are for service-to-service communication. Most go through Traefik.
            # Some critical infrastructure needs to be resolved directly.
            ($lxc_config.lxc_configs | values[] | select(.name and .network_config.ip and .network_config.ip != "dhcp") | {
                "hostname": "\(.name | ascii_downcase).internal.thinkheads.ai",
                "ip": (if .name == "Step-CA" or .name == "Traefik-Internal" then (.network_config.ip | split("/")[0]) else $traefik_ip end)
            }),
            ($vm_config.vms[] | select(.name and .network_config.ip) | {
                "hostname": "\(.name | ascii_downcase).internal.thinkheads.ai",
                "ip": $traefik_ip
            }),
            ($vm_config.vms[] | select(.portainer_agent_hostname? and .portainer_agent_hostname != "") | {
                "hostname": .portainer_agent_hostname,
                "ip": $traefik_ip
            })

        ] | unique_by(.hostname)
        '
    )
    # --- Write Unified Internal DNS Records ---
    local INTERNAL_DNS_FILE="${DNSMASQ_CONFIG_DIR}/00-phoenix-internal.conf"
    log_info "Writing all DNS records to ${INTERNAL_DNS_FILE}..."
    echo "# Phoenix Hypervisor Internal DNS Records" > "$INTERNAL_DNS_FILE"
    echo "$ALL_RECORDS_JSON" | jq -r '.[] | "address=/\(.hostname)/\(.ip)"' >> "$INTERNAL_DNS_FILE"
    # --- BEGIN VALIDATION ---
    if [ ! -s "$INTERNAL_DNS_FILE" ]; then
        log_warn "Generated DNS config file is empty. Skipping dnsmasq restart to prevent service disruption."
    else
        log_info "Restarting dnsmasq service..."
        systemctl restart dnsmasq
    fi
    # --- END VALIDATION ---
    systemctl enable dnsmasq
    # --- Configure Host DNS Resolution ---
    log_info "Configuring host to use the local dnsmasq server..."
    local resolv_conf="/etc/resolv.conf"
    local resolv_conf_backup="/etc/resolv.conf.phoenix.bak"
    if [ ! -f "$resolv_conf_backup" ]; then
        log_info "Backing up original /etc/resolv.conf to ${resolv_conf_backup}..."
        cp "$resolv_conf" "$resolv_conf_backup"
    fi
    log_info "Generating new /etc/resolv.conf..."
    echo "# Generated by Phoenix Hypervisor - $(date)" > "$resolv_conf"
    local HOST_IP=$(get_global_config_value '.network.interfaces.address' | cut -d'/' -f1)
    local INTERNAL_DOMAIN_NAME=$(get_global_config_value '.domain_name' | sed 's/\(.*\)\.\(.*\)/\1.\2/')
    echo "search ${INTERNAL_DOMAIN_NAME}" >> "$resolv_conf"
    echo "nameserver ${HOST_IP}" >> "$resolv_conf"
    
    echo "$DNS_CONFIG" | jq -r '.upstream_servers[]' | while read -r server; do
        echo "nameserver ${server}" >> "$resolv_conf"
    done
    log_success "Host DNS resolution configured successfully."
    log_success "dnsmasq server setup completed successfully."
}
# --- Main execution ---
setup_dns_server