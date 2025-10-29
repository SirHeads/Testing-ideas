#!/bin/bash
# File: portainer-manager.sh
# Description: This script manages all Portainer-related operations for the Phoenix Hypervisor system.
#              It handles the deployment of Portainer server and agents, and the synchronization
#              of Docker stacks via the Portainer API.
#
# Dependencies:
#   - phoenix_hypervisor_common_utils.sh: A library of shared shell functions.
#   - jq: For parsing JSON configuration files.
#   - curl: For interacting with the Portainer API.
#
# Version: 1.0.0
# Author: Phoenix Hypervisor Team
#

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# --- Source common utilities ---
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"
source "${PHOENIX_BASE_DIR}/bin/managers/vm-manager.sh" # Source vm-manager.sh for run_qm_command

# --- Load external configurations ---
# Rely on HYPERVISOR_CONFIG_FILE exported from phoenix_hypervisor_common_utils.sh
STACKS_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_stacks_config.json"
CENTRALIZED_CA_CERT_PATH="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_ca.crt"
# =====================================================================================
# Function: wait_for_system_ready
# Description: Executes a series of health checks to ensure the system is ready
#              for Portainer operations. It uses a retry mechanism to wait for
#              services to become available.
#
# Returns:
#   0 on success, 1 on failure after all retries.
# =====================================================================================
wait_for_system_ready() {
    log_info "--- Waiting for all system components to be ready ---"
    local MAX_RETRIES=5
    local RETRY_DELAY=3
    local attempt=1

    # Define critical internal domains and their expected IP addresses

    local other_health_checks=(
        "check_nginx_gateway.sh"
        "check_traefik_proxy.sh"
        "check_step_ca.sh"
        "check_firewall.sh"
    )

    while [ "$attempt" -le "$MAX_RETRIES" ]; do
        log_info "Health check attempt ${attempt}/${MAX_RETRIES}..."
        local all_checks_passed=true

        # --- DNS Health Checks ---
        for domain in "${!critical_domains[@]}"; do
            local expected_ip="${critical_domains[$domain]}"
            if ! "${PHOENIX_BASE_DIR}/bin/health_checks/check_dns_resolution.sh" --context host --domain "$domain" --expected-ip "$expected_ip"; then
                log_warn "DNS health check failed for domain: $domain"
                all_checks_passed=false
                break 2 # Exit both loops to retry all checks
            fi
        done

        if [ "$all_checks_passed" = false ]; then
            # Go to the next attempt if DNS checks failed
            if [ "$attempt" -lt "$MAX_RETRIES" ]; then
                log_info "One or more health checks failed. Retrying in ${RETRY_DELAY} seconds..."
                sleep "$RETRY_DELAY"
            fi
            attempt=$((attempt + 1))
            continue
        fi

        # --- Other Health Checks ---
        for check_script in "${other_health_checks[@]}"; do
            if ! "${PHOENIX_BASE_DIR}/bin/health_checks/${check_script}"; then
                log_warn "Health check failed: ${check_script}"
                all_checks_passed=false
                break # Exit the inner loop to retry all checks
            fi
        done

        if [ "$all_checks_passed" = true ]; then
            log_success "All health checks passed. System is ready."
            return 0
        fi

        if [ "$attempt" -lt "$MAX_RETRIES" ]; then
            log_info "One or more health checks failed. Retrying in ${RETRY_DELAY} seconds..."
            sleep "$RETRY_DELAY"
        fi
        attempt=$((attempt + 1))
    done

    log_fatal "System is not ready after ${MAX_RETRIES} attempts. Aborting Portainer operations."
    return 1
}

# =====================================================================================
# Function: get_portainer_jwt
# Description: Authenticates with the Portainer API and retrieves a JWT.
#
# Returns:
#   The JWT on success, or exits with a fatal error on failure.
# =====================================================================================
get_portainer_jwt() {
    log_info "Attempting to authenticate with Portainer API..."
    local PORTAINER_HOSTNAME="portainer.internal.thinkheads.ai"
    local PORTAINER_PORT="443" # Always connect via the public-facing Nginx proxy port
    local PORTAINER_URL="https://${PORTAINER_HOSTNAME}"
    local USERNAME=$(get_global_config_value '.portainer_api.admin_user')
    local PASSWORD=$(get_global_config_value '.portainer_api.admin_password')
    local CA_CERT_PATH="${CENTRALIZED_CA_CERT_PATH}"

    log_debug "HYPERVISOR_CONFIG_FILE: ${HYPERVISOR_CONFIG_FILE}"
    log_debug "Raw admin_user from config: $(jq -r '.portainer_api.admin_user' "$HYPERVISOR_CONFIG_FILE")"
    log_debug "Raw admin_password from config: $(jq -r '.portainer_api.admin_password' "$HYPERVISOR_CONFIG_FILE")"

    log_debug "Portainer URL: ${PORTAINER_URL}"
    log_debug "Portainer Username: ${USERNAME}"
    log_debug "Portainer Password (first 3 chars): ${PASSWORD:0:3}..." # Mask password for security

    if [ ! -f "$CA_CERT_PATH" ]; then
        log_fatal "CA certificate file not found at: ${CA_CERT_PATH}. Cannot authenticate with Portainer API."
    fi

 
    local JWT_RESPONSE
    local JWT=""
    local AUTH_PAYLOAD=$(jq -n --arg user "$USERNAME" --arg pass "$PASSWORD" '{username: $user, password: $pass}')
    local MAX_RETRIES=5
    local RETRY_DELAY=5
    local attempt=1

    while [ -z "$JWT" ] && [ "$attempt" -le "$MAX_RETRIES" ]; do
        log_info "Authentication attempt ${attempt}/${MAX_RETRIES}..."
        JWT=$(retry_api_call -s -X POST -H "Content-Type: application/json" -d "${AUTH_PAYLOAD}" "${PORTAINER_URL}/api/auth" | jq -r '.jwt // ""')

        if [ -z "$JWT" ]; then
            log_warn "Authentication failed on attempt ${attempt}."
            sleep "$RETRY_DELAY"
            attempt=$((attempt + 1))
        fi
    done

    if [ -z "$JWT" ]; then
      log_fatal "Failed to authenticate with Portainer API after ${MAX_RETRIES} attempts."
    fi
    log_success "Successfully authenticated with Portainer API."
    echo "$JWT"
}

# =====================================================================================
# Function: deploy_portainer_instances
# Description: Deploys the Portainer server and agent containers to their respective VMs.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if deployment fails.
# =====================================================================================
deploy_portainer_instances() {
    wait_for_system_ready || return 1
    log_info "Deploying Portainer server and agent instances..."

    local vms_with_portainer
    vms_with_portainer=$(jq -c '.vms[] | select(.portainer_role == "primary" or .portainer_role == "agent")' "$VM_CONFIG_FILE")

    while read -r vm_config; do
        local VMID=$(echo "$vm_config" | jq -r '.vmid')
        local PORTAINER_ROLE=$(echo "$vm_config" | jq -r '.portainer_role')
        local VM_NAME=$(echo "$vm_config" | jq -r '.name')
        local persistent_volume_path=$(echo "$vm_config" | jq -r '.volumes[] | select(.type == "nfs") | .path' | head -n 1)
        local vm_mount_point=$(echo "$vm_config" | jq -r '.volumes[] | select(.type == "nfs") | .mount_point' | head -n 1)

        if [ -z "$persistent_volume_path" ] || [ -z "$vm_mount_point" ]; then
            log_fatal "VM $VMID is configured for Portainer but is missing NFS persistent volume details."
        fi

        log_info "Processing VM $VMID with Portainer role: $PORTAINER_ROLE"

        case "$PORTAINER_ROLE" in
            primary)
                log_info "Deploying Portainer server on VM $VMID..."
                local compose_file_path="${vm_mount_point}/portainer/docker-compose.yml"
                local config_json_path="${vm_mount_point}/portainer/config.json"

                # Ensure the Portainer directory exists on the hypervisor's NFS share
                local hypervisor_portainer_dir="${persistent_volume_path}/portainer"
                mkdir -p "$hypervisor_portainer_dir" || log_fatal "Failed to create hypervisor Portainer directory: $hypervisor_portainer_dir"

                # --- BEGIN: Idempotent Data Directory Creation ---
                # Ensure the data directory exists on the host with the correct permissions for the NFS mount.
                # This prevents "permission denied" errors when Docker (running as root inside the VM)
                # tries to create the directory via the bind mount, due to root_squash mapping root to nobody:nogroup.
                local hypervisor_portainer_data_dir="${hypervisor_portainer_dir}/data"
                log_info "Ensuring Portainer data directory exists at: ${hypervisor_portainer_data_dir}"
                if [ ! -d "$hypervisor_portainer_data_dir" ]; then
                    log_info "Creating Portainer data directory..."
                    mkdir -p "$hypervisor_portainer_data_dir" || log_fatal "Failed to create Portainer data directory."
                fi

                log_info "Ensuring correct permissions on Portainer data directory..."
                if [ "$(stat -c '%U:%G' "$hypervisor_portainer_data_dir")" != "nobody:nogroup" ]; then
                    log_info "Setting ownership to nobody:nogroup..."
                    chown nobody:nogroup "$hypervisor_portainer_data_dir" || log_fatal "Failed to set ownership on Portainer data directory."
                fi
                # --- END: Idempotent Data Directory Creation ---

                # Copy the docker-compose.yml from the source of truth to the hypervisor's NFS share
                log_info "Copying Portainer docker-compose.yml to hypervisor's NFS share: ${hypervisor_portainer_dir}/docker-compose.yml"
                log_info "Forcefully removing old docker-compose.yml to ensure a clean copy..."
                rm -f "${hypervisor_portainer_dir}/docker-compose.yml"
                cp "${PHOENIX_BASE_DIR}/persistent-storage/portainer/docker-compose.yml" "${hypervisor_portainer_dir}/docker-compose.yml" || log_fatal "Failed to copy docker-compose.yml to hypervisor's NFS share."



                # Ensure the compose file and config.json are present on the VM's persistent storage
                if ! qm guest exec "$VMID" -- /bin/bash -c "test -f $compose_file_path"; then
                    log_fatal "Portainer server compose file not found in VM $VMID at $compose_file_path."
                fi
                if ! qm guest exec "$VMID" -- /bin/bash -c "test -f $config_json_path"; then
                    log_warn "Portainer server config.json not found in VM $VMID at $config_json_path. Declarative endpoints may not be created."
                fi

                log_info "Ensuring clean restart for Portainer server on VM $VMID..."
                # Bring down the existing stack to apply changes without destroying data
                qm guest exec "$VMID" -- /bin/bash -c "cd $(dirname "$compose_file_path") && docker compose down --remove-orphans" || log_warn "Portainer server was not running or failed to stop cleanly on VM $VMID. Proceeding with deployment."
                
                # Forcefully remove the container by name to prevent conflicts
                qm guest exec "$VMID" -- /bin/bash -c "docker rm -f portainer_server" || log_warn "Portainer server container was not running or failed to remove cleanly. This is expected if it's the first run."



                log_info "Executing docker compose up -d for Portainer server on VM $VMID..."
                if [ "$PHOENIX_DRY_RUN" = "true" ]; then
                    log_info "DRY-RUN: Would execute 'docker compose up -d' for Portainer server on VM $VMID."
                else
                    if ! qm guest exec "$VMID" -- /bin/bash -c "cd $(dirname ${compose_file_path}) && docker compose -f ${compose_file_path} up -d"; then
                        log_fatal "Failed to deploy Portainer server on VM $VMID."
                    fi
                fi
                log_info "Portainer server deployment initiated on VM $VMID."
                
                log_info "Adding firewall rule to allow Traefik to access Portainer..."
                
                # The health check in sync_all will now handle waiting for the service to be ready.
                
                # --- BEGIN IMMEDIATE ADMIN SETUP ---
                log_info "Waiting for Portainer API and setting up admin user..."
                # Use the direct internal IP for initial setup to bypass the proxy layers.
                local portainer_server_ip="10.0.0.111"
                local portainer_server_port="9000"
                local PORTAINER_URL="http://${portainer_server_ip}:${portainer_server_port}"
                # The second argument (CA_CERT_PATH) is empty because we are using http.
                # The third argument (CURL_EXTRA_ARGS) is omitted as per the plan.
                setup_portainer_admin_user "$PORTAINER_URL" ""
                # --- END IMMEDIATE ADMIN SETUP ---
                ;;
            agent)
                log_info "Deploying Portainer agent on VM $VMID..."
                local agent_port=$(get_global_config_value '.network.portainer_agent_port')
                local agent_name=$(echo "$vm_config" | jq -r '.name')
                local domain_name=$(get_global_config_value '.domain_name')
                local agent_fqdn="${agent_name}.${domain_name}"



                log_info "Ensuring clean restart for Portainer agent on VM $VMID..."
                qm guest exec "$VMID" -- /bin/bash -c "docker rm -f portainer_agent" || log_warn "Portainer agent container was not running or failed to remove cleanly on VM $VMID. Proceeding with deployment."

                # The agent is now a standard non-TLS service. Traefik will handle TLS.
                log_info "Starting Portainer agent..."
                local docker_command="docker run -d -p ${agent_port}:9001 --name portainer_agent --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker/volumes:/var/lib/docker/volumes portainer/agent:latest"

                if [ "$PHOENIX_DRY_RUN" = "true" ]; then
                    log_info "DRY-RUN: Would execute 'docker run' for Portainer agent on VM $VMID."
                else
                    if ! qm guest exec "$VMID" -- /bin/bash -c "$docker_command"; then
                        log_fatal "Failed to deploy Portainer agent on VM $VMID."
                    fi
                fi
                log_info "Portainer agent deployment initiated on VM $VMID."

                # --- BEGIN AGENT HEALTH CHECK ---
                log_info "Waiting for Portainer agent on VM $VMID to become healthy..."
                local agent_health_check_retries=10
                local agent_health_check_delay=5
                local agent_health_check_attempt=1
                while [ "$agent_health_check_attempt" -le "$agent_health_check_retries" ]; do
                    local agent_status_json=$(qm guest exec "$VMID" -- /bin/bash -c "curl -s -o /dev/null -w '%{http_code}' http://localhost:9001/ping")
                    local agent_status_code=$(echo "$agent_status_json" | jq -r '."out-data" // ""')
                    if [ "$agent_status_code" == "204" ]; then
                        log_success "Portainer agent on VM $VMID is healthy."
                        break
                    fi
                    log_warn "Portainer agent on VM $VMID not yet healthy (HTTP status: ${agent_status_code}). Retrying in ${agent_health_check_delay} seconds... (Attempt ${agent_health_check_attempt}/${agent_health_check_retries})"
                    sleep "$agent_health_check_delay"
                    agent_health_check_attempt=$((agent_health_check_attempt + 1))
                done

                if [ "$agent_health_check_attempt" -gt "$agent_health_check_retries" ]; then
                    log_fatal "Portainer agent on VM $VMID did not become healthy after multiple retries. Aborting."
                fi
                # --- END AGENT HEALTH CHECK ---
                ;;
            *)
                log_warn "Unknown Portainer role '$PORTAINER_ROLE' for VM $VMID. Skipping deployment."
                ;;
        esac
    done < <(echo "$vms_with_portainer" | jq -c '.')
    log_success "Portainer server and agent instances deployment process completed."

}

# =====================================================================================
# Function: setup_portainer_admin_user
# Description: Sets up the initial admin user for Portainer if it hasn't been initialized yet.
# Arguments:
#   $1 - The Portainer URL (e.g., https://portainer.phoenix.local:9443)
#   $2 - The path to the CA certificate file.
# Returns:
#   None. Exits with a fatal error if admin user setup fails.
# =====================================================================================
setup_portainer_admin_user() {
    local PORTAINER_URL="$1"
    local CA_CERT_PATH="$2"
    local CURL_EXTRA_ARGS="$3" # Accept extra curl arguments, like --insecure
    local ADMIN_USERNAME=$(get_global_config_value '.portainer_api.admin_user')
    local ADMIN_PASSWORD=$(get_global_config_value '.portainer_api.admin_password')
    local MAX_RETRIES=5 # Increased retries for robustness
    local RETRY_DELAY=5
    local attempt=1

    if [ -z "$ADMIN_USERNAME" ] || [ "$ADMIN_USERNAME" == "null" ]; then
        log_fatal "Portainer admin username is not configured or is null in phoenix_hypervisor_config.json."
    fi
    if [ -z "$ADMIN_PASSWORD" ] || [ "$ADMIN_PASSWORD" == "null" ]; then
        log_fatal "Portainer admin password is not configured or is null in phoenix_hypervisor_config.json."
    fi

    log_info "Waiting for Portainer API to become available..."
    local status_attempt=1
    while [ "$status_attempt" -le "$MAX_RETRIES" ]; do
        local http_status
        http_status=$(curl -s -o /dev/null -w "%{http_code}" "${CURL_EXTRA_ARGS}" "${PORTAINER_URL}/api/system/status")
        
        if [[ "$http_status" -eq 200 ]]; then
            local body
            body=$(curl -s "${CURL_EXTRA_ARGS}" "${PORTAINER_URL}/api/system/status")
            if echo "$body" | jq -e '.InstanceID' > /dev/null; then
                log_info "Portainer is already initialized. Skipping admin user creation."
                return 0
            elif echo "$body" | jq -e '.Status == "No administrator account found"' > /dev/null; then
                log_success "Portainer API is responsive and ready for initialization."
                break
            fi
        elif [[ "$http_status" -eq 503 ]]; then
            log_info "Portainer API is starting up (HTTP 503). Retrying..."
        fi

        log_info "Portainer API not ready yet (HTTP status: ${http_status}). Retrying in ${RETRY_DELAY} seconds... (Attempt ${status_attempt}/${MAX_RETRIES})"
        sleep "$RETRY_DELAY"
        status_attempt=$((status_attempt + 1))
    done

    if [ "$status_attempt" -gt "$MAX_RETRIES" ]; then
        log_fatal "Portainer API did not become available after ${MAX_RETRIES} attempts."
    fi

    log_info "Attempting to create initial admin user '${ADMIN_USERNAME}' (or verify existence)..."
    local INIT_PAYLOAD
    INIT_PAYLOAD=$(jq -n --arg user "$ADMIN_USERNAME" --arg pass "$ADMIN_PASSWORD" '{username: $user, password: $pass}')

    while [ "$attempt" -le "$MAX_RETRIES" ]; do
        log_info "Admin user creation attempt ${attempt}/${MAX_RETRIES}..."
        
        local curl_args=(-s -w "HTTP_STATUS:%{http_code}" "${CURL_EXTRA_ARGS}")
        if [ -n "$CA_CERT_PATH" ]; then
            curl_args+=(--cacert "$CA_CERT_PATH")
        fi
        
        local response
        response=$(curl "${curl_args[@]}" -X POST -H "Content-Type: application/json" -d "${INIT_PAYLOAD}" "${PORTAINER_URL}/api/users/admin/init")
        
        local http_status
        http_status=$(echo "$response" | sed -n 's/.*HTTP_STATUS://p')
        local body
        body=$(echo "$response" | sed 's/HTTP_STATUS:.*//')

        log_debug "Admin creation response body: ${body}"
        log_debug "Admin creation HTTP status: ${http_status}"

        # Success Case 1: User created successfully
        if [[ "$http_status" -eq 200 ]]; then
            log_success "Portainer admin user '${ADMIN_USERNAME}' created successfully."
            return 0
        # Success Case 2: User already exists
        elif [[ "$http_status" -eq 409 ]]; then
            log_info "Portainer admin user '${ADMIN_USERNAME}' already exists. Skipping creation."
            return 0
        # Retry Case: Portainer is not fully initialized yet
        elif echo "$body" | jq -e '.details | contains("Administrator initialization timeout")' > /dev/null; then
            log_warn "Portainer is not fully initialized yet. Retrying in ${RETRY_DELAY} seconds. (Attempt ${attempt}/${MAX_RETRIES})"
        # General Failure Case
        else
            log_warn "Failed to create Portainer admin user with HTTP status ${http_status}. Retrying in ${RETRY_DELAY} seconds. (Attempt ${attempt}/${MAX_RETRIES})"
            log_warn "Response: ${body}"
        fi

        sleep "$RETRY_DELAY"
        attempt=$((attempt + 1))
    done

    log_fatal "Failed to create or verify Portainer admin user after ${MAX_RETRIES} attempts. The service may be unhealthy."
}

# =====================================================================================
# Function: sync_all
# Description: Synchronizes all Portainer environments and deploys all associated stacks.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error on failure.
# =====================================================================================
sync_all() {
    log_info "--- Starting Full System State Synchronization ---"

    # --- STAGE 1: CERTIFICATE GENERATION & CORE INFRASTRUCTURE ---
    log_info "--- Stage 1: Synchronizing Certificates, DNS, and Firewall ---"

    # Ensure the Proxmox host trusts our internal CA before proceeding
    log_info "Ensuring Step-CA root certificate is present on the Proxmox host..."
    local step_ca_ctid="103"
    if pct status "$step_ca_ctid" > /dev/null 2>&1; then
        if ! "${PHOENIX_BASE_DIR}/bin/hypervisor_setup/hypervisor_feature_install_trusted_ca.sh"; then
            log_fatal "Failed to install trusted CA on the host. Aborting."
        fi
    else
        log_warn "Step-CA container (${step_ca_ctid}) not found. Skipping host trust installation."
    fi


    # Sync DNS server configuration
    if ! "${PHOENIX_BASE_DIR}/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh"; then
        log_fatal "DNS synchronization failed. Aborting."
    fi
    log_success "DNS server configuration synchronized."

    # Sync global firewall rules
    if ! "${PHOENIX_BASE_DIR}/bin/hypervisor_setup/hypervisor_feature_setup_firewall.sh" "$HYPERVISOR_CONFIG_FILE"; then
        log_fatal "Global firewall synchronization failed. Aborting."
    fi
    log_success "Global firewall rules synchronized."

    # --- STAGE 2: DEPLOY & VERIFY UPSTREAM SERVICES ---
    log_info "--- Stage 2: Deploying and Verifying Portainer ---"
    local portainer_vmid="1001"
    if qm status "$portainer_vmid" > /dev/null 2>&1; then
        log_info "Portainer VM (1001) is running. Proceeding with deployment."
        deploy_portainer_instances
    else
        log_warn "Portainer VM (1001) is not running. Skipping all subsequent stages."
        log_info "--- Full System State Synchronization Finished (Aborted) ---"
        return
    fi

    # --- STAGE 3: CONFIGURE SERVICE MESH ---
    log_info "--- Stage 3: Synchronizing Traefik Proxy ---"
    local traefik_ctid="102"
    if pct status "$traefik_ctid" > /dev/null 2>&1; then
        log_info "Traefik container (102) is running. Generating and applying configuration."
        if ! "${PHOENIX_BASE_DIR}/bin/generate_traefik_config.sh"; then
            log_fatal "Failed to generate Traefik configuration."
        fi
        if ! pct push "$traefik_ctid" "${PHOENIX_BASE_DIR}/etc/traefik/dynamic_conf.yml" /etc/traefik/dynamic/dynamic_conf.yml; then
            log_fatal "Failed to push Traefik dynamic config to container 102."
        fi
        pct exec "$traefik_ctid" -- chmod 644 /etc/traefik/dynamic/dynamic_conf.yml
        if ! pct exec "$traefik_ctid" -- systemctl reload traefik; then
            log_warn "Failed to reload Traefik service. A restart may be required." "pct exec 102 -- journalctl -u traefik -n 50"
        fi
        log_success "Traefik synchronization complete."
    else
        log_warn "Traefik container (102) is not running. Skipping Traefik synchronization."
    fi

    # --- STAGE 4: CONFIGURE GATEWAY ---
    log_info "--- Stage 4: Synchronizing NGINX Gateway ---"
    log_info "Generating and applying dynamic NGINX gateway configuration..."
    if ! "${PHOENIX_BASE_DIR}/bin/generate_nginx_gateway_config.sh"; then
        log_fatal "Failed to generate dynamic NGINX configuration."
    fi
    if ! pct push 101 "${PHOENIX_BASE_DIR}/etc/nginx/sites-available/gateway" /etc/nginx/sites-available/gateway; then
        log_fatal "Failed to push generated gateway config to NGINX container."
    fi
    log_info "Reloading Nginx in container 101..."
    if ! pct exec 101 -- systemctl reload nginx; then
        log_fatal "Failed to reload Nginx in container 101." "pct exec 101 -- journalctl -u nginx -n 50"
    fi
    log_success "NGINX gateway configuration applied and reloaded successfully."

    # --- STAGE 5: SYNCHRONIZE STACKS ---
    log_info "--- Stage 5: Synchronizing Portainer Endpoints and Docker Stacks ---"
    local JWT=$(get_portainer_jwt | tr -d '\n')
    local CA_CERT_PATH="${CENTRALIZED_CA_CERT_PATH}"
    sync_portainer_endpoints "$JWT" "$CA_CERT_PATH"
    
    log_info "--- Synchronizing all declared Docker stacks ---"
    local vms_with_stacks
    vms_with_stacks=$(jq -c '.vms[] | select(.docker_stacks and (.docker_stacks | length > 0))' "$VM_CONFIG_FILE")
    while read -r vm_config; do
        local VMID=$(echo "$vm_config" | jq -r '.vmid')
        local agent_ip=$(echo "$vm_config" | jq -r '.network_config.ip' | cut -d'/' -f1)
        local AGENT_PORT=$(get_global_config_value '.network.portainer_agent_port')
        local ENDPOINT_URL="tcp://${agent_ip}:${AGENT_PORT}"
        
        log_info "Fetching Portainer endpoint ID for VM ${VMID}..."
        local endpoints_response
        endpoints_response=$(retry_api_call -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}")
        local ENDPOINT_ID=$(echo "$endpoints_response" | jq -r --arg url "${ENDPOINT_URL}" '.[] | select(.URL==$url) | .Id // ""')
        
        if [ -z "$ENDPOINT_ID" ]; then
            log_warn "Could not find Portainer endpoint for VM ${VMID}. Skipping stack deployment."
            continue
        fi

        echo "$vm_config" | jq -c '.docker_stacks[]' | while read -r stack_config; do
            sync_stack "$VMID" "$stack_config" "$JWT" "$ENDPOINT_ID"
        done
    done < <(echo "$vms_with_stacks" | jq -c '.')
    log_info "--- Docker stack synchronization complete ---"

    # --- FINAL HEALTH CHECK ---
    log_info "--- Performing final health check on Portainer API endpoint ---"
    local health_check_script="${PHOENIX_BASE_DIR}/bin/health_checks/check_portainer_api.sh"
    local max_retries=10
    local retry_delay=10
    local attempt=1
    while [ "$attempt" -le "$max_retries" ]; do
        if "$health_check_script"; then
            log_success "Portainer API health check passed."
            break
        fi
        log_warn "Portainer API health check failed on attempt $attempt/$max_retries. Retrying in $retry_delay seconds..."
        sleep "$retry_delay"
        attempt=$((attempt + 1))
    done
    if [ "$attempt" -gt "$max_retries" ]; then
        log_fatal "Portainer API did not become healthy after $max_retries attempts. Aborting."
    fi

    log_info "--- Full System State Synchronization Finished ---"
}

# =====================================================================================
# Function: sync_stack
# Description: Synchronizes a specific Docker stack to a given VM's Portainer environment.
# Arguments:
#   $1 - The VMID of the target VM.
#   $2 - The JSON object defining the stack and its environment (e.g., { "name": "stack_name", "environment": "env_name" }).
#   $3 - (Optional) The JWT for Portainer API authentication. If not provided, it will be fetched.
#   $4 - (Optional) The Portainer Endpoint ID. If not provided, it will be fetched.
# Returns:
#   None. Exits with a fatal error on failure.
# =====================================================================================
sync_stack() {
    local VMID="$1"
    local STACK_CONFIG_JSON="$2" # This will be the JSON object: { "name": "stack_name", "environment": "env_name" }
    local JWT="${3:-}" # Use provided JWT or fetch new one
    local ENDPOINT_ID="${4:-}" # Use provided Endpoint ID or fetch new one

    local STACK_NAME=$(echo "$STACK_CONFIG_JSON" | jq -r '.name')
    local ENVIRONMENT_NAME=$(echo "$STACK_CONFIG_JSON" | jq -r '.environment')

    log_info "DEBUG: STACK_CONFIG_JSON: ${STACK_CONFIG_JSON}"
    log_info "Synchronizing stack '${STACK_NAME}' (environment: '${ENVIRONMENT_NAME}') to VMID '${VMID}'..."

    local portainer_hostname="portainer.internal.thinkheads.ai"
    local PORTAINER_URL="https://${portainer_hostname}"
    local CA_CERT_PATH="${CENTRALIZED_CA_CERT_PATH}"

    if [ -z "$JWT" ]; then
        JWT=$(get_portainer_jwt)
    fi

    if [ -z "$ENDPOINT_ID" ]; then
        local agent_ip=$(jq -r ".vms[] | select(.vmid == $VMID) | .network_config.ip" "$VM_CONFIG_FILE" | cut -d'/' -f1)
        local AGENT_PORT=$(get_global_config_value '.network.portainer_agent_port')
        local ENDPOINT_URL="tcp://${agent_ip}:${AGENT_PORT}"
        local endpoints_response
        endpoints_response=$(retry_api_call -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}")
        ENDPOINT_ID=$(echo "$endpoints_response" | jq -r --arg url "${ENDPOINT_URL}" '.[] | select(.URL==$url) | .Id // ""')
        if [ -z "$ENDPOINT_ID" ]; then
            log_fatal "Could not find Portainer environment for VMID ${VMID} (URL: ${ENDPOINT_URL}). Ensure agent is running and environment is created."
        fi
    fi

    local STACK_DEFINITION
    STACK_DEFINITION=$(jq -r ".docker_stacks.\"${STACK_NAME}\".environments.\"${ENVIRONMENT_NAME}\"" "$STACKS_CONFIG_FILE")
    log_info "DEBUG: STACK_DEFINITION: ${STACK_DEFINITION}"
    if [ "$STACK_DEFINITION" == "null" ]; then
        log_fatal "Stack '${STACK_NAME}' with environment '${ENVIRONMENT_NAME}' not found in ${STACKS_CONFIG_FILE}."
    fi

    local COMPOSE_FILE_PATH=$(jq -r ".docker_stacks.\"${STACK_NAME}\".compose_file_path" "$STACKS_CONFIG_FILE")
    local FULL_COMPOSE_PATH="${PHOENIX_BASE_DIR}/${COMPOSE_FILE_PATH}"

    if [ ! -f "$FULL_COMPOSE_PATH" ]; then
        log_fatal "Compose file ${FULL_COMPOSE_PATH} not found for stack '${STACK_NAME}'. Cannot deploy."
    fi

    # --- BEGIN FILE-BASED DEPLOYMENT LOGIC ---
    local vm_config=$(jq -r ".vms[] | select(.vmid == $VMID)" "$VM_CONFIG_FILE")
    local persistent_volume_path=$(echo "$vm_config" | jq -r '.volumes[] | select(.type == "nfs") | .path' | head -n 1)
    local vm_mount_point=$(echo "$vm_config" | jq -r '.volumes[] | select(.type == "nfs") | .mount_point' | head -n 1)

    if [ -z "$persistent_volume_path" ] || [ -z "$vm_mount_point" ]; then
        log_fatal "VM $VMID is missing NFS persistent volume details. Cannot deploy stack from file."
    fi

    local hypervisor_stack_dir="${persistent_volume_path}/stacks/${STACK_NAME}"
    local agent_stack_path="${vm_mount_point}/stacks/${STACK_NAME}/docker-compose.yml"

    log_info "Preparing stack file on persistent storage for VM ${VMID}..."
    log_info "Hypervisor path: ${hypervisor_stack_dir}/docker-compose.yml"
    log_info "Agent path: ${agent_stack_path}"

    mkdir -p "$hypervisor_stack_dir" || log_fatal "Failed to create stack directory on hypervisor: $hypervisor_stack_dir"
    chmod 777 "$hypervisor_stack_dir" || log_warn "Failed to set permissions on stack directory: $hypervisor_stack_dir"
    cp "$FULL_COMPOSE_PATH" "${hypervisor_stack_dir}/docker-compose.yml" || log_fatal "Failed to copy compose file to hypervisor's persistent storage."

    # --- BEGIN TRAEFIK LABEL INJECTION ---
    log_info "Injecting Traefik labels into compose file for stack '${STACK_NAME}'..."
    local services_to_label=$(echo "$STACK_DEFINITION" | jq -r '.services | keys[] // ""')
    for service_name in $services_to_label; do
        local labels=$(echo "$STACK_DEFINITION" | jq -c ".services.\"${service_name}\".traefik_labels // []")
        if [ "$(echo "$labels" | jq 'length')" -gt 0 ]; then
            log_info "  Injecting labels for service: ${service_name}"
            local yq_script=""
            echo "$labels" | jq -r '.[]' | while read -r label; do
                yq_script+=" .services.\"${service_name}\".labels += [\"${label}\"] |"
            done
            yq_script=${yq_script%?} # Remove trailing pipe
            yq eval -i "$yq_script" "${hypervisor_stack_dir}/docker-compose.yml"
        fi
    done
    log_success "Traefik label injection complete."
    # --- END TRAEFIK LABEL INJECTION ---

    # --- END FILE-BASED DEPLOYMENT LOGIC ---

    # --- Handle Environment Variables ---
    local ENV_VARS_JSON="[]"
    local variables_array=$(echo "$STACK_DEFINITION" | jq -c '.variables // []')
    log_info "DEBUG: Raw variables_array: ${variables_array}"
    if [ "$(echo "$variables_array" | jq 'length')" -gt 0 ]; then
        ENV_VARS_JSON=$(echo "$variables_array" | jq -c '. | map({name: .name, value: .value})')
        log_info "DEBUG: Processed ENV_VARS_JSON: ${ENV_VARS_JSON}"
    fi

    # --- Handle Configuration Files (Portainer Configs) ---
    local CONFIG_IDS_JSON="[]"
    local files_array=$(echo "$STACK_DEFINITION" | jq -c '.files // []')
    log_info "DEBUG: Raw files_array: ${files_array}"
    if [ "$(echo "$files_array" | jq 'length')" -gt 0 ]; then
        local temp_config_ids="[]"
        echo "$files_array" | jq -c '.[]' | while read -r file_config; do
            local SOURCE_PATH=$(echo "$file_config" | jq -r '.source')
            local DESTINATION_PATH=$(echo "$file_config" | jq -r '.destination_in_container')
            local CONFIG_NAME="${STACK_NAME}-${ENVIRONMENT_NAME}-$(basename "$SOURCE_PATH" | tr '.' '-')" # Unique name for Portainer Config
            log_info "DEBUG: Processing file config: ${file_config}"
            log_info "DEBUG: SOURCE_PATH: ${SOURCE_PATH}, DESTINATION_PATH: ${DESTINATION_PATH}, CONFIG_NAME: ${CONFIG_NAME}"

            if [ ! -f "${PHOENIX_BASE_DIR}/${SOURCE_PATH}" ]; then
                log_fatal "Source config file not found: ${PHOENIX_BASE_DIR}/${SOURCE_PATH} for stack '${STACK_NAME}'."
            fi
            local FILE_CONTENT=$(cat "${PHOENIX_BASE_DIR}/${SOURCE_PATH}")

            # Check if config already exists
            local configs_response
            configs_response=$(retry_api_call -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/configs" -H "Authorization: Bearer ${JWT}")
            local EXISTING_CONFIG_ID=$(echo "$configs_response" | jq -r --arg name "${CONFIG_NAME}" '.[] | select(.Name==$name) | .Id // ""')

            if [ -n "$EXISTING_CONFIG_ID" ]; then
                log_info "Portainer Config '${CONFIG_NAME}' already exists. Deleting and recreating to ensure content is fresh."
                if ! retry_api_call -s --cacert "$CA_CERT_PATH" -X DELETE "${PORTAINER_URL}/api/configs/${EXISTING_CONFIG_ID}" -H "Authorization: Bearer ${JWT}"; then
                    log_warn "Failed to delete old Portainer Config '${CONFIG_NAME}'. Proceeding, but this might cause issues."
                fi
            fi

            log_info "Creating Portainer Config '${CONFIG_NAME}'..."
            local CONFIG_PAYLOAD=$(jq -n --arg name "${CONFIG_NAME}" --arg data "${FILE_CONTENT}" '{Name: $name, Data: $data}')
            local CONFIG_RESPONSE
            CONFIG_RESPONSE=$(retry_api_call -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/configs?endpointId=${ENDPOINT_ID}" \
              -H "Authorization: Bearer ${JWT}" -H "Content-Type: application/json" -d "${CONFIG_PAYLOAD}")
            local NEW_CONFIG_ID=$(echo "$CONFIG_RESPONSE" | jq -r '.Id // ""')
            log_info "DEBUG: Portainer Config creation response: ${CONFIG_RESPONSE}"
            
            if [ -z "$NEW_CONFIG_ID" ]; then
                log_fatal "Failed to create Portainer Config '${CONFIG_NAME}'. Response: ${CONFIG_RESPONSE}"
            fi
            log_info "Portainer Config '${CONFIG_NAME}' created with ID: ${NEW_CONFIG_ID}"
            temp_config_ids=$(echo "$temp_config_ids" | jq --arg id "$NEW_CONFIG_ID" --arg dest "$DESTINATION_PATH" '. + [{configId: $id, fileName: $dest}]')
        done
        CONFIG_IDS_JSON="$temp_config_ids"
        log_info "DEBUG: Processed CONFIG_IDS_JSON: ${CONFIG_IDS_JSON}"
    fi

    local STACK_EXISTS_ID
    local stacks_response
    stacks_response=$(retry_api_call -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/stacks" -H "Authorization: Bearer ${JWT}")
    STACK_EXISTS_ID=$(echo "$stacks_response" | jq -r --arg name "${STACK_NAME}-${ENVIRONMENT_NAME}" --argjson endpoint_id "${ENDPOINT_ID}" '.[] | select(.Name==$name and .EndpointId==$endpoint_id) | .Id // ""')

    local STACK_DEPLOY_NAME="${STACK_NAME}-${ENVIRONMENT_NAME}" # Unique stack name in Portainer

    if [ -n "$STACK_EXISTS_ID" ]; then
        log_info "Stack '${STACK_DEPLOY_NAME}' already exists on environment ID '${ENDPOINT_ID}'. Updating..."
        local JSON_PAYLOAD=$(jq -n \
            --arg path "${agent_stack_path}" \
            --argjson env "$ENV_VARS_JSON" \
            --argjson configs "$CONFIG_IDS_JSON" \
            '{StackFilePath: $path, Env: $env, Configs: $configs, Prune: true}')
        log_info "DEBUG: PUT JSON_PAYLOAD: ${JSON_PAYLOAD}"
        local RESPONSE
        RESPONSE=$(retry_api_call -s --cacert "$CA_CERT_PATH" -X PUT "${PORTAINER_URL}/api/stacks/${STACK_EXISTS_ID}?endpointId=${ENDPOINT_ID}" \
          -H "Authorization: Bearer ${JWT}" -H "Content-Type: application/json" -d "${JSON_PAYLOAD}")
        log_info "DEBUG: PUT API RESPONSE: ${RESPONSE}"
        if echo "$RESPONSE" | jq -e '.Id' > /dev/null; then
          log_success "Stack '${STACK_DEPLOY_NAME}' updated successfully."
        else
          log_fatal "Failed to update stack '${STACK_DEPLOY_NAME}'. Response: ${RESPONSE}"
        fi
    else
        log_info "Stack '${STACK_DEPLOY_NAME}' does not exist on environment ID '${ENDPOINT_ID}'. Deploying..."
        local JSON_PAYLOAD=$(jq -n \
            --arg name "${STACK_DEPLOY_NAME}" \
            --arg path "${agent_stack_path}" \
            --argjson env "$ENV_VARS_JSON" \
            --argjson configs "$CONFIG_IDS_JSON" \
            '{Name: $name, ComposeFilePathInContainer: $path, Env: $env, Configs: $configs}')
        log_info "DEBUG: POST JSON_PAYLOAD: ${JSON_PAYLOAD}"
        local RESPONSE
        RESPONSE=$(retry_api_call -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/stacks?type=2&method=file&endpointId=${ENDPOINT_ID}" \
          -H "Authorization: Bearer ${JWT}" -H "Content-Type: application/json" -d "${JSON_PAYLOAD}")
        log_info "DEBUG: POST API RESPONSE: ${RESPONSE}"
        if echo "$RESPONSE" | jq -e '.Id' > /dev/null; then
          log_success "Stack '${STACK_DEPLOY_NAME}' deployed successfully."
        else
          log_fatal "Failed to deploy stack '${STACK_DEPLOY_NAME}'. Response: ${RESPONSE}"
        fi
    fi
}

# =====================================================================================
# Function: sync_portainer_endpoints
# Description: Ensures that all Portainer agent endpoints defined in the configuration
#              are registered with the Portainer server.
# Arguments:
#   $1 - The Portainer JWT.
#   $2 - The path to the CA certificate.
# =====================================================================================
sync_portainer_endpoints() {
    local JWT="$1"
    local CA_CERT_PATH="$2"
    local PORTAINER_HOSTNAME="portainer.internal.thinkheads.ai"
    local PORTAINER_URL="https://${PORTAINER_HOSTNAME}"

    log_info "--- Synchronizing Portainer Endpoints ---"

    local agents_to_register
    agents_to_register=$(jq -c '.vms[] | select(.portainer_role == "agent")' "$VM_CONFIG_FILE")

    while read -r agent_config; do
        local VMID=$(echo "$agent_config" | jq -r '.vmid')
        local AGENT_NAME=$(echo "$agent_config" | jq -r '.portainer_environment_name' | tr -d '[:space:]')
        local AGENT_HOSTNAME=$(echo "$agent_config" | jq -r '.portainer_agent_hostname // ""')
        if [ -z "$AGENT_HOSTNAME" ]; then
            log_warn "portainer_agent_hostname not defined for VM ${VMID}. Falling back to legacy naming convention."
            AGENT_HOSTNAME="${AGENT_NAME}.internal.thinkheads.ai"
        fi
        log_info "Using agent hostname: ${AGENT_HOSTNAME} for VM ${VMID}"
        local AGENT_PORT=$(get_global_config_value '.network.portainer_agent_port')
        local ENDPOINT_URL="tcp://${AGENT_HOSTNAME}:${AGENT_PORT}"

        log_info "Checking for existing endpoint for VM ${VMID} ('${AGENT_NAME}')..."
        
        local endpoints_response
        endpoints_response=$(retry_api_call -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}")
        local EXISTING_ENDPOINT_ID=$(echo "$endpoints_response" | jq -r --arg name "${AGENT_NAME}" '.[] | select(.Name==$name) | .Id // ""')

        if [ -n "$EXISTING_ENDPOINT_ID" ]; then
            log_info "Endpoint '${AGENT_NAME}' already exists with ID ${EXISTING_ENDPOINT_ID}. No update needed for non-TLS endpoint."
        else
            log_info "Endpoint '${AGENT_NAME}' not found. Creating it now as a standard non-TLS endpoint..."
            local CREATE_RESPONSE
            CREATE_RESPONSE=$(jq -n \
                --arg name "$AGENT_NAME" \
                --arg url "$ENDPOINT_URL" \
                --argjson groupID 1 \
                '{ "Name": $name, "URL": $url, "Type": 2, "GroupID": $groupID, "TLS": false }' | \
                retry_api_call -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/endpoints" \
                    -H "Authorization: Bearer ${JWT}" \
                    -H "Content-Type: application/json" \
                    --data-binary @-)

            if echo "$CREATE_RESPONSE" | jq -e '.Id' > /dev/null; then
                log_success "Successfully created endpoint for VM ${VMID}."
            else
                log_fatal "Failed to create endpoint for VM ${VMID}. Response: ${CREATE_RESPONSE}"
            fi
        fi
    done < <(echo "$agents_to_register" | jq -c '.')
    log_info "--- Portainer Endpoint Synchronization Complete ---"
}

# =====================================================================================
# Function: main_portainer_orchestrator
# Description: The main entry point for the Portainer manager script. It parses the
#              action and arguments, and then executes the appropriate operations.
# Arguments:
#   $@ - The command-line arguments passed to the script.
# =====================================================================================
main_portainer_orchestrator() {
    local action="$1"
    shift

    local config_file_override=""
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --config)
                config_file_override="$2"
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done

    if [ -n "$config_file_override" ]; then
        export HYPERVISOR_CONFIG_FILE="$config_file_override"
        log_debug "HYPERVISOR_CONFIG_FILE overridden to: $HYPERVISOR_CONFIG_FILE"
    fi

    local config_file_override=""
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --config)
                config_file_override="$2"
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done

    if [ -n "$config_file_override" ]; then
        export HYPERVISOR_CONFIG_FILE="$config_file_override"
        log_debug "HYPERVISOR_CONFIG_FILE overridden to: $HYPERVISOR_CONFIG_FILE"
    fi

    case "$action" in
        sync)
            local target="$1"
            if [ "$target" == "all" ]; then
                sync_all
            elif [ "$1" == "stack" ]; then
                local stack_name_from_cli="$2"
                local to_keyword="$3"
                local vmid_from_cli="$4"
                if [ "$to_keyword" == "to" ] && [ -n "$stack_name_from_cli" ] && [ -n "$vmid_from_cli" ]; then
                    # For CLI, we assume 'production' environment if not specified, or could add a CLI arg for it
                    local CLI_ENVIRONMENT="production" # Default to production for CLI sync stack
                    local CLI_STACK_CONFIG=$(jq -n --arg name "$stack_name_from_cli" --arg env "$CLI_ENVIRONMENT" '{name: $name, environment: $env}')
                    sync_stack "$vmid_from_cli" "$CLI_STACK_CONFIG"
                else
                    log_fatal "Invalid arguments for 'sync stack'. Usage: sync stack <stack_name> to <vmid>"
                fi
            else
                log_fatal "Invalid target for 'sync'. Usage: sync (all | stack <stack_name> to <vmid>)"
            fi
            ;;
        *)
            log_fatal "Invalid action '$action' for portainer-manager. Valid actions: sync"
            ;;
    esac
}

# If the script is executed directly, call the main orchestrator
if [[ "${BASH_SOURCE}" == "${0}" ]]; then
    main_portainer_orchestrator "$@"
fi