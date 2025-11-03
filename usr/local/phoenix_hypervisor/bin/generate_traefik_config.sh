#!/bin/bash
#
# File: generate_traefik_config.sh
# Description: This script dynamically generates the Traefik dynamic configuration file
#              for a pure HTTP service mesh. It discovers all services from the LXC
#              and VM configuration files and creates the necessary plain HTTP routers
#              and services.
#
# Version: 4.0.0 (HTTP-Only Service Mesh)
# Author: Roo

# --- SCRIPT INITIALIZATION ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/.." &> /dev/null && pwd)
source "$SCRIPT_DIR/phoenix_hypervisor_common_utils.sh"

# --- CONFIGURATION ---
LXC_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_lxc_configs.json"
VM_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_vm_configs.json"
OUTPUT_FILE="${PHOENIX_BASE_DIR}/etc/traefik/dynamic_conf.yml"
INTERNAL_DOMAIN_NAME="internal.thinkheads.ai"

# --- MAIN LOGIC ---
main() {
    log_info "--- Starting Traefik Dynamic Configuration Generation (v4 - HTTP-Only) ---"

    # --- AGGREGATE ALL GUESTS THAT NEED A TRAEFIK ROUTE ---
    local traefik_services_json=$(jq -n \
        --slurpfile vms "$VM_CONFIG_FILE" \
        --slurpfile lxcs "$LXC_CONFIG_FILE" \
        --arg internal_domain "$INTERNAL_DOMAIN_NAME" \
        '
        [
            # Process VMs
            ($vms[0].vms[]? | select(.traefik_service? and .traefik_service != null) |
                . as $vm_config |
                .traefik_service as $service_def |
                {
                    "name": $service_def.name,
                    "rule": "Host(`\($service_def.name).\($internal_domain)`)",
                    "url": "https://\($vm_config.network_config.ip | split("/")[0]):\($service_def.port)"
                }
            ),
            # Process LXCs
            ($lxcs[0].lxc_configs | values[]? | select(.traefik_service? and .traefik_service != null) |
                . as $lxc_config |
                .traefik_service as $service_def |
                {
                    "name": $service_def.name,
                    "rule": "Host(`\($service_def.name).\($internal_domain)`)",
                    "url": "http://\($lxc_config.network_config.ip | split("/")[0]):\($service_def.port)"
                }
            ),
            # Add the Traefik dashboard itself
            {
                "name": "traefik-dashboard",
                "rule": "Host(`traefik.\($internal_domain)`)",
                "url": "http://127.0.0.1:8080",
                "is_api": true
            }
        ]
        '
    )

    log_info "Aggregated Traefik services JSON: $(echo "$traefik_services_json" | jq -c)"

    # --- GENERATE YAML FROM JSON ---
    {
        echo "http:"
        echo "  routers:"
        echo "$traefik_services_json" | jq -r '
            .[] |
            "    \(.name)-router:\n" +
            "      rule: \"\(.rule)\"\n" +
            "      service: \"\(if .is_api then "api@internal" else "\(.name)-service" end)\"\n" +
            "      entryPoints:\n" +
            "        - web"
        '
        
        echo ""
        echo "  services:"
        echo "$traefik_services_json" | jq -r '
            .[] | select(.is_api | not) |
            "    \(.name)-service:\n" +
            "      loadBalancer:\n" +
            "        servers:\n" +
            "          - url: \"\(.url)\"\n" +
            "        passHostHeader: true" +
            (if (.url | startswith("https")) then "\n        serversTransport: \"internal-ca@file\"" else "" end)
        '
    } > "$OUTPUT_FILE"

    # --- APPEND SERVERS TRANSPORT FOR INTERNAL CA ---
    cat >> "$OUTPUT_FILE" <<EOF

  serversTransports:
    internal-ca:
      insecureSkipVerify: false
      rootCAs:
        - /etc/step-ca/ssl/phoenix_root_ca.crt
EOF

    log_success "Traefik dynamic configuration generated successfully at ${OUTPUT_FILE}"
    
    # --- Add a final check to ensure the file is not empty ---
    if [ ! -s "$OUTPUT_FILE" ] || [ $(grep -cv '^#' "$OUTPUT_FILE") -le 1 ]; then
        log_warn "Generated Traefik config is empty or contains no services. Writing a placeholder to prevent Traefik from crashing."
        echo "http:" > "$OUTPUT_FILE"
    fi
}

main