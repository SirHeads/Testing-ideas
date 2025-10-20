#!/bin/bash
#
# File: generate_traefik_config.sh
# Description: This script dynamically generates the Traefik dynamic configuration file
#              by reading the LXC and VM configuration files. It discovers all services
#              that need to be exposed via Traefik and creates the necessary routers
#              and services.
#
# Version: 2.0.0
# Author: Roo

# --- SCRIPT INITIALIZATION ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/.." &> /dev/null && pwd)
source "$SCRIPT_DIR/phoenix_hypervisor_common_utils.sh"

# --- CONFIGURATION ---
LXC_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_lxc_configs.json"
VM_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_vm_configs.json"
OUTPUT_FILE="${PHOENIX_BASE_DIR}/etc/traefik/dynamic_conf.yml"
DOMAIN_NAME=$(get_global_config_value '.domain_name')
INTERNAL_DOMAIN_NAME="internal.${DOMAIN_NAME}"

# --- MAIN LOGIC ---
main() {
    log_info "--- Starting Traefik Dynamic Configuration Generation ---"

    # --- AGGREGATE ALL GUESTS THAT NEED A TRAEFIK ROUTE ---
    local traefik_services_json=$(jq -n \
        --slurpfile vms "$VM_CONFIG_FILE" \
        --slurpfile lxcs "$LXC_CONFIG_FILE" \
        --arg internal_domain "$INTERNAL_DOMAIN_NAME" \
        --arg portainer_hostname "$(get_global_config_value '.portainer_api.portainer_hostname')" \
        --arg portainer_port "$(get_global_config_value '.network.portainer_server_port')" \
        '
        [
            # 1. Process Portainer VM
            ($vms[0].vms[]? | select(.portainer_role == "primary") | {
                "name": "portainer",
                "rule": ("Host(`" + $portainer_hostname + "`)"),
                "url": ("https://\(.network_config.ip | split("/")[0]):" + $portainer_port),
                "transport": "portainer-transport"
            }),
            # 2. Process LXCs with exposed ports
            ($lxcs[0].lxc_configs | values[]? | select(.ports? and (.ports | length > 0)) | {
                "name": .name,
                "rule": ("Host(`" + .name + "." + $internal_domain + "`)"),
                "url": ("http://\(.network_config.ip | split("/")[0]):\(.ports[0] | split(":")[1])")
            })
        ] | flatten | map(select(. != null))
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
            "      service: \"\(.name)-service\"\n" +
            "      entryPoints:\n" +
            "        - websecure\n" +
            "      tls:\n" +
            "        certResolver: myresolver"
        '

        echo ""
        echo "  services:"
        echo "$traefik_services_json" | jq -r '
            .[] |
            "    \(.name)-service:\n" +
            "      loadBalancer:\n" +
            "        servers:\n" +
            "          - url: \"\(.url)\"\n" +
            (if .transport then "        serversTransport: \"\(.transport)\"\n" else "" end) +
            "        passHostHeader: true"
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