#!/bin/bash
#
# File: generate_traefik_config.sh
# Description: This script dynamically generates the Traefik dynamic configuration file
#              by reading the LXC and VM configuration files. It discovers all services
#              that need to be exposed via Traefik and creates the necessary routers
#              and services.
#
# Version: 3.0.0 (Simplified)
# Author: Roo
# --- SCRIPT INITIALIZATION ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/.." &> /dev/null && pwd)
source "$SCRIPT_DIR/phoenix_hypervisor_common_utils.sh"
# --- CONFIGURATION ---
LXC_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_lxc_configs.json"
VM_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_vm_configs.json"
HYPERVISOR_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_hypervisor_config.json"
OUTPUT_FILE="${PHOENIX_BASE_DIR}/etc/traefik/dynamic_conf.yml"
INTERNAL_DOMAIN_NAME="internal.thinkheads.ai"
# --- MAIN LOGIC ---
main() {
    log_info "--- Starting Traefik Dynamic Configuration Generation (Simplified) ---"
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
                    "url": "https://\($vm_config.network_config.ip | split("/")[0]):\($service_def.port)",
                    "transport": ($service_def.name + "-transport"),
                    "serverName": "\($service_def.name).\($internal_domain)",
                    "resolver": "internal-resolver"
                }
            ),
            # Process LXCs
            ($lxcs[0].lxc_configs | values[]? | select(.traefik_service? and .traefik_service != null) |
                . as $lxc_config |
                .traefik_service as $service_def |
                {
                    "name": $service_def.name,
                    "rule": "Host(`\($service_def.name).\($internal_domain)`)",
                    "url": "http://\($lxc_config.network_config.ip | split("/")[0]):\($service_def.port)",
                    "resolver": "internal-resolver"
                }
            ),
            {
                "name": "traefik-internal",
                "rule": "Host(`traefik.\($internal_domain)`)",
                "url": "http://127.0.0.1:8080",
                "is_dummy": true,
                "resolver": "internal-resolver"
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
            (if .is_dummy then "      service: \"noop@internal\"" else "      service: \"\(.name)-service\"" end) + "\n" +
            "      entryPoints:\n" +
            "        - websecure\n" +
            "      tls:\n" +
            "        certResolver: \(.resolver)"
        '
        echo ""
        echo "  services:"
        echo "$traefik_services_json" | jq -r '
            .[] | select(.is_dummy | not) |
            "    \(.name)-service:\n" +
            "      loadBalancer:\n" +
            "        servers:\n" +
            "          - url: \"\(.url)\"\n" +
            (if .transport then "        serversTransport: \"\(.transport)\"\n" else "" end) +
            "        passHostHeader: true"
        '
        echo ""
        echo "  serversTransports:"
        echo "$traefik_services_json" | jq -r '
            .[] | select(.transport) |
            "    \(.transport):\n" +
            "      serverName: \"\(.serverName)\"\n" +
            "      rootCAs:\n" +
            "        - \"/etc/step-ca/ssl/phoenix_ca.crt\""
        '
    } > "$OUTPUT_FILE"
    log_success "Traefik dynamic configuration generated successfully at ${OUTPUT_FILE}"
    
    # --- Add a final check to ensure the file is not empty ---
    if [ ! -s "$OUTPUT_FILE" ] || [ $(grep -cv '^#' "$OUTPUT_FILE") -le 1 ]; then
        log_warn "Generated Traefik config is empty or contains no services. Writing a placeholder to prevent Traefik from crashing."
        echo "http:" > "$OUTPUT_FILE"
    fi
}
main