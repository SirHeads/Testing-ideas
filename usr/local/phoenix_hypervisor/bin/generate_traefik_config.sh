#!/bin/bash
#
# File: generate_traefik_config.sh
# Description: This script generates a complete Traefik dynamic configuration file
#              by reading from the central LXC and VM JSON configuration files.
#
# Version: 1.0.0
# Author: Roo

set -e

# --- SCRIPT INITIALIZATION ---
source "/tmp/phoenix_run/phoenix_hypervisor_common_utils.sh"

# --- Configuration Paths ---
LXC_CONFIG_FILE="/tmp/phoenix_run/phoenix_lxc_configs.json"
VM_CONFIG_FILE="/tmp/phoenix_run/phoenix_vm_configs.json"
HYPERVISOR_CONFIG_FILE="/tmp/phoenix_run/phoenix_hypervisor_config.json"
OUTPUT_FILE="/tmp/dynamic_conf.yml"

# --- Main Logic ---
main() {
    log_info "Generating Traefik dynamic configuration..."

    # Start with a clean file
    rm -f "$OUTPUT_FILE"
    touch "$OUTPUT_FILE"

    # Generate the main http block
    cat <<EOF > "$OUTPUT_FILE"
http:
  routers:
EOF

    # --- Process LXC Containers ---
    log_info "Processing LXC configurations..."
    for ctid in $(jq -r '.lxc_configs | keys[]' "$LXC_CONFIG_FILE"); do
        local lxc_config=$(jq -r ".lxc_configs.\"$ctid\"" "$LXC_CONFIG_FILE")
        local name=$(echo "$lxc_config" | jq -r '.name')
        local ip=$(echo "$lxc_config" | jq -r '.network_config.ip' | cut -d'/' -f1)
        
        # Check for services to expose via Traefik (e.g., based on a new "expose" flag or specific names)
        # For now, we'll hardcode the known services for simplicity
        case "$name" in
            "granite-embedding"|"granite-3.3-8b-fp8"|"ollama-gpu0"|"llamacpp-gpu0")
                local hostname="${name}.internal.thinkheads.ai"
                local port=$(echo "$lxc_config" | jq -r '.ports[0]' | cut -d':' -f1)
                
                cat <<EOF >> "$OUTPUT_FILE"
    ${name}-router:
      rule: "Host(\`${hostname}\`)"
      service: "${name}-service"
      entryPoints:
        - websecure
      tls:
        certResolver: myresolver
EOF
            ;;
        esac
    done

    # --- Process VMs (for Portainer) ---
    log_info "Processing VM configurations..."
    local domain_name=$(jq -r '.domain_name' "$HYPERVISOR_CONFIG_FILE")
    
    for vmid in $(jq -r '.vms[] | .vmid' "$VM_CONFIG_FILE"); do
        local vm_config=$(jq -r ".vms[] | select(.vmid == $vmid)" "$VM_CONFIG_FILE")
        local portainer_role=$(echo "$vm_config" | jq -r '.portainer_role')
        local name=$(echo "$vm_config" | jq -r '.name')

        if [[ "$portainer_role" == "primary" ]]; then
            local hostname="portainer.${domain_name}" # Force lowercase to match cert
            cat <<EOF >> "$OUTPUT_FILE"
    ${name}-router:
      rule: "Host(\`${hostname}\`)"
      service: "${name}-service"
      entryPoints:
        - websecure
      tls:
        certResolver: myresolver
EOF
        elif [[ "$portainer_role" == "agent" ]]; then
            local hostname="${name}.${domain_name}"
            cat <<EOF >> "$OUTPUT_FILE"
    ${name}-router:
      rule: "Host(\`${hostname}\`)"
      service: "${name}-service"
      entryPoints:
        - websecure
      tls:
        certResolver: myresolver
EOF
        fi
    done

    # --- Generate Services ---
    cat <<EOF >> "$OUTPUT_FILE"

  services:
EOF

    # --- Process LXC Services ---
    for ctid in $(jq -r '.lxc_configs | keys[]' "$LXC_CONFIG_FILE"); do
        local lxc_config=$(jq -r ".lxc_configs.\"$ctid\"" "$LXC_CONFIG_FILE")
        local name=$(echo "$lxc_config" | jq -r '.name')
        
        case "$name" in
            "granite-embedding"|"granite-3.3-8b-fp8"|"ollama-gpu0"|"llamacpp-gpu0")
                local ip=$(echo "$lxc_config" | jq -r '.network_config.ip' | cut -d'/' -f1)
                local port=$(echo "$lxc_config" | jq -r '.ports[0]' | cut -d':' -f1)
                
                cat <<EOF >> "$OUTPUT_FILE"
    ${name}-service:
      loadBalancer:
        servers:
          - url: "http://${ip}:${port}"
EOF
            ;;
        esac
    done

    # --- Process VM Services (Portainer) ---
    for vmid in $(jq -r '.vms[] | .vmid' "$VM_CONFIG_FILE"); do
        local vm_config=$(jq -r ".vms[] | select(.vmid == $vmid)" "$VM_CONFIG_FILE")
        local portainer_role=$(echo "$vm_config" | jq -r '.portainer_role')
        local name=$(echo "$vm_config" | jq -r '.name')
        local ip=$(echo "$vm_config" | jq -r '.network_config.ip' | cut -d'/' -f1)

        if [[ "$portainer_role" == "primary" ]]; then
            cat <<EOF >> "$OUTPUT_FILE"
    ${name}-service:
      loadBalancer:
        servers:
          - url: "https://${ip}:9443"
        serversTransport: portainer-transport
EOF
        elif [[ "$portainer_role" == "agent" ]]; then
            cat <<EOF >> "$OUTPUT_FILE"
    ${name}-service:
      loadBalancer:
        servers:
          - url: "https://${ip}:9001"
EOF
        fi
    done

    # --- Add serversTransports for specific services ---
    local domain_name=$(jq -r '.domain_name' "$HYPERVISOR_CONFIG_FILE")
    cat <<EOF >> "$OUTPUT_FILE"

  serversTransports:
    portainer-transport:
      serverName: "portainer.${domain_name}"
EOF

    log_success "Traefik dynamic configuration generated successfully at $OUTPUT_FILE"
    echo "$OUTPUT_FILE"
}

# If the script is executed directly, call the main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi