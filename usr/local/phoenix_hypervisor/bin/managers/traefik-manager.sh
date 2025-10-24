#!/bin/bash
# File: traefik-manager.sh
# Description: This script manages the dynamic configuration for the Traefik service.

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# --- Source common utilities ---
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# =====================================================================================
# Function: generate_traefik_config
# Description: Generates the Traefik dynamic configuration file from container data.
# Arguments:
#   $1 - A JSON string of container data from the Portainer API.
# =====================================================================================
generate_traefik_config() {
    local container_data="$1"
    local output_file="${PHOENIX_BASE_DIR}/etc/traefik/dynamic_conf.yml"

    log_info "--- Starting Traefik Dynamic Configuration Generation ---"

    # Start with a clean YAML structure
    echo "http:" > "$output_file"
    echo "  routers:" >> "$output_file"

    # Process each container
    echo "$container_data" | jq -c '.[]' | while read -r container; do
        local labels=$(echo "$container" | jq -r '.Labels')
        if echo "$labels" | jq -e '."traefik.enable" == "true"' > /dev/null; then
            local router_name=$(echo "$labels" | jq -r 'keys[] | select(startswith("traefik.http.routers.")) | split(".")[2]' | head -n 1)
            local rule=$(echo "$labels" | jq -r --arg router_name "$router_name" '."traefik.http.routers.\($router_name).rule"')
            local service_name=$(echo "$labels" | jq -r --arg router_name "$router_name" '."traefik.http.routers.\($router_name).service"')
            local entrypoints=$(echo "$labels" | jq -r --arg router_name "$router_name" '."traefik.http.routers.\($router_name).entrypoints"')
            
            echo "    ${router_name}:" >> "$output_file"
            echo "      rule: \"${rule}\"" >> "$output_file"
            echo "      service: \"${service_name}\"" >> "$output_file"
            echo "      entryPoints:" >> "$output_file"
            echo "        - ${entrypoints}" >> "$output_file"
            echo "      tls:" >> "$output_file"
            echo "        certResolver: myresolver" >> "$output_file"
        fi
    done

    echo "  services:" >> "$output_file"

    # Process each container again for services
    echo "$container_data" | jq -c '.[]' | while read -r container; do
        local labels=$(echo "$container" | jq -r '.Labels')
        if echo "$labels" | jq -e '."traefik.enable" == "true"' > /dev/null; then
            local service_name=$(echo "$labels" | jq -r 'keys[] | select(startswith("traefik.http.services.")) | split(".")[2]' | head -n 1)
            local port=$(echo "$labels" | jq -r --arg service_name "$service_name" '."traefik.http.services.\($service_name).loadbalancer.server.port"')
            local container_ip=$(echo "$container" | jq -r '.NetworkSettings.Networks | values[0].IPAddress')
            
            echo "    ${service_name}:" >> "$output_file"
            echo "      loadBalancer:" >> "$output_file"
            echo "        servers:" >> "$output_file"
            echo "          - url: \"http://${container_ip}:${port}\"" >> "$output_file"
        fi
    done

    log_success "Traefik dynamic configuration generated successfully at ${output_file}"
}

# If the script is executed directly, call the main function
if [[ "${BASH_SOURCE}" == "${0}" ]]; then
    if [ -z "$1" ]; then
        log_fatal "Container data not provided."
    fi
    generate_traefik_config "$1"
fi