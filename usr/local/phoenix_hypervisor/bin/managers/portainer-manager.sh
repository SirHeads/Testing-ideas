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
source "${PHOENIX_BASE_DIR}/bin/managers/vm-manager.sh"

# --- NEW: Wrapper for Docker commands in VM 1001 ---
run_docker_command_in_vm() {
    local vmid="$1"
    shift
    local docker_command="$@"
    # The DOCKER_HOST export has been removed.
    # The command will now rely on the default Docker context ('phoenix') inside the VM,
    # which is configured for secure mTLS communication.
    run_qm_command guest exec "$vmid" -- /bin/bash -c "${docker_command}"
}

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
        status_response=$(curl -s --cacert "${CENTRALIZED_CA_CERT_PATH}" -H "X-API-Key: ${API_KEY}" "${PORTAINER_URL}/api/system/status")
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
        JWT_RESPONSE=$(retry_api_call --cacert "${CENTRALIZED_CA_CERT_PATH}" -X POST -H "Content-Type: application/json" -d "$AUTH_PAYLOAD" "${PORTAINER_URL}/api/auth")
        local JWT=$(echo "$JWT_RESPONSE" | jq -r '.jwt // ""')

        if [ -z "$JWT" ]; then
            log_fatal "Failed to obtain temporary JWT for API key generation."
        fi
        log_info "Successfully obtained temporary JWT."

        # Create a new API key
        local API_KEY_PAYLOAD
        API_KEY_PAYLOAD=$(jq -n --arg pass "$PASSWORD" '{description: "phoenix-cli-key", password: $pass}')
        local API_KEY_RESPONSE
        API_KEY_RESPONSE=$(retry_api_call --cacert "${CENTRALIZED_CA_CERT_PATH}" -X POST -H "Authorization: Bearer ${JWT}" -H "Content-Type: application/json" -d "$API_KEY_PAYLOAD" "${PORTAINER_URL}/api/users/1/tokens")
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
                    run_docker_command_in_vm "$VMID" "docker stack rm prod_portainer_service" || log_warn "Portainer stack was not running or failed to stop cleanly."
                    log_info "Waiting for stack removal to complete..."
                    sleep 10 # Give the stack time to be removed before deleting the volume
                    log_info "Forcefully removing Portainer data volume to ensure a clean slate..."
                    run_docker_command_in_vm "$VMID" "docker volume rm prod_portainer_service_portainer_data" || log_warn "Portainer data volume did not exist or could not be removed."
                    log_info "--- PORTAINER RESET COMPLETE ---"
                fi

                # --- DYNAMIC CERTIFICATE GENERATION ---
                # This is now handled by the centralized certificate-renewal-manager

                # --- UNIFIED STACK DEPLOYMENT ---
                log_info "Executing unified swarm stack deploy for Portainer server on VM $VMID..."
                if [ "$PHOENIX_DRY_RUN" = "true" ]; then
                    log_info "DRY-RUN: Would execute 'swarm-manager.sh deploy' for portainer_service."
                else
                    if ! "${PHOENIX_BASE_DIR}/bin/managers/swarm-manager.sh" deploy portainer_service --env production; then
                        log_fatal "Failed to deploy Portainer stack via swarm-manager."
                    fi
                fi
                log_info "Portainer server deployment initiated via Swarm."
                
                # The immediate admin setup has been moved to Stage 6 of the sync_all command
                # to ensure the network gateway is ready before the API is called.
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
                    if ! run_docker_command_in_vm "$VMID" "$docker_command"; then
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
# Function: ensure_portainer_admin_secret
# Description: Ensures the Docker Swarm secret for the Portainer admin password exists.
#              If it doesn't exist, it creates it using the password from the config file.
# =====================================================================================
ensure_portainer_admin_secret() {
    log_info "--- Ensuring Portainer admin password secret exists in Docker Swarm ---"
    local secret_name="portainer_admin_password"
    local manager_vmid=$(jq -r '.vms[] | select(.swarm_role == "manager") | .vmid' "$VM_CONFIG_FILE")
    local admin_password=$(get_global_config_value '.portainer_api.admin_password')

    if [ -z "$admin_password" ] || [ "$admin_password" == "null" ]; then
        log_fatal "Portainer admin password is not set in phoenix_hypervisor_config.json."
    fi

    # Check if the secret already exists inside the Swarm manager VM
    local secret_exists_output
    secret_exists_output=$(run_docker_command_in_vm "$manager_vmid" "docker secret ls --filter name=${secret_name} -q")

    if [ -z "$secret_exists_output" ]; then
        log_info "Secret '${secret_name}' not found. Creating it now..."
        # Create the secret by piping the password directly to the command
        if ! run_docker_command_in_vm "$manager_vmid" "printf '%s' '${admin_password}' | docker secret create ${secret_name} -"; then
            log_fatal "Failed to create Docker Swarm secret '${secret_name}'."
        fi
        log_success "Docker Swarm secret '${secret_name}' created successfully."
    else
        log_info "Secret '${secret_name}' already exists. Skipping creation."
    fi
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
    local is_manager=$(run_docker_command_in_vm "$manager_vmid" "docker info --format '{{.Swarm.ControlAvailable}}'")

    if [[ "$is_manager" == "true" ]]; then
        log_info "VM ${manager_vmid} correctly identifies as an active Swarm manager."
    else
        log_warn "VM ${manager_vmid} is not an active Swarm manager. This can happen after a daemon restart. Forcing re-initialization..."
        local manager_ip=$(jq_get_vm_value "$manager_vmid" ".network_config.ip" | cut -d'/' -f1)
        
        # The --force-new-cluster flag is critical. It tells the node to become the manager
        # of a new cluster, but because the Swarm state is preserved on disk, it effectively
        # re-asserts leadership over the *existing* cluster.
        run_docker_command_in_vm "$manager_vmid" "docker swarm init --force-new-cluster --advertise-addr ${manager_ip}"
        log_success "Successfully re-initialized Swarm leadership on VM ${manager_vmid}."
    fi

    log_info "--- Ensuring Docker socket is exposed over TCP ---"
    local docker_proxy_script="${PHOENIX_BASE_DIR}/bin/vm_features/feature_install_docker_proxy.sh"
    if [ ! -f "$docker_proxy_script" ]; then
        log_fatal "Docker proxy feature script not found at $docker_proxy_script."
    fi
    if ! run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "$(cat "$docker_proxy_script")"; then
        log_fatal "Failed to execute Docker proxy feature script on VM $manager_vmid."
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
        local node_status=$(run_docker_command_in_vm "$manager_vmid" "docker node ls --filter \"name=${worker_hostname}\" --format '{{.Status}}'")
        
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

    # --- STAGE 1: INFRASTRUCTURE PREPARATION ---
    log_info "--- Stage 1: Preparing Infrastructure (Files, DNS, Firewall) ---"
    sync_stack_files
    log_info "Ensuring correct permissions on stacks directory..."
    chmod -R 777 /quickOS/portainer_stacks/ || log_fatal "Failed to set permissions on /quickOS/portainer_stacks/"

    log_info "Ensuring Step-CA root certificate is present on the Proxmox host..."
    if ! "${PHOENIX_BASE_DIR}/bin/hypervisor_setup/hypervisor_feature_install_trusted_ca.sh"; then
        log_fatal "Failed to install trusted CA on the host. Aborting."
    fi

    log_info "Synchronizing DNS server configuration..."
    if ! "${PHOENIX_BASE_DIR}/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh"; then
        log_fatal "DNS synchronization failed. Aborting."
    fi

    log_info "Synchronizing firewall configuration..."
    if ! "${PHOENIX_BASE_DIR}/bin/hypervisor_setup/hypervisor_feature_setup_firewall.sh" "$HYPERVISOR_CONFIG_FILE"; then
        log_fatal "Firewall synchronization failed. Aborting."
    fi
    log_success "Infrastructure preparation complete."


    # --- STAGE 2: SWARM INITIALIZATION ---
    log_info "--- Stage 2: Ensuring Docker Swarm Cluster is Active ---"
    ensure_swarm_cluster_active
    log_info "--- Ensuring Traefik overlay network exists ---"
    local manager_vmid=$(jq -r '.vms[] | select(.swarm_role == "manager") | .vmid' "$VM_CONFIG_FILE")
    if ! run_docker_command_in_vm "$manager_vmid" "docker network inspect traefik-public > /dev/null 2>&1"; then
        log_info "Traefik overlay network not found. Creating it now..."
        run_docker_command_in_vm "$manager_vmid" "docker network create --driver overlay --attachable traefik-public" || log_fatal "Failed to create Traefik overlay network."
    fi
    ensure_portainer_admin_secret
    log_success "Docker Swarm is active and configured."


    # --- STAGE 3: CERTIFICATE GENERATION & DISTRIBUTION ---
    log_info "--- Stage 3: Generating and Distributing All Certificates ---"
    if ! "${PHOENIX_BASE_DIR}/bin/managers/certificate-renewal-manager.sh" --force; then
        log_fatal "Centralized certificate generation and distribution failed. Aborting sync."
    fi
    log_success "All certificates generated and distributed successfully."


    # --- STAGE 4: DEPLOY & VERIFY UPSTREAM SERVICES ---
    log_info "--- Stage 4: Deploying and Verifying Portainer ---"
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

        # --- BEGIN PHOENIX-TRAEFIK-FIX ---
        # Push the corrected static configuration before the dynamic one.
        log_info "Pushing updated static Traefik configuration..."
        if ! pct push "$traefik_ctid" "${PHOENIX_BASE_DIR}/etc/traefik/traefik.yml.template" /etc/traefik/traefik.yml; then
            log_fatal "Failed to push Traefik static config to container 102."
        else
            log_success "Successfully pushed Traefik static config to container 102."
        fi
        # --- END PHOENIX-TRAEFIK-FIX ---

        if ! "${PHOENIX_BASE_DIR}/bin/generate_traefik_config.sh"; then
            log_fatal "Failed to generate Traefik configuration."
        fi
        if ! pct push "$traefik_ctid" "${PHOENIX_BASE_DIR}/etc/traefik/dynamic_conf.yml" /etc/traefik/dynamic/dynamic_conf.yml; then
            log_fatal "Failed to push Traefik dynamic config to container 102."
        fi
        pct exec "$traefik_ctid" -- chmod 644 /etc/traefik/dynamic/dynamic_conf.yml
        
        # --- BEGIN PHOENIX-TRAEFIK-FIX ---
        # Use start instead of restart to ensure the service is started for the first time.
        log_info "Starting Traefik to apply new static configuration..."
        if ! pct exec "$traefik_ctid" -- systemctl start traefik; then
            log_warn "Failed to start Traefik service. Check the logs for errors." "pct exec 102 -- journalctl -u traefik -n 50"
        else
            log_success "Traefik service started successfully."
        fi
        # --- END PHOENIX-TRAEFIK-FIX ---
        
        log_success "Traefik synchronization complete."
    else
        log_warn "Traefik container (102) is not running. Skipping Traefik synchronization."
    fi

    # --- STAGE 5: CONFIGURE GATEWAY ---
    # --- STAGE 5: CONFIGURE GATEWAY ---
    log_info "--- Stage 5: Synchronizing NGINX Gateway ---"
    local nginx_ctid="101"
    if pct status "$nginx_ctid" > /dev/null 2>&1; then
        log_info "Nginx container (101) is running. Applying gateway configuration."

        # 1. Write the HTTP gateway config to sites-available and enable it
        local http_config_source="${PHOENIX_BASE_DIR}/etc/nginx/sites-available/gateway"
        local http_config_dest="/etc/nginx/sites-available/gateway"
        log_info "Writing HTTP gateway config to ${http_config_dest}..."
        if ! cat "${http_config_source}" | pct exec "${nginx_ctid}" -- tee "${http_config_dest}" > /dev/null; then
            log_fatal "Failed to write Nginx HTTP config to container 101."
        fi
        
        log_info "Enabling gateway site..."
        pct exec "${nginx_ctid}" -- ln -sf /etc/nginx/sites-available/gateway /etc/nginx/sites-enabled/

        # 2. Write the TCP stream config directly to stream.d
        local stream_config_source="${PHOENIX_BASE_DIR}/etc/nginx/stream.d/stream-gateway.conf"
        local stream_config_dest="/etc/nginx/stream.d/stream-gateway.conf"
        log_info "Writing TCP stream config to ${stream_config_dest}..."
        if ! cat "${stream_config_source}" | pct exec "${nginx_ctid}" -- tee "${stream_config_dest}" > /dev/null; then
            log_fatal "Failed to write Nginx stream config to container 101."
        fi

        # 3. Remove the placeholder default config (from sites-enabled and conf.d just in case)
        log_info "Removing placeholder default configuration..."
        pct exec "$nginx_ctid" -- rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf

        # 4. Test and reload Nginx inside the container
        if ! pct exec "$nginx_ctid" -- nginx -t; then
            log_fatal "Nginx configuration test failed inside container 101."
        fi
        if ! pct exec "$nginx_ctid" -- systemctl reload nginx; then
            log_fatal "Failed to reload Nginx inside container 101."
        fi
        log_success "NGINX gateway configuration applied and reloaded successfully."
    else
        log_warn "Nginx container (101) is not running. Skipping Nginx synchronization."
    fi

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
    # --- STAGE 6: SETUP PORTAINER ADMIN AND SYNCHRONIZE STACKS ---
    log_info "--- Stage 6: Setting up Portainer Admin and Synchronizing Stacks ---"
    
    # With the gateway now confirmed to be active, we can safely set up the admin user.
    log_info "Setting up Portainer admin user..."
    local portainer_server_ip=$(get_global_config_value '.network.portainer_server_ip')
    local PORTAINER_URL="http://${portainer_server_ip}:9000"
    # setup_portainer_admin_user "$PORTAINER_URL" - This is now handled by the Docker secret

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
            if ! "${PHOENIX_BASE_DIR}/bin/managers/swarm-manager.sh" deploy "$stack_name" --env production; then
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