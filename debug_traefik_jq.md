#!/bin/bash
#
# File: debug_traefik_jq.sh
# Description: This script is for debugging the jq query from generate_traefik_config.sh
#

# --- SCRIPT INITIALIZATION ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/.." &> /dev/null && pwd)
source "usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh"

# --- CONFIGURATION ---
LXC_CONFIG_FILE="usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json"
VM_CONFIG_FILE="usr/local/phoenix_hypervisor/etc/phoenix_vm_configs.json"
HYPERVISOR_CONFIG_FILE="usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json"
INTERNAL_DOMAIN_NAME="internal.thinkheads.ai"

# --- DEBUGGING LOGIC ---
log_info "--- Debugging Traefik LXC Service Discovery ---"

# This query isolates the part of the main script that processes LXCs
jq -n \
    --slurpfile lxcs "$LXC_CONFIG_FILE" \
    --slurpfile hypervisor_config "$HYPERVISOR_CONFIG_FILE" \
    --arg internal_domain "$INTERNAL_DOMAIN_NAME" \
    '
    # Define a function to find the DNS hostname for a given IP
    def find_hostname($ip; $dns_records):
        ($dns_records[]? | select(.ip_internal == $ip) | .hostname) // null;

    # Extract DNS records for the internal zone
    def get_internal_dns_records:
        $hypervisor_config[0].dns_server.authoritative_zones[] | select(.zone_name == $internal_domain) | .records;

    (get_internal_dns_records | . as $dns_records |
    [
        ($lxcs[0].lxc_configs | values[]? | select(.ports? and (.ports | length > 0)) |
            . as $lxc_config |
            ($lxc_config.network_config.ip | split("/")[0]) as $ip |
            find_hostname($ip; $dns_records) as $hostname |
            select($hostname != null) | {
                "name": $hostname,
                "rule": "Host(`\($hostname).\($internal_domain)`)",
                "url": ("http://\($ip):\( $lxc_config.ports[0] | split(":")[1] )")
            }
        )
    ] | flatten | map(select(. != null)))
    '