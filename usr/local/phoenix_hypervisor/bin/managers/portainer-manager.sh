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
CENTRALIZED_CA_CERT_PATH="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt"
# =====================================================================================
# =====================================================================================
# Function: discover_stacks
# Description: Scans the stacks directory, validates each stack's configuration,
#              and compiles them into a single JSON object.
#
# Returns:
#   A JSON object containing the configurations of all valid stacks.
# =====================================================================================
discover_stacks() {
    local stacks_dir="${PHOENIX_BASE_DIR}/stacks"
    local all_stacks_json="{}"

    if [ ! -d "$stacks_dir" ]; then
        log_warn "Stacks directory not found at: ${stacks_dir}"
        echo "$all_stacks_json"
        return
    fi

    for stack_dir in "$stacks_dir"/*/; do
        if [ -d "$stack_dir" ]; then
            local stack_name=$(basename "$stack_dir")
            local compose_file="${stack_dir}docker-compose.yml"
            local manifest_file="${stack_dir}phoenix.json"

            if [ ! -f "$compose_file" ]; then
                log_warn "Stack '${stack_name}' is missing a docker-compose.yml file. Skipping."
                continue
            fi

            if [ ! -f "$manifest_file" ]; then
                log_warn "Stack '${stack_name}' is missing a phoenix.json manifest file. Skipping."
                continue
            fi

            local manifest_content=$(jq -c . "$manifest_file")
            all_stacks_json=$(echo "$all_stacks_json" | jq --argjson content "$manifest_content" --arg name "$stack_name" '. + {($name): $content}')
        fi
    done

    echo "$all_stacks_json"
}
# Function: retry_api_call
# Description: A robust wrapper for executing curl commands to interact with APIs.
#              It includes retry logic, detailed logging, and handles different
#              HTTP methods and payloads.
#
# Arguments:
#   $@ - The curl command arguments.
#
# Returns:
#   The body of the API response on success. Exits with a fatal error on failure.
# =====================================================================================
retry_api_call() {
    local MAX_RETRIES=5
    local RETRY_DELAY=5
    local attempt=1
    local response
    local http_status

    log_debug "Executing API call with sensitive data masked..."

    while [ "$attempt" -le "$MAX_RETRIES" ]; do
        response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" "$@")
        http_status=$(echo -e "$response" | tail -n1 | sed -n 's/.*HTTP_STATUS://p')
        body=$(echo -e "$response" | sed '$d')

        if [[ "$http_status" -ge 200 && "$http_status" -lt 300 ]]; then
            log_debug "API call successful (HTTP ${http_status})."
            log_debug "Response body: ${body}"
            echo -e "$body"
            return 0
        elif [[ "$http_status" -eq 409 ]]; then
             log_info "API call returned HTTP 409 (Conflict). This is often expected (e.g., resource already exists)."
             log_debug "Response body: ${body}"
             echo -e "$body"
             return 0
        else
            log_warn "API call failed with HTTP status ${http_status} (Attempt ${attempt}/${MAX_RETRIES})."
            log_warn "Response body: ${body}"
            if [ "$attempt" -lt "$MAX_RETRIES" ]; then
                log_info "Retrying in ${RETRY_DELAY} seconds..."
                sleep "$RETRY_DELAY"
            fi
        fi
        attempt=$((attempt + 1))
    done

    log_error "API call failed after ${MAX_RETRIES} attempts."
    # Do not exit fatally, but return a failure code so the caller can decide how to proceed.
    return 1
}

# =====================================================================================
# Function: get_or_create_portainer_api_key
# Description: Retrieves the Portainer API key from the config, validates it, and
#              generates a new one if it's missing or invalid.
#
# Returns:
#   The valid API key on success, or exits with a fatal error on failure.
# =====================================================================================
get_or_create_portainer_api_key() {
    log_info "--- Ensuring Portainer API Key is available ---"
    local PORTAINER_SERVER_IP=$(get_global_config_value '.network.portainer_server_ip')
    local PORTAINER_URL="http://${PORTAINER_SERVER_IP}:9000"
    local API_KEY=$(get_global_config_value '.portainer_api.api_key // ""')
    local key_is_valid=false

    # 1. Validate existing key
    if [ -n "$API_KEY" ] && [ "$API_KEY" != "null" ]; then
        log_info "Validating existing Portainer API key..."
        local status_response
        status_response=$(curl -s -H "X-API-Key: ${API_KEY}" "${PORTAINER_URL}/api/system/status")
        if echo "$status_response" | jq -e '.Status == "healthy"' > /dev/null; then
            log_success "Existing Portainer API key is valid."
            key_is_valid=true
        else
            log_warn "Existing Portainer API key is invalid. A new key will be generated."
        fi
    else
        log_info "No Portainer API key found in configuration. A new key will be generated."
    fi

    # 2. Generate new key if necessary
    if [ "$key_is_valid" = false ]; then
        log_info "Generating new Portainer API key..."
        local USERNAME=$(get_global_config_value '.portainer_api.admin_user')
        local PASSWORD=$(get_global_config_value '.portainer_api.admin_password')

        # Get a temporary JWT
        local AUTH_PAYLOAD
        AUTH_PAYLOAD=$(jq -n --arg user "$USERNAME" --arg pass "$PASSWORD" '{username: $user, password: $pass}')
        local JWT_RESPONSE
        JWT_RESPONSE=$(retry_api_call -X POST -H "Content-Type: application/json" -d "$AUTH_PAYLOAD" "${PORTAINER_URL}/api/auth")
        local JWT=$(echo "$JWT_RESPONSE" | jq -r '.jwt // ""')

        if [ -z "$JWT" ]; then
            log_fatal "Failed to obtain temporary JWT for API key generation."
        fi
        log_info "Successfully obtained temporary JWT."

        # Create a new API key
        local API_KEY_PAYLOAD
        API_KEY_PAYLOAD=$(jq -n --arg pass "$PASSWORD" '{description: "phoenix-cli-key", password: $pass}')
        local API_KEY_RESPONSE
        API_KEY_RESPONSE=$(retry_api_call -X POST -H "Authorization: Bearer ${JWT}" -H "Content-Type: application/json" -d "$API_KEY_PAYLOAD" "${PORTAINER_URL}/api/users/1/tokens")
        API_KEY=$(echo "$API_KEY_RESPONSE" | jq -r '.rawAPIKey // ""')

        if [ -z "$API_KEY" ]; then
            log_fatal "Failed to generate a new Portainer API key."
        fi
        log_success "Successfully generated new Portainer API key."

        # 3. Save the new key back to the configuration file
        log_info "Saving new API key to phoenix_hypervisor_config.json..."
        local temp_config
        temp_config=$(mktemp)
        jq --arg key "$API_KEY" '.portainer_api.api_key = $key' "$HYPERVISOR_CONFIG_FILE" > "$temp_config"
        if ! mv "$temp_config" "$HYPERVISOR_CONFIG_FILE"; then
            log_fatal "Failed to save new API key to configuration file. Please check permissions."
        fi
        log_success "New API key saved successfully."
    fi

    echo "$API_KEY"
}


# =====================================================================================
# Function: ensure_portainer_certificates
# Description: Ensures that a valid TLS certificate for Portainer is generated and
#              in place before the service starts.
# Arguments:
#   $1 - The VMID of the Portainer server.
#   $2 - The persistent volume path on the hypervisor.
#   $3 - The FQDN for the Portainer service.
# Returns:
#   None. Exits with a fatal error if certificate generation fails.
# =====================================================================================
ensure_portainer_certificates() {
    local VMID="$1"
    local persistent_volume_path="$2"
    local portainer_fqdn="$3"
    
    log_info "Ensuring TLS certificates are in place for Portainer on VM ${VMID}..."

    local hypervisor_cert_dir="${persistent_volume_path}/portainer/certs"
    mkdir -p "$hypervisor_cert_dir" || log_fatal "Failed to create Portainer cert directory on hypervisor."

    local cert_file="${hypervisor_cert_dir}/portainer.crt"
    local key_file="${hypervisor_cert_dir}/portainer.key"

    # Idempotency Check: If certs exist and are valid, do nothing.
    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        if openssl x509 -in "$cert_file" -checkend 86400 >/dev/null 2>&1; then
            log_info "Existing Portainer certificate is valid for more than 24 hours. Skipping generation."
            return 0
        else
            log_warn "Existing Portainer certificate is expiring soon or has expired. Generating a new one."
        fi
    fi

    log_info "Requesting new Portainer certificate for ${portainer_fqdn}..."
    
    # Ensure the host's step-cli is bootstrapped
    step ca bootstrap --ca-url "https://10.0.0.10:9000" --fingerprint "$(cat /mnt/pve/quickOS/lxc-persistent-data/103/ssl/root_ca.fingerprint)" --force

    # Dynamically get the IP address for the SAN
    local vm_ip=$(jq_get_vm_value "$VMID" ".network_config.ip" | cut -d'/' -f1)
    if [ -z "$vm_ip" ]; then
        log_fatal "Could not determine IP address for VM ${VMID} to include in certificate SAN."
    fi

    log_info "Generating certificate with SANs for both FQDN (${portainer_fqdn}) and IP (${vm_ip})..."
    if ! step ca certificate "$portainer_fqdn" "$cert_file" "$key_file" --provisioner "admin@thinkheads.ai" --provisioner-password-file "/mnt/pve/quickOS/lxc-persistent-data/103/ssl/provisioner_password.txt" --force --san "$vm_ip"; then
        log_fatal "Failed to obtain Portainer certificate from Step CA."
    fi

    # --- User Requested Validation ---
    log_info "Validating newly generated certificate..."
    openssl x509 -in "$cert_file" -noout -text | grep -A 2 "Validity"
    if ! openssl x509 -in "$cert_file" -checkend 0 >/dev/null 2>&1; then
        log_fatal "Newly generated certificate is already expired!"
    fi
    log_success "Certificate validation passed."
    # --- End Validation ---

    log_success "Portainer TLS certificate generated and placed in ${hypervisor_cert_dir}."

    log_info "Setting ownership of certs directory to root:root for Docker bind mount access..."
    if ! chown -R root:root "$hypervisor_cert_dir"; then
        log_fatal "Failed to set ownership on Portainer certs directory."
    fi
    log_success "Permissions set successfully."
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
    local reset_portainer_flag=${1:-false}
    log_info "Deploying Portainer server and agent instances..."

    local vms_with_portainer
    vms_with_portainer=$(jq -c '.vms[] | select(.portainer_role == "primary" or .portainer_role == "agent")' "$VM_CONFIG_FILE")

    while read -r vm_config; do
        local VMID=$(echo "$vm_config" | jq -r '.vmid')
        local PORTAINER_ROLE=$(echo "$vm_config" | jq -r '.portainer_role')
        local VM_NAME=$(echo "$vm_config" | jq -r '.name')
        # The NFS volume path is no longer needed as we are using local Docker volumes.
        # local persistent_volume_path=$(echo "$vm_config" | jq -r '.volumes[] | select(.type == "nfs") | .path' | head -n 1)
        # local vm_mount_point=$(echo "$vm_config" | jq -r '.volumes[] | select(.type == "nfs") | .mount_point' | head -n 1)
        #
        # if [ -z "$persistent_volume_path" ] || [ -z "$vm_mount_point" ]; then
        #     log_fatal "VM $VMID is configured for Portainer but is missing NFS persistent volume details."
        # fi

        log_info "Processing VM $VMID with Portainer role: $PORTAINER_ROLE"

        case "$PORTAINER_ROLE" in
            primary)
                log_info "Deploying Portainer server on VM $VMID..."
                # Define the path for the compose file inside the VM.
                # We'll use a standard location in the user's home directory.
                local compose_file_path="/home/phoenix_user/portainer/docker-compose.yml"

                # If the reset flag is set, perform a clean wipe using docker compose.
                if [ "$PHOENIX_RESET_PORTAINER" = true ]; then
                    log_warn "--- RESETTING PORTAINER ---"
                    log_info "Forcefully removing Portainer stack and volumes..."
                    # The '-v' flag removes the named volumes associated with the stack.
                    run_qm_command guest exec "$VMID" -- /bin/bash -c "docker stack rm prod_portainer_service" || log_warn "Portainer stack was not running or failed to stop cleanly."
                    log_info "Waiting for stack removal to complete..."
                    sleep 10 # Give the stack time to be removed before deleting the volume
                    log_info "Forcefully removing Portainer data volume to ensure a clean slate..."
                    run_qm_command guest exec "$VMID" -- docker volume rm prod_portainer_service_portainer_data || log_warn "Portainer data volume did not exist or could not be removed."
                    log_info "--- PORTAINER RESET COMPLETE ---"
                fi

                # --- DYNAMIC CERTIFICATE GENERATION ---
                local portainer_fqdn=$(get_global_config_value '.portainer_api.portainer_hostname')
                local hypervisor_cert_dir="/quickOS/vm-persistent-data/1001/portainer/certs"
                ensure_portainer_certificates "$VMID" "/quickOS/vm-persistent-data/1001" "$portainer_fqdn"

                # --- UNIFIED STACK DEPLOYMENT ---
                log_info "Executing unified swarm stack deploy for Portainer server on VM $VMID..."
                if [ "$PHOENIX_DRY_RUN" = "true" ]; then
                    log_info "DRY-RUN: Would execute 'swarm-manager.sh deploy' for portainer_service."
                else
                    if ! "${PHOENIX_BASE_DIR}/bin/managers/swarm-manager.sh" deploy portainer_service --env prod; then
                        log_fatal "Failed to deploy Portainer stack via swarm-manager."
                    fi
                fi
                log_info "Portainer server deployment initiated via Swarm."
                
                # --- BEGIN IMMEDIATE ADMIN SETUP ---
                log_info "Waiting for Portainer API and setting up admin user..."
                local portainer_server_ip=$(get_global_config_value '.network.portainer_server_ip')
                local PORTAINER_URL="http://${portainer_server_ip}:9000"
                setup_portainer_admin_user "$PORTAINER_URL"
                # --- END IMMEDIATE ADMIN SETUP ---
                ;;
            agent)
                log_info "Deploying Portainer agent on VM $VMID..."
                local agent_port=$(get_global_config_value '.network.portainer_agent_port')
                local agent_fqdn=$(echo "$vm_config" | jq -r '.portainer_agent_hostname')
                local persistent_volume_path=$(echo "$vm_config" | jq -r '.volumes[] | select(.type == "nfs") | .path' | head -n 1)

                if [ -z "$agent_fqdn" ]; then
                    log_fatal "VM $VMID is configured as a Portainer agent but is missing the 'portainer_agent_hostname' attribute."
                fi
                if [ -z "$persistent_volume_path" ]; then
                    log_fatal "VM $VMID is configured as a Portainer agent but is missing NFS persistent volume details."
                fi

                # --- DYNAMIC CERTIFICATE GENERATION (Mirrors Server Logic) ---
                log_info "Ensuring TLS certificates are in place for Portainer Agent on VM ${VMID}..."
                local hypervisor_cert_dir="${persistent_volume_path}/portainer-agent/certs"
                mkdir -p "$hypervisor_cert_dir" || log_fatal "Failed to create Portainer Agent cert directory on hypervisor."

                local cert_file="${hypervisor_cert_dir}/agent.crt"
                local key_file="${hypervisor_cert_dir}/agent.key"

                # Idempotency Check
                if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
                    if ! openssl x509 -in "$cert_file" -checkend 86400 >/dev/null 2>&1; then
                         log_warn "Existing Portainer Agent certificate is expiring or invalid. Generating a new one."
                    else
                        log_info "Existing Portainer Agent certificate is valid. Skipping generation."
                    fi
                else
                    log_info "Requesting new Portainer Agent certificate for ${agent_fqdn}..."
                    step ca bootstrap --ca-url "https://10.0.0.10:9000" --fingerprint "$(cat /mnt/pve/quickOS/lxc-persistent-data/103/ssl/root_ca.fingerprint)" --force
                    local vm_ip=$(jq_get_vm_value "$VMID" ".network_config.ip" | cut -d'/' -f1)
                    step ca certificate "$agent_fqdn" "$cert_file" "$key_file" --provisioner "admin@thinkheads.ai" --provisioner-password-file "/mnt/pve/quickOS/lxc-persistent-data/103/ssl/provisioner_password.txt" --force --san "$vm_ip" || log_fatal "Failed to obtain Portainer Agent certificate."
                fi
                
                # --- PREPARE AND PUSH FILES TO VM (Mirrors Server Logic) ---
                log_info "Preparing Portainer Agent files for deployment to VM..."
                local temp_deploy_dir=$(mktemp -d)
                mkdir -p "${temp_deploy_dir}/certs"
                cp "$cert_file" "${temp_deploy_dir}/certs/agent.crt"
                cp "$key_file" "${temp_deploy_dir}/certs/agent.key"
                cp "${CENTRALIZED_CA_CERT_PATH}" "${temp_deploy_dir}/certs/ca.crt" # Add the root CA

                local agent_deploy_path="/home/phoenix_user/portainer-agent"
                log_info "Pushing certificates to VM ${VMID} at ${agent_deploy_path}..."
                run_qm_command guest exec "$VMID" -- mkdir -p "$agent_deploy_path"
                qm_push_dir "$VMID" "$temp_deploy_dir" "$agent_deploy_path" || log_fatal "Failed to push Portainer Agent deployment files to VM ${VMID}."
                log_info "Setting correct ownership on deployment directory in VM..."
                run_qm_command guest exec "$VMID" -- /bin/chown -R phoenix_user:phoenix_user "$agent_deploy_path"
                rm -rf "$temp_deploy_dir"

                # --- DEPLOY AGENT WITH TLS (New Logic) ---
                log_info "Ensuring clean restart for Portainer agent on VM $VMID..."
                run_qm_command guest exec "$VMID" -- /bin/bash -c "docker rm -f portainer_agent" || log_warn "Portainer agent container was not running or failed to remove cleanly."

                log_info "Starting Portainer agent with TLS enabled..."
                local agent_image=$(get_global_config_value '.docker.portainer_agent_image')
                local docker_command="docker run -d -p ${agent_port}:9001 --name portainer_agent --restart=always \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    -v /var/lib/docker/volumes:/var/lib/docker/volumes \
                    -v ${agent_deploy_path}/certs:/certs \
                    -e AGENT_TLS=true \
                    -e AGENT_TLS_CACERT=/certs/ca.crt \
                    -e AGENT_TLS_CERT=/certs/agent.crt \
                    -e AGENT_TLS_KEY=/certs/agent.key \
                    ${agent_image}"

                if [ "$PHOENIX_DRY_RUN" = "true" ]; then
                    log_info "DRY-RUN: Would execute TLS-enabled 'docker run' for Portainer agent on VM $VMID."
                else
                    if ! run_qm_command guest exec "$VMID" -- /bin/bash -c "$docker_command"; then
                        log_fatal "Failed to deploy Portainer agent on VM $VMID."
                    fi
                fi
                log_info "Portainer agent deployment initiated on VM $VMID."

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
#   $1 - The Portainer URL (e.g., https://portainer.internal.thinkheads.ai)
#   $2 - The path to the CA certificate file.
# Returns:
#   None. Exits with a fatal error if admin user setup fails.
# =====================================================================================
setup_portainer_admin_user() {
    local PORTAINER_URL="$1"
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

    log_info "Attempting to create initial admin user '${ADMIN_USERNAME}'..."

    # --- BEGIN RESILIENT WAIT ---
    # Add a loop to wait for the Portainer service to be in a 'Running' state.
    # This prevents a race condition where we try to use the overlay network before it's ready.
    log_info "Waiting for Portainer service to be stable before creating admin user..."
    local service_name="prod_portainer_service_portainer"
    local wait_attempts=0
    local max_wait_attempts=12 # Wait for up to 60 seconds (12 * 5s)
    while [ "$wait_attempts" -lt "$max_wait_attempts" ]; do
        # The 'docker service ps' command is the most reliable way to check the actual state of the task.
        local service_status=$(run_qm_command guest exec 1001 -- /bin/bash -c "docker service ps ${service_name} --format '{{.CurrentState}}' --no-trunc" | tail -n 1)
        if [[ "$service_status" == "Running "* ]]; then
            log_success "Portainer service is stable and running."
            break
        fi
        log_info "Portainer service not yet stable (Current State: ${service_status}). Waiting 5 seconds..."
        sleep 5
        wait_attempts=$((wait_attempts + 1))
    done

    if [ "$wait_attempts" -ge "$max_wait_attempts" ]; then
        log_error "Timeout reached while waiting for Portainer service to become stable."
        log_error "--- Last known service status ---"
        run_qm_command guest exec 1001 -- /bin/bash -c "docker service ps ${service_name} --no-trunc"
        log_error "--- Portainer service logs ---"
        run_qm_command guest exec 1001 -- /bin/bash -c "docker service logs ${service_name}"
        log_fatal "Portainer service failed to start. Please review the logs above."
    fi
    # --- END RESILIENT WAIT ---

    while [ "$attempt" -le "$MAX_RETRIES" ]; do
        log_info "Admin user creation attempt ${attempt}/${MAX_RETRIES}..."
        
        local response
        local http_status
        
        # --- BEGIN DIRECT HOST EXECUTION (REMEDIATED) ---
        # The Portainer service exposes port 9000 on the host VM. We can curl it directly
        # from within the VM. This version uses a heredoc to create a clean, unescaped
        # command string, which is then executed by bash -c. This is the most robust way
        # to handle the nested quotes and special characters.
        local qm_response
        local container_id=$(run_qm_command guest exec 1001 -- /bin/bash -c "docker ps -q --filter 'name=prod_portainer_service_portainer'")
        
        # --- THE DEFINITIVE FIX ---
        # The API call is now made from the Proxmox host, which has the root CA installed
        # and can resolve the internal DNS name. This is the correct and simplest approach.
        local PORTAINER_FQDN=$(get_global_config_value '.portainer_api.portainer_hostname')
        local API_ENDPOINT="https://${PORTAINER_FQDN}/api/users/admin/init"
        local PAYLOAD
        PAYLOAD=$(jq -n --arg user "$ADMIN_USERNAME" --arg pass "$ADMIN_PASSWORD" '{Username: $user, Password: $pass}')

        response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
            -X POST \
            -H "Content-Type: application/json" \
            --data "$PAYLOAD" \
            --cacert "${CENTRALIZED_CA_CERT_PATH}" \
            "$API_ENDPOINT")
        
        http_status=$(echo -e "$response" | tail -n1 | sed -n 's/.*HTTP_STATUS://p')
        body=$(echo -e "$response" | sed '$d')
        # --- END DEFINITIVE FIX ---

        log_debug "Admin creation response body: ${body}"
        log_debug "Admin creation HTTP status: ${http_status}"

        if [[ "$http_status" -eq 200 ]]; then
            log_success "Portainer admin user '${ADMIN_USERNAME}' created successfully."
            log_info "Waiting for 10 seconds for Portainer to fully initialize before proceeding..."
            sleep 10
            return 0
        elif [[ "$http_status" -eq 409 ]]; then
            log_info "Portainer admin user already exists. Skipping creation."
            return 0
        else
            log_warn "Failed to create Portainer admin user (HTTP: ${http_status}). Retrying in ${RETRY_DELAY} seconds..."
            log_warn "Response: ${body}"
        fi

        sleep "$RETRY_DELAY"
        attempt=$((attempt + 1))
    done

    log_fatal "Failed to create or verify Portainer admin user after ${MAX_RETRIES} attempts. The service may be unhealthy."
}

# =====================================================================================
# Function: ensure_swarm_manager_active
# Description: A resilient function to check if the designated manager node is actively
#              leading the Swarm. If it's in a zombie state after a restart, this
#              function will force it to re-assert its leadership.
# =====================================================================================
ensure_swarm_manager_active() {
    log_info "--- Ensuring Swarm Manager is Active and Leading ---"
    local manager_vmid=$(jq -r '.vms[] | select(.swarm_role == "manager") | .vmid' "$VM_CONFIG_FILE")
    if [ -z "$manager_vmid" ]; then
        log_fatal "No VM with swarm_role 'manager' found in vm_configs.json."
    fi

    # Check the node's self-reported status.
    local is_manager=$(run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "docker info --format '{{.Swarm.ControlAvailable}}'")

    if [[ "$is_manager" == "true" ]]; then
        log_info "VM ${manager_vmid} correctly identifies as an active Swarm manager."
    else
        log_warn "VM ${manager_vmid} is not an active Swarm manager. This can happen after a daemon restart. Forcing re-initialization..."
        local manager_ip=$(jq_get_vm_value "$manager_vmid" ".network_config.ip" | cut -d'/' -f1)
        
        # The --force-new-cluster flag is critical. It tells the node to become the manager
        # of a new cluster, but because the Swarm state is preserved on disk, it effectively
        # re-asserts leadership over the *existing* cluster.
        run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "docker swarm init --force-new-cluster --advertise-addr ${manager_ip}"
        log_success "Successfully re-initialized Swarm leadership on VM ${manager_vmid}."
    fi
}

# =====================================================================================
# Function: ensure_swarm_cluster_active
# Description: Checks if the Docker Swarm is active and initializes it if not.
#              It also ensures all worker nodes are joined to the cluster.
# =====================================================================================
ensure_swarm_cluster_active() {
    log_info "--- Ensuring Docker Swarm Cluster is Active ---"
    
    # First, ensure the manager is in a healthy, leading state.
    ensure_swarm_manager_active

    local manager_vmid=$(jq -r '.vms[] | select(.swarm_role == "manager") | .vmid' "$VM_CONFIG_FILE")
    if [ -z "$manager_vmid" ]; then
        log_fatal "No VM with swarm_role 'manager' found in vm_configs.json."
    fi

    # Ensure all worker nodes are joined
    local worker_vmids=$(jq -r '.vms[] | select(.swarm_role == "worker") | .vmid' "$VM_CONFIG_FILE")
    for worker_vmid in $worker_vmids; do
        local worker_hostname=$(jq_get_vm_value "$worker_vmid" ".name")
        log_info "Checking status of worker node ${worker_hostname} (VM ${worker_vmid})..."
        
        # Check if the node is already in the swarm
        local node_status=$(run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "docker node ls --filter \"name=${worker_hostname}\" --format '{{.Status}}'")
        
        if [[ "$node_status" == "Ready" ]]; then
            log_info "Worker node ${worker_hostname} is already part of the swarm and ready."
        else
            log_warn "Worker node ${worker_hostname} is not ready or not in the swarm. Attempting to join..."
            if ! "${PHOENIX_BASE_DIR}/bin/managers/swarm-manager.sh" join "$worker_vmid"; then
                log_fatal "Failed to join worker node ${worker_hostname} (VM ${worker_vmid}) to the swarm."
            fi
        fi
    done

    log_success "Docker Swarm cluster is active and all nodes are joined."
}

# =====================================================================================
# Function: sync_stack_files
# Description: Synchronizes the local stack definition files to the shared ZFS dataset
#              so they are available for Portainer to use.
# =====================================================================================
sync_stack_files() {
    log_info "--- Syncing stack files to shared ZFS dataset ---"
    local source_dir="${PHOENIX_BASE_DIR}/stacks/"
    local dest_dir="/quickOS/portainer_stacks/"

    if [ ! -d "$source_dir" ]; then
        log_warn "Source stacks directory not found at ${source_dir}. Skipping sync."
        return
    fi

    # Ensure the destination directory exists.
    if ! mkdir -p "$dest_dir"; then
        log_fatal "Failed to create destination directory for stacks: ${dest_dir}"
    fi

    # Use rsync to efficiently synchronize the files. The --delete flag ensures that
    # stacks removed from the git repo are also removed from the shared volume.
    if ! rsync -av --delete "$source_dir" "$dest_dir"; then
        log_fatal "Failed to rsync stack files from ${source_dir} to ${dest_dir}"
    fi

    log_success "Stack files synchronized successfully to ${dest_dir}."
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
    export PHOENIX_RESET_PORTAINER=${1:-false}
    log_info "--- Starting Full System State Synchronization ---"

    # --- NEW STAGE 0: Sync Stack Files & Ensure Permissions ---
    sync_stack_files
    log_info "Ensuring correct permissions on stacks directory..."
    chmod -R 777 /quickOS/portainer_stacks/ || log_fatal "Failed to set permissions on /quickOS/portainer_stacks/"

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

    # --- FIX: Ensure firewall rules are always synchronized ---
    log_info "Synchronizing firewall configuration..."
    if ! "${PHOENIX_BASE_DIR}/bin/hypervisor_setup/hypervisor_feature_setup_firewall.sh" "$HYPERVISOR_CONFIG_FILE"; then
        log_fatal "Firewall synchronization failed. Aborting."
    fi
    log_success "Firewall configuration synchronized."

    # --- FIX: Ensure firewall rules are always synchronized ---
    log_info "Synchronizing firewall configuration..."
    if ! "${PHOENIX_BASE_DIR}/bin/hypervisor_setup/hypervisor_feature_setup_firewall.sh" "$HYPERVISOR_CONFIG_FILE"; then
        log_fatal "Firewall synchronization failed. Aborting."
    fi
    log_success "Firewall configuration synchronized."
    
    # --- NEW: Run Certificate Manager ---
    log_info "Running certificate renewal manager to ensure all certificates are up to date..."
    if ! "${PHOENIX_BASE_DIR}/bin/managers/certificate-renewal-manager.sh" --force; then
        log_fatal "Certificate renewal manager failed. Aborting."
    fi
    log_success "Certificate renewal manager completed successfully."

    # --- STAGE 2: ENSURE SWARM CLUSTER IS ACTIVE ---
    log_info "--- Stage 2: Ensuring Docker Swarm Cluster is Active ---"
    ensure_swarm_cluster_active

    # --- STAGE 3: DEPLOY & VERIFY UPSTREAM SERVICES ---
    log_info "--- Stage 3: Deploying and Verifying Portainer ---"
    local portainer_vmid="1001"
    if qm status "$portainer_vmid" > /dev/null 2>&1; then
        log_info "Portainer VM (1001) is running. Proceeding with deployment."
        deploy_portainer_instances "$reset_portainer_on_sync"
    else
        log_warn "Portainer VM (1001) is not running. Skipping all subsequent stages."
        log_info "--- Full System State Synchronization Finished (Aborted) ---"
        return
    fi

    # --- STAGE 4: CONFIGURE SERVICE MESH ---
    log_info "--- Stage 4: Synchronizing Traefik Proxy ---"
    local traefik_ctid="102"
    if pct status "$traefik_ctid" > /dev/null 2>&1; then
        log_info "Traefik container (102) is running. Generating and applying configuration."
        if ! "${PHOENIX_BASE_DIR}/bin/generate_traefik_config.sh"; then
            log_fatal "Failed to generate Traefik configuration."
        fi
        if ! pct push "$traefik_ctid" "${PHOENIX_BASE_DIR}/etc/traefik/dynamic_conf.yml" /etc/traefik/dynamic/dynamic_conf.yml; then
            log_fatal "Failed to push Traefik dynamic config to container 102."
        else
            log_success "Successfully pushed Traefik dynamic config to container 102."
        fi
        pct exec "$traefik_ctid" -- chmod 644 /etc/traefik/dynamic/dynamic_conf.yml
        if ! pct exec "$traefik_ctid" -- systemctl reload traefik; then
            log_warn "Failed to reload Traefik service. A restart may be required." "pct exec 102 -- journalctl -u traefik -n 50"
        fi
        log_success "Traefik synchronization complete."
    else
        log_warn "Traefik container (102) is not running. Skipping Traefik synchronization."
    fi

    # --- STAGE 5: CONFIGURE GATEWAY ---
    log_info "--- Stage 5: Synchronizing NGINX Gateway ---"
    log_info "Generating and applying dynamic NGINX gateway configuration..."
    if ! "${PHOENIX_BASE_DIR}/bin/generate_nginx_gateway_config.sh"; then
        log_fatal "Failed to generate dynamic NGINX configuration."
    fi
    # --- BEGIN ROBUST NGINX CONFIGURATION ---
    log_info "Attempting to push NGINX gateway config to container 101..."
    local gateway_config_src="${PHOENIX_BASE_DIR}/etc/nginx/sites-available/gateway"
    local gateway_config_dest="/etc/nginx/sites-available/gateway"
    
    if output=$(pct push 101 "$gateway_config_src" "$gateway_config_dest" 2>&1); then
        log_success "Successfully pushed NGINX gateway config."
    else
        log_fatal "Failed to push NGINX gateway config. Exit code: $?. Output: $output"
    fi

    log_info "Attempting to create symbolic link for NGINX gateway site..."
    if output=$(pct exec 101 -- ln -sf "$gateway_config_dest" /etc/nginx/sites-enabled/gateway 2>&1); then
        log_success "Successfully created NGINX gateway symlink."
    else
        log_fatal "Failed to create NGINX gateway symlink. Exit code: $?. Output: $output"
    fi

    log_info "Attempting to reload Nginx in container 101..."
    if output=$(pct exec 101 -- systemctl reload nginx 2>&1); then
        log_success "Nginx reloaded successfully."
    else
        log_error "Failed to reload Nginx. Exit code: $?. Output: $output"
        log_info "Dumping Nginx journal for debugging..."
        pct exec 101 -- journalctl -u nginx -n 50 --no-pager
        log_fatal "NGINX reload failed. Please review the logs above."
    fi
    # --- END ROBUST NGINX CONFIGURATION ---
    log_success "NGINX gateway configuration applied and reloaded successfully."

    # --- BEGIN DEFINITIVE VERIFICATION ---
    log_info "Verifying Nginx listener on port 443 inside container 101..."
    local nginx_check_retries=10
    local nginx_check_delay=3
    local nginx_check_attempt=1
    while [ "$nginx_check_attempt" -le "$nginx_check_retries" ]; do
        if pct exec 101 -- ss -tuln | grep -q ':443'; then
            log_success "Nginx is listening on port 443."
            break
        fi
        log_warn "Nginx is not yet listening on port 443. Retrying in ${nginx_check_delay} seconds... (Attempt ${nginx_check_attempt}/${nginx_check_retries})"
        sleep "$nginx_check_delay"
        nginx_check_attempt=$((nginx_check_attempt + 1))
    done

    if [ "$nginx_check_attempt" -gt "$nginx_check_retries" ]; then
        log_fatal "Nginx failed to start listening on port 443 after multiple retries. Aborting."
    fi
    # --- END DEFINITIVE VERIFICATION ---

    # --- STAGE 6: SETUP PORTAINER ADMIN AND SYNCHRONIZE STACKS ---
    log_info "--- Stage 6: Setting up Portainer Admin and Synchronizing Stacks ---"
    # --- FIX: Proactively restart Portainer to avoid security timeout before API calls ---
    log_info "Proactively restarting Portainer container to reset security timeout..."
    run_qm_command guest exec "$portainer_vmid" -- /bin/bash -c "docker restart portainer_server" || log_warn "Failed to restart Portainer container. It may not have been running."
    log_info "Waiting for Portainer to initialize after restart..."
    sleep 15 # Give Portainer ample time to initialize after restart

    # DEPRECATED: The following block for endpoint and stack synchronization is
    #             now handled manually via the Portainer UI. See the new
    #             manual_deployment_guide.md for the updated workflow.
    #
    # local API_KEY=$(get_or_create_portainer_api_key)
    # if [ -z "$API_KEY" ]; then
    #     log_fatal "Failed to get Portainer API Key. Aborting stack synchronization."
    # fi
    #
    # sync_portainer_endpoints "$API_KEY"
    #
    # log_info "Discovering all available Docker stacks..."
    # ... (rest of the block commented out) ...
    # log_info "--- Docker stack synchronization complete ---"

    # --- STAGE 7: SYNCHRONIZE APPLICATION STACKS ---
    sync_application_stacks

    # --- FINAL HEALTH CHECK ---
    # wait_for_system_ready

    log_info "--- Full System State Synchronization Finished ---"
}

# =====================================================================================
# Function: sync_stack
# DEPRECATED: This function is deprecated in favor of the new UI-driven workflow.
#             Application stacks are now deployed manually via the Portainer UI
#             using the shared /stacks volume. See manual_deployment_guide.md.
# =====================================================================================
# sync_stack() {
#     ... (code commented out) ...
# }

# =====================================================================================
# Function: sync_application_stacks
# Description: Automatically deploys all Docker stacks defined in the `docker_stacks`
#              array of the VM configurations.
# =====================================================================================
sync_application_stacks() {
    log_info "--- Stage 6: Synchronizing Application Stacks ---"

    local vm_configs=$(jq -c '.vms[] | select(.docker_stacks and (.docker_stacks | length > 0))' "$VM_CONFIG_FILE")

    if [ -z "$vm_configs" ]; then
        log_info "No VMs with 'docker_stacks' defined. Skipping application stack deployment."
        return 0
    fi

    while read -r vm_config; do
        local vm_name=$(echo "$vm_config" | jq -r '.name')
        local stacks=$(echo "$vm_config" | jq -r '.docker_stacks[]')

        for stack_name in $stacks; do
            log_info "Deploying stack '${stack_name}' as defined in VM '${vm_name}'..."
            # We assume 'prod' environment for now, as per the current design.
            # This can be parameterized in the future if needed.
            if ! "${PHOENIX_BASE_DIR}/bin/managers/swarm-manager.sh" deploy "$stack_name" --env prod; then
                log_warn "Failed to deploy stack '${stack_name}'. Please check the logs for details."
            else
                log_success "Successfully initiated deployment for stack '${stack_name}'."
            fi
        done
    done <<< "$vm_configs"

    log_info "--- Application stack synchronization complete ---"
}

# =====================================================================================
# Function: sync_portainer_endpoints
# DEPRECATED: This function is deprecated in favor of the new UI-driven workflow.
#             Endpoints are now added manually via the Portainer UI.
#             See manual_deployment_guide.md.
# =====================================================================================
# sync_portainer_endpoints() {
#     ... (code commented out) ...
# }

# =====================================================================================
# Function: main_portainer_orchestrator
# Description: The main entry point for the Portainer manager script. It parses the
#              action and arguments, and then executes the appropriate operations.
# Arguments:
#   $@ - The command-line arguments passed to the script.
# =====================================================================================
main_portainer_orchestrator() {
    local action=""
    local args=()
    local config_file_override=""
    local reset_portainer=false

    # First, parse all flags
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --config)
                config_file_override="$2"
                shift 2
                ;;
            --reset-portainer)
                reset_portainer=true
                shift
                ;;
            *)
                # Assume first non-flag is the action
                if [ -z "$action" ]; then
                    action="$1"
                else
                    args+=("$1")
                fi
                shift
                ;;
        esac
    done

    if [ -n "$config_file_override" ]; then
        export HYPERVISOR_CONFIG_FILE="$config_file_override"
        log_debug "HYPERVISOR_CONFIG_FILE overridden to: $HYPERVISOR_CONFIG_FILE"
    fi

    case "$action" in
        sync)
            local target="${args[0]}"
            if [ "$target" == "all" ]; then
                sync_all "$reset_portainer"
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