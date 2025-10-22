#!/bin/bash
#
# File: generate_nginx_gateway_config.sh
# Description: This script dynamically generates the NGINX gateway configuration,
#              creating a routing map based on the declared services in the
#              Phoenix Hypervisor configuration files.
#
# Version: 1.0.0
# Author: Roo

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/.." &> /dev/null && pwd)

# --- Source common utilities ---
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- Configuration file paths ---
VM_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_vm_configs.json"
LXC_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_lxc_configs.json"
GATEWAY_CONFIG_TEMPLATE="${PHOENIX_BASE_DIR}/etc/nginx/sites-available/gateway.template"
GATEWAY_CONFIG_OUTPUT="${PHOENIX_BASE_DIR}/etc/nginx/sites-available/gateway"

# =====================================================================================
# Function: generate_map_block
# Description: Generates the NGINX map block by iterating through all declared
#              VMs and LXCs that have a traefik_service definition.
# =====================================================================================
generate_map_block() {
    log_info "Generating NGINX gateway map block..."
    
    local map_block="map \$host \$upstream_service {\n"
    map_block+="    default https://traefik.internal.thinkheads.ai:443;\n"

    # Process VMs
    local vm_services=$(jq -c '(.vms // [])[] | select(.traefik_service)' "$VM_CONFIG_FILE")
    echo "$vm_services" | jq -c '.' | while read -r service_config; do
        local service_name=$(echo "$service_config" | jq -r '.traefik_service.name')
        local service_ip=$(echo "$service_config" | jq -r '.network_config.ip' | cut -d'/' -f1)
        local service_port=$(echo "$service_config" | jq -r '.traefik_service.port')
        local domain_name=$(get_global_config_value '.domain_name')
        local fqdn="${service_name}.${domain_name}"
        
        map_block+="    ${fqdn} https://${service_ip}:${service_port};\n"
    done

    # Process LXCs
    local lxc_services=$(jq -c '(.lxc_containers // [])[] | select(.traefik_service)' "$LXC_CONFIG_FILE")
    echo "$lxc_services" | jq -c '.' | while read -r service_config; do
        local service_name=$(echo "$service_config" | jq -r '.traefik_service.name')
        local service_ip=$(echo "$service_config" | jq -r '.network_config.ip' | cut -d'/' -f1)
        local service_port=$(echo "$service_config" | jq -r '.traefik_service.port')
        local domain_name=$(get_global_config_value '.domain_name')
        local fqdn="${service_name}.${domain_name}"
        
        map_block+="    ${fqdn} https://${service_ip}:${service_port};\n"
    done

    map_block+="}"
    echo -e "$map_block"
}

# --- Main execution ---
log_info "--- Starting NGINX Gateway Configuration Generation ---"

# Create a template file if it doesn't exist
if [ ! -f "$GATEWAY_CONFIG_TEMPLATE" ]; then
    log_info "Gateway template not found. Creating from existing gateway file."
    mv "$GATEWAY_CONFIG_OUTPUT" "$GATEWAY_CONFIG_TEMPLATE"
    sed -i 's/map \$host \$upstream_service {[^}]*}/##MAP_BLOCK##/' "$GATEWAY_CONFIG_TEMPLATE"
fi

MAP_BLOCK=$(generate_map_block)

log_info "Generated Map Block:\n${MAP_BLOCK}"

# Replace the placeholder in the template with the generated map block
awk -v map_block="$MAP_BLOCK" '{
    if ($0 == "##MAP_BLOCK##") {
        print map_block
    } else {
        print $0
    }
}' "$GATEWAY_CONFIG_TEMPLATE" > "$GATEWAY_CONFIG_OUTPUT"

log_success "NGINX gateway configuration generated successfully at ${GATEWAY_CONFIG_OUTPUT}"