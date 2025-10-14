#!/bin/bash
#
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
VM_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_vm_configs.json"
STACKS_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_stacks_config.json"
# =====================================================================================
# Function: get_portainer_jwt
# Description: Authenticates with the Portainer API and retrieves a JWT.
#
# Returns:
#   The JWT on success, or exits with a fatal error on failure.
# =====================================================================================
get_portainer_jwt() {
    log_info "Attempting to authenticate with Portainer API..."
    local PORTAINER_HOSTNAME=$(get_global_config_value '.portainer_api.portainer_hostname')
    local PORTAINER_PORT=$(get_global_config_value '.network.portainer_server_port')
    local PORTAINER_URL="https://${PORTAINER_HOSTNAME}:${PORTAINER_PORT}"
    local USERNAME=$(get_global_config_value '.portainer_api.admin_user')
    local PASSWORD=$(get_global_config_value '.portainer_api.admin_password')
    local CA_CERT_PATH="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_ca.crt"

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
    local MAX_RETRIES=10
    local RETRY_DELAY=5
    local attempt=1

    while [ -z "$JWT" ] && [ "$attempt" -le "$MAX_RETRIES" ]; do
        log_info "Authentication attempt ${attempt}/${MAX_RETRIES}..."
        JWT_RESPONSE=$(curl -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/auth" \
          -H "Content-Type: application/json" \
          -d "${AUTH_PAYLOAD}")
        
        log_debug "Raw JWT API response (attempt ${attempt}): ${JWT_RESPONSE}"
        JWT=$(echo "$JWT_RESPONSE" | jq -r '.jwt // ""')

        if [ -z "$JWT" ]; then
            log_warn "Authentication failed on attempt ${attempt}. Retrying in ${RETRY_DELAY} seconds. Response: ${JWT_RESPONSE}"
            sleep "$RETRY_DELAY"
            attempt=$((attempt + 1))
        fi
    done

    if [ -z "$JWT" ]; then
      log_fatal "Failed to authenticate with Portainer API after ${MAX_RETRIES} attempts. Check credentials and SSL certificate. Last response: ${JWT_RESPONSE}"
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
    log_info "Deploying Portainer server and agent instances..."

    # Check for yq and install if not found
    if ! command -v yq &> /dev/null; then
        log_info "yq not found. Attempting to install yq..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            # For Debian/Ubuntu-based systems
            sudo apt-get update && sudo apt-get install -y yq || log_fatal "Failed to install yq. Please install yq manually."
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            # For macOS
            brew install yq || log_fatal "Failed to install yq. Please install yq manually (brew install yq)."
        else
            log_fatal "Unsupported OS for automatic yq installation. Please install yq manually."
        fi
    fi

    local vms_with_portainer
    vms_with_portainer=$(jq -c '.vms[] | select(.portainer_role == "primary" or .portainer_role == "agent")' "$VM_CONFIG_FILE")

    echo "$vms_with_portainer" | jq -c '.' | while read -r vm_config; do
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

                # Copy the docker-compose.yml from the source of truth to the hypervisor's NFS share
                log_info "Copying Portainer docker-compose.yml to hypervisor's NFS share: ${hypervisor_portainer_dir}/docker-compose.yml"
                cp "${PHOENIX_BASE_DIR}/persistent-storage/portainer/docker-compose.yml" "${hypervisor_portainer_dir}/docker-compose.yml" || log_fatal "Failed to copy docker-compose.yml to hypervisor's NFS share."

                # Copy the Dockerfile and phoenix_ca.crt to the build context on the hypervisor's NFS share
                log_info "Copying Dockerfile and phoenix_ca.crt to hypervisor's NFS share for image build."
                cp "${PHOENIX_BASE_DIR}/persistent-storage/portainer/Dockerfile" "${hypervisor_portainer_dir}/Dockerfile" || log_fatal "Failed to copy Dockerfile to NFS share."
                cp "${PHOENIX_BASE_DIR}/persistent-storage/ssl/phoenix_ca.crt" "${hypervisor_portainer_dir}/phoenix_ca.crt" || log_fatal "Failed to copy phoenix_ca.crt to NFS share."

                # Build the custom Portainer image inside VM 1001
                log_info "Building custom Portainer image 'portainer-ce-custom:latest' inside VM $VMID..."
                if ! run_qm_command guest exec "$VMID" -- /bin/bash -c "cd ${vm_mount_point}/portainer && docker build -t portainer-ce-custom:latest ."; then
                    log_fatal "Failed to build custom Portainer image inside VM $VMID."
                fi
                log_success "Custom Portainer image 'portainer-ce-custom:latest' built successfully inside VM $VMID."

                # Dynamically update the docker-compose.yml to use the custom image
                log_info "Updating docker-compose.yml to use custom image 'portainer-ce-custom:latest'."
                local compose_file_on_hypervisor="${hypervisor_portainer_dir}/docker-compose.yml"
                if [ ! -s "$compose_file_on_hypervisor" ]; then
                    log_fatal "docker-compose.yml not found or is empty at ${compose_file_on_hypervisor}. Cannot update with custom image."
                fi
                yq -i -y '.services.portainer.image = "portainer-ce-custom:latest"' "$compose_file_on_hypervisor" || log_fatal "Failed to update docker-compose.yml with custom image using yq."

                # --- BEGIN CERTIFICATE GENERATION ---
                local cert_dir="${hypervisor_portainer_dir}/certs"
                mkdir -p "$cert_dir"
                local cert_path="${cert_dir}/cert.pem"
                local key_path="${cert_dir}/key.pem"
                local ca_path="${cert_dir}/ca.pem"

                log_info "Generating Portainer certificate..."
                local temp_cert_path="/tmp/portainer.phoenix.local.crt"
                local temp_key_path="/tmp/portainer.phoenix.local.key"
                pct exec 103 -- step ca certificate portainer.phoenix.local "$temp_cert_path" "$temp_key_path" --provisioner admin@thinkheads.ai --password-file /etc/step-ca/ssl/ca_password.txt --force
                pct pull 103 "$temp_cert_path" "$cert_path"
                pct pull 103 "$temp_key_path" "$key_path"

                # Copy the CA certificate to the certs directory, renaming it to ca.pem
                log_info "Copying CA certificate to certs directory as ca.pem..."
                local source_ca_path="${hypervisor_portainer_dir}/phoenix_ca.crt"
                if [ -f "$source_ca_path" ]; then
                    cp "$source_ca_path" "$ca_path" || log_fatal "Failed to copy CA certificate to ${ca_path}."
                else
                    log_fatal "Source CA certificate not found at ${source_ca_path}. Cannot proceed."
                fi
                # --- END CERTIFICATE GENERATION ---

                # Ensure the compose file and config.json are present on the VM's persistent storage
                if ! qm guest exec "$VMID" -- /bin/bash -c "test -f $compose_file_path"; then
                    log_fatal "Portainer server compose file not found in VM $VMID at $compose_file_path."
                fi
                if ! qm guest exec "$VMID" -- /bin/bash -c "test -f $config_json_path"; then
                    log_warn "Portainer server config.json not found in VM $VMID at $config_json_path. Declarative endpoints may not be created."
                fi

                log_info "Ensuring clean restart for Portainer server on VM $VMID..."
                # Check if portainer_data volume exists before docker compose down
                qm guest exec "$VMID" -- /bin/bash -c "docker volume inspect portainer_portainer_data > /dev/null 2>&1" && log_debug "Portainer volume 'portainer_portainer_data' exists before down." || log_debug "Portainer volume 'portainer_portainer_data' does NOT exist before down."
                
                qm guest exec "$VMID" -- /bin/bash -c "cd $(dirname "$compose_file_path") && docker compose down --remove-orphans" || log_warn "Portainer server was not running or failed to stop cleanly on VM $VMID. Proceeding with deployment."
                log_info "Removing Portainer data volume to ensure a clean state..."
                qm guest exec "$VMID" -- /bin/bash -c "docker volume rm portainer_portainer_data || true"
                
                # Explicitly remove the portainer_data volume to ensure a clean state for re-initialization
                log_info "Removing Portainer data volume 'portainer_portainer_data' on VM $VMID to force re-initialization."
                qm guest exec "$VMID" -- /bin/bash -c "docker volume rm portainer_portainer_data || true" # '|| true' to prevent script from failing if volume doesn't exist
                
                # Check if portainer_data volume exists after docker compose down
                qm guest exec "$VMID" -- /bin/bash -c "docker volume inspect portainer_portainer_data > /dev/null 2>&1" && log_debug "Portainer volume 'portainer_portainer_data' exists AFTER down." || log_debug "Portainer volume 'portainer_portainer_data' does NOT exist AFTER down."

                # --- BEGIN DOCKER COMPOSE MODIFICATION ---
                log_info "Updating docker-compose.yml to mount certificates..."
                yq -i -y '.services.portainer.volumes += ["./certs:/certs"]' "$compose_file_on_hypervisor"
                # --- END DOCKER COMPOSE MODIFICATION ---

                log_info "Dynamically adding extra_hosts to docker-compose.yml for DNS resolution..."
                local agent_ip=$(jq -r '.vms[] | select(.portainer_role == "agent") | .network_config.ip' "$VM_CONFIG_FILE" | cut -d'/' -f1)
                local agent_name=$(jq -r '.vms[] | select(.portainer_role == "agent") | .name' "$VM_CONFIG_FILE")
                local domain_name=$(get_global_config_value '.network.domain_name' | jq -r '. // "phoenix.local"')
                local agent_fqdn="${agent_name}.agent.${domain_name}"
                local host_entry="${agent_fqdn}:${agent_ip}"

                yq -i -y ".services.portainer.extra_hosts += [\"${host_entry}\"]" "$compose_file_on_hypervisor" || log_fatal "Failed to add extra_hosts to docker-compose.yml using yq."

                log_info "Executing docker compose up -d for Portainer server on VM $VMID..."
                if ! qm guest exec "$VMID" -- /bin/bash -c "docker compose -f ${compose_file_path} up -d"; then
                    log_fatal "Failed to deploy Portainer server on VM $VMID."
                fi
                log_info "Portainer server deployment initiated on VM $VMID."
                log_info "Waiting 30 seconds for Portainer to initialize..."
                sleep 30
                ;;
            agent)
                log_info "Deploying Portainer agent on VM $VMID..."
                local agent_port=$(get_global_config_value '.network.portainer_agent_port')
                local agent_name=$(echo "$vm_config" | jq -r '.name')
                local domain_name=$(get_global_config_value '.network.domain_name' | jq -r '. // "phoenix.local"')
                local agent_fqdn="${agent_name}.agent.${domain_name}"

                # --- BEGIN AGENT CERTIFICATE GENERATION ---
                local agent_cert_dir="${persistent_volume_path}/certs"
                mkdir -p "$agent_cert_dir"
                local agent_cert_path="${agent_cert_dir}/cert.pem"
                local agent_key_path="${agent_cert_dir}/key.pem"
                local agent_ca_path="${agent_cert_dir}/ca.pem"

                log_info "Generating Portainer Agent certificate for ${agent_fqdn}..."
                local temp_agent_cert_path="/tmp/${agent_fqdn}.crt"
                local temp_agent_key_path="/tmp/${agent_fqdn}.key"
                
                pct exec 103 -- step ca certificate "${agent_fqdn}" "$temp_agent_cert_path" "$temp_agent_key_path" --provisioner admin@thinkheads.ai --password-file /etc/step-ca/ssl/ca_password.txt --force
                pct pull 103 "$temp_agent_cert_path" "$agent_cert_path"
                pct pull 103 "$temp_agent_key_path" "$agent_key_path"
                
                # Copy the CA certificate to the agent's certs directory
                cp "${PHOENIX_BASE_DIR}/persistent-storage/ssl/phoenix_ca.crt" "$agent_ca_path" || log_fatal "Failed to copy CA certificate to agent's certs directory."
                # --- END AGENT CERTIFICATE GENERATION ---

                log_info "Ensuring clean restart for Portainer agent on VM $VMID..."
                qm guest exec "$VMID" -- /bin/bash -c "docker rm -f portainer_agent" || log_warn "Portainer agent container was not running or failed to remove cleanly on VM $VMID. Proceeding with deployment."

                # The agent needs to be started with the correct TLS certificates. The agent will automatically use them if they are mounted to /certs.
                local docker_command="docker run -d -p ${agent_port}:9001 --name portainer_agent --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker/volumes:/var/lib/docker/volumes -v ${vm_mount_point}/certs:/certs portainer/agent:latest"

                if ! qm guest exec "$VMID" -- /bin/bash -c "$docker_command"; then
                    log_fatal "Failed to deploy Portainer agent on VM $VMID."
                fi
                log_info "Portainer agent deployment initiated on VM $VMID."
                ;;
            *)
                log_warn "Unknown Portainer role '$PORTAINER_ROLE' for VM $VMID. Skipping deployment."
                ;;
        esac
    done
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
    local ADMIN_USERNAME=$(get_global_config_value '.portainer_api.admin_user')
    local ADMIN_PASSWORD=$(get_global_config_value '.portainer_api.admin_password')

    if [ -z "$ADMIN_USERNAME" ] || [ "$ADMIN_USERNAME" == "null" ]; then
        log_fatal "Portainer admin username is not configured or is null in phoenix_hypervisor_config.json."
    fi
    if [ -z "$ADMIN_PASSWORD" ] || [ "$ADMIN_PASSWORD" == "null" ]; then
        log_fatal "Portainer admin password is not configured or is null in phoenix_hypervisor_config.json."
    fi

    log_info "Checking Portainer initialization status..."
    local STATUS_RESPONSE=$(curl -s --cacert "$CA_CERT_PATH" "${PORTAINER_URL}/api/status" --retry 5 --retry-delay 10)
    log_debug "Raw Portainer /api/status response: ${STATUS_RESPONSE}"
    local PORTAINER_STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.Status // ""')
    log_debug "Parsed Portainer status: ${PORTAINER_STATUS}"

    # Always attempt to create the admin user. The API endpoint is idempotent.
    log_info "Attempting to create initial admin user '${ADMIN_USERNAME}' (or verify existence)..."
    local INIT_PAYLOAD=$(jq -n --arg user "$ADMIN_USERNAME" --arg pass "$ADMIN_PASSWORD" '{username: $user, password: $pass}')
    local INIT_RESPONSE=$(curl -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/users/admin/init" \
      -H "Content-Type: application/json" -d "${INIT_PAYLOAD}" --retry 5 --retry-delay 10)

    # Check for successful creation (HTTP 200 OK or specific success message)
    # The API returns the user object on success, not necessarily a JWT at the top level for init.
    if echo "$INIT_RESPONSE" | jq -e '.Id' > /dev/null; then
        log_success "Portainer admin user '${ADMIN_USERNAME}' created successfully."
    elif echo "$INIT_RESPONSE" | grep -q "Admin user already exists"; then
        log_info "Portainer admin user '${ADMIN_USERNAME}' already exists. Skipping creation."
    else
        log_fatal "Failed to create Portainer admin user. Response: ${INIT_RESPONSE}"
    fi
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
    log_info "Starting full Portainer environment synchronization..."

    # 1. Ensure Portainer instances are deployed and running
    deploy_portainer_instances

    # 2. Wait for Portainer API to be responsive
    if ! "${PHOENIX_BASE_DIR}/bin/health_checks/check_portainer_api.sh"; then
        log_fatal "Portainer API health check failed. The service is not available. Aborting synchronization."
    fi
    log_info "Portainer API is responsive."

    # 2.5. Setup Portainer Admin User if not already configured
    local portainer_hostname=$(get_global_config_value '.portainer_api.portainer_hostname')
    local portainer_server_port=$(get_global_config_value '.network.portainer_server_port')
    local PORTAINER_URL="https://${portainer_hostname}:${portainer_server_port}"
    local ca_cert_path="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_ca.crt"
    setup_portainer_admin_user "$PORTAINER_URL" "$ca_cert_path"

    local JWT=$(get_portainer_jwt)
    local CA_CERT_PATH="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_ca.crt"
    local SSL_DIR="/mnt/pve/quickOS/lxc-persistent-data/103/ssl"
    local PORTAINER_SERVER_IP=$(get_global_config_value '.network.portainer_server_ip')

    # 3. Process each agent VM to create/update environments (endpoints)
    log_info "DEBUG: Listing all existing Portainer environments..."
    local all_endpoints=$(curl -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}" --retry 5 --retry-delay 10)
    log_info "DEBUG: Existing environments: $(echo "$all_endpoints" | jq)"

    local agent_vms_json
    agent_vms_json=$(jq -c '[.vms[] | select(.portainer_role == "agent")]' "$VM_CONFIG_FILE")

    echo "$agent_vms_json" | jq -c '.[]' | while read -r agent_vm; do
        local AGENT_IP=$(echo "$agent_vm" | jq -r '.network_config.ip' | cut -d'/' -f1)
        local AGENT_VMID=$(echo "$agent_vm" | jq -r '.vmid') # Extract VMID here
        local AGENT_NAME=$(echo "$agent_vm" | jq -r '.name')
        local AGENT_PORT=$(get_global_config_value '.network.portainer_agent_port')

        # Use the VM's actual name for the Portainer environment name
        local PORTAINER_ENVIRONMENT_NAME="${AGENT_NAME}"

        log_info "Synchronizing environment for agent: ${AGENT_NAME} (Portainer name: ${PORTAINER_ENVIRONMENT_NAME}) at ${AGENT_IP}"

        # --- Comprehensive Network Connectivity Checks ---
        log_info "DEBUG: Performing network connectivity checks..."

        # Host to Server VM (1001)
        log_info "DEBUG: Host to Portainer Server VM (1001) connectivity check (ping ${PORTAINER_SERVER_IP})..."
        ping -c 3 "${PORTAINER_SERVER_IP}" || log_warn "Host cannot ping Portainer Server VM (1001)."
        log_info "DEBUG: Host to Portainer Server VM (1001) port 9443 check..."
        nc -z -w 5 "${PORTAINER_SERVER_IP}" 9443 || log_warn "Host cannot reach Portainer Server VM (1001) on port 9443."

        # Host to Agent VM (1002)
        log_info "DEBUG: Host to Portainer Agent VM (${AGENT_VMID}) connectivity check (ping ${AGENT_IP})..."
        ping -c 3 "${AGENT_IP}" || log_warn "Host cannot ping Portainer Agent VM (${AGENT_VMID})."
        log_info "DEBUG: Host to Portainer Agent VM (${AGENT_VMID}) port ${AGENT_PORT} check..."
        nc -z -w 5 "${AGENT_IP}" "${AGENT_PORT}" || log_warn "Host cannot reach Portainer Agent VM (${AGENT_VMID}) on port ${AGENT_PORT}."

        # Server VM (1001) to Agent VM (1002) - Firewall status and listening port
        log_info "DEBUG: Checking firewall status on agent VM ${AGENT_VMID}..."
        qm guest exec "$AGENT_VMID" -- /bin/bash -c "ufw status" || log_warn "Could not get ufw status on VM ${AGENT_VMID}. UFW might not be installed or command failed."

        log_info "DEBUG: Verifying Portainer agent is listening on port ${AGENT_PORT} inside VM ${AGENT_VMID}..."
        qm guest exec "$AGENT_VMID" -- /bin/bash -c "ss -tulpn | grep :${AGENT_PORT}" || log_warn "Portainer agent not listening on ${AGENT_PORT} inside VM ${AGENT_VMID}."

        log_info "Introducing a 15-second delay before final connectivity check to allow agent to fully start..."
        sleep 15

        log_info "DEBUG: Adding firewall rule on Portainer server VM (1001) to allow outgoing traffic to agent VM (${AGENT_VMID}) at ${AGENT_IP}:${AGENT_PORT}..."
        qm guest exec 1001 -- /bin/bash -c "ufw allow out to ${AGENT_IP} port ${AGENT_PORT} proto tcp" || log_warn "Failed to add firewall rule on Portainer server VM (1001). This may cause connectivity issues."
        
        log_info "DEBUG: Forcing CA certificate update in Portainer server VM (1001)..."
        qm guest exec 1001 -- /bin/bash -c "update-ca-certificates" || log_warn "Failed to force update-ca-certificates in Portainer server VM (1001)."

        log_info "Performing final connectivity check from Portainer server VM (1001) to agent VM (${AGENT_VMID}) at ${AGENT_IP}:${AGENT_PORT}..."
        if ! run_qm_command guest exec 1001 -- nc -z -w 5 "${AGENT_IP}" "${AGENT_PORT}"; then
            log_fatal "Connectivity check failed: Portainer server VM (1001) cannot reach agent VM (${AGENT_VMID}) at ${AGENT_IP}:${AGENT_PORT}. Please ensure firewall rules and network configuration are correct."
        fi
        log_success "Connectivity check passed: Portainer server VM (1001) can reach agent VM (${AGENT_VMID}) at ${AGENT_IP}:${AGENT_PORT}."

        local ENDPOINT_URL="tcp://${AGENT_NAME}.agent.phoenix.local:${AGENT_PORT}"
        local ENDPOINT_ID=""

        # First, check if an environment with this name already exists
        local EXISTING_ENDPOINT_BY_NAME=$(curl -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}" --retry 5 --retry-delay 10 | jq -r --arg name "${PORTAINER_ENVIRONMENT_NAME}" '.[] | select(.Name==$name) | .Id // ""')

        if [ -n "$EXISTING_ENDPOINT_BY_NAME" ]; then
            log_warn "Portainer environment '${PORTAINER_ENVIRONMENT_NAME}' already exists with ID: ${EXISTING_ENDPOINT_BY_NAME}. Deleting and recreating to ensure a clean state."
            local delete_response
            delete_response=$(curl -w "%{http_code}" -s --cacert "$CA_CERT_PATH" -X DELETE "${PORTAINER_URL}/api/endpoints/${EXISTING_ENDPOINT_BY_NAME}" -H "Authorization: Bearer ${JWT}" --retry 5 --retry-delay 10)
            local http_code=${delete_response: -3}
            local body=${delete_response::-3}

            log_info "DEBUG: Delete API response HTTP code: ${http_code}"
            log_info "DEBUG: Delete API response body: ${body}"

            if [[ "$http_code" -ne 204 && "$http_code" -ne 404 ]]; then # 204 is success, 404 means it was already gone
                log_error "Failed to delete existing Portainer environment '${PORTAINER_ENVIRONMENT_NAME}'. HTTP status: ${http_code}. Proceeding, but this might cause issues."
            else
                log_info "Successfully deleted old Portainer environment '${PORTAINER_ENVIRONMENT_NAME}' (or it was already gone)."
            fi
        fi

        # Now, attempt to create the environment
        log_info "Creating environment for ${AGENT_NAME} (Portainer name: ${PORTAINER_ENVIRONMENT_NAME})..."
        
        # Use the agent's name to construct the FQDN for the endpoint URL.
        local domain_name=$(get_global_config_value '.network.domain_name')
        if [ -z "$domain_name" ] || [ "$domain_name" == "null" ]; then
            log_warn "Domain name not found in config, defaulting to 'phoenix.local'."
            domain_name="phoenix.local"
        fi
        local ENDPOINT_URL="tcp://${AGENT_NAME}.agent.${domain_name}:${AGENT_PORT}"
        log_info "Using endpoint URL: ${ENDPOINT_URL}"

        # --- BEGIN mTLS Certificate Generation ---
        local client_cert_path="${SSL_DIR}/portainer-server-client.crt"
        local client_key_path="${SSL_DIR}/portainer-server-client.key"
        log_info "Generating client certificate for Portainer server inside LXC 103..."
        
        # Define paths as they will be seen *inside* the container
        local container_cert_path="/tmp/portainer-server-client.crt"
        local container_key_path="/tmp/portainer-server-client.key"
        local container_password_path="/etc/step-ca/ssl/ca_password.txt"

        # Command to be executed inside LXC 103 - simplified to essentials
        local agent_fqdn="${AGENT_NAME}.agent.${domain_name}"
        log_info "Generating client certificate for agent FQDN: ${agent_fqdn}"
        local step_command="step ca certificate \"${agent_fqdn}\" \"${container_cert_path}\" \"${container_key_path}\" --provisioner admin@thinkheads.ai --password-file \"${container_password_path}\" --force"

        # Execute the command inside the container
        if ! pct exec 103 -- /bin/bash -c "$step_command"; then
            log_fatal "Failed to generate client certificate inside LXC 103."
        fi

        # Extract only the client certificate from the bundled file
        log_info "Extracting client certificate from bundled file..."
        local unbundled_cert_path="/tmp/portainer-server-client.unbundled.crt"
        local extract_command="awk 'BEGIN {p=1} /-----BEGIN CERTIFICATE-----/ {if(p==0) exit; p=0} {print}' ${container_cert_path} > ${unbundled_cert_path}"
        if ! pct exec 103 -- /bin/bash -c "$extract_command"; then
            log_fatal "Failed to extract client certificate in LXC 103."
        fi

        # Pull the generated files from the container to the host
        log_info "Pulling generated certificate and key from LXC 103..."
        if ! pct pull 103 "$unbundled_cert_path" "$client_cert_path"; then
            log_fatal "Failed to pull certificate from LXC 103."
        fi
        if ! pct pull 103 "$container_key_path" "$client_key_path"; then
            log_fatal "Failed to pull key from LXC 103."
        fi

        # Clean up the temporary files inside the container
        pct exec 103 -- rm -f "$container_cert_path" "$container_key_path" "$unbundled_cert_path"
        # --- END mTLS Certificate Generation ---

        local temp_payload_file=$(mktemp)
        jq -n \
            --arg name "${PORTAINER_ENVIRONMENT_NAME}" \
            --arg url "${ENDPOINT_URL}" \
            --rawfile cacert "${SSL_DIR}/phoenix_ca.crt" \
            --rawfile clientcert "$client_cert_path" \
            --rawfile clientkey "$client_key_path" \
            '{
                "Name": $name,
                "Type": 3,
                "URL": $url,
                "TLS": true,
                "TLSSkipVerify": false,
                "TLSCACert": $cacert,
                "TLSCert": $clientcert,
                "TLSKey": $clientkey
            }' > "$temp_payload_file"

        log_debug "Portainer environment creation payload (from file): $(cat "$temp_payload_file")"
        
        # Add verbose curl logging
        log_debug "Executing curl command for environment creation:"
        log_debug "Curl command: curl -v -s --cacert \"$CA_CERT_PATH\" -X POST \"${PORTAINER_URL}/api/endpoints\" -H \"Authorization: Bearer ${JWT}\" -H \"Content-Type: application/json\" --data @\"$temp_payload_file\" --retry 5 --retry-delay 10"
        local RESPONSE=$(curl -v -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/endpoints" \
            -H "Authorization: Bearer ${JWT}" \
            -H "Content-Type: application/json" \
            --data @"$temp_payload_file" \
            --retry 5 --retry-delay 10)
        
        rm "$temp_payload_file" # Clean up the temporary file
        log_debug "Raw Portainer environment creation response: ${RESPONSE}"

        ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.Id // ""')
        if [ -z "$ENDPOINT_ID" ]; then
            log_fatal "Failed to create environment for ${AGENT_NAME}. Response: ${RESPONSE}"
        fi
        log_info "Environment for ${AGENT_NAME} created with ID: ${ENDPOINT_ID}"

        # 4. Deploy/Update stacks associated with this agent
        echo "$agent_vm" | jq -r '.docker_stacks[]?' | while read -r STACK_CONFIG_JSON; do
            log_info "Synchronizing stack '$(echo "$STACK_CONFIG_JSON" | jq -r '.name')' (environment: '$(echo "$STACK_CONFIG_JSON" | jq -r '.environment')') for environment '${AGENT_NAME}'"
            sync_stack "$AGENT_VMID" "$STACK_CONFIG_JSON" "$JWT" "$ENDPOINT_ID" # Pass AGENT_VMID
        done
    done

    log_success "Full Portainer environment synchronization completed successfully."
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

    local portainer_hostname="portainer.phoenix.local"
    local portainer_server_port=$(get_global_config_value '.network.portainer_server_port')
    local PORTAINER_URL="https://${portainer_hostname}:${portainer_server_port}"
    local CA_CERT_PATH="${PHOENIX_BASE_DIR}/persistent-storage/ssl/portainer.phoenix.local.crt"

    if [ -z "$JWT" ]; then
        JWT=$(get_portainer_jwt)
    fi

    if [ -z "$ENDPOINT_ID" ]; then
        local agent_ip=$(jq -r ".vms[] | select(.vmid == $VMID) | .network_config.ip" "$VM_CONFIG_FILE" | cut -d'/' -f1)
        local AGENT_PORT=$(get_global_config_value '.network.portainer_agent_port')
        local ENDPOINT_URL="tcp://${agent_ip}:${AGENT_PORT}"
        ENDPOINT_ID=$(curl -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}" --retry 5 --retry-delay 10 | jq -r --arg url "${ENDPOINT_URL}" '.[] | select(.URL==$url) | .Id // ""')
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

    local STACK_CONTENT
    STACK_CONTENT=$(cat "$FULL_COMPOSE_PATH")

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
            local EXISTING_CONFIG_ID=$(curl -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/configs" -H "Authorization: Bearer ${JWT}" --retry 5 --retry-delay 10 | jq -r --arg name "${CONFIG_NAME}" '.[] | select(.Name==$name) | .Id // ""')

            if [ -n "$EXISTING_CONFIG_ID" ]; then
                log_info "Portainer Config '${CONFIG_NAME}' already exists. Deleting and recreating to ensure content is fresh."
                if ! curl -s --cacert "$CA_CERT_PATH" -X DELETE "${PORTAINER_URL}/api/configs/${EXISTING_CONFIG_ID}" -H "Authorization: Bearer ${JWT}" --retry 5 --retry-delay 10; then
                    log_warn "Failed to delete old Portainer Config '${CONFIG_NAME}'. Proceeding, but this might cause issues."
                fi
            fi

            log_info "Creating Portainer Config '${CONFIG_NAME}'..."
            local CONFIG_PAYLOAD=$(jq -n --arg name "${CONFIG_NAME}" --arg data "${FILE_CONTENT}" '{Name: $name, Data: $data}')
            local CONFIG_RESPONSE=$(curl -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/configs?endpointId=${ENDPOINT_ID}" \
              -H "Authorization: Bearer ${JWT}" -H "Content-Type: application/json" -d "${CONFIG_PAYLOAD}" --retry 5 --retry-delay 10)
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
    STACK_EXISTS_ID=$(curl -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/stacks" -H "Authorization: Bearer ${JWT}" --retry 5 --retry-delay 10 | jq -r --arg name "${STACK_NAME}-${ENVIRONMENT_NAME}" --argjson endpoint_id "${ENDPOINT_ID}" '.[] | select(.Name==$name and .EndpointId==$endpoint_id) | .Id // ""')

    local STACK_DEPLOY_NAME="${STACK_NAME}-${ENVIRONMENT_NAME}" # Unique stack name in Portainer

    if [ -n "$STACK_EXISTS_ID" ]; then
        log_info "Stack '${STACK_DEPLOY_NAME}' already exists on environment ID '${ENDPOINT_ID}'. Updating..."
        local JSON_PAYLOAD=$(jq -n \
            --arg content "${STACK_CONTENT}" \
            --argjson env "$ENV_VARS_JSON" \
            --argjson configs "$CONFIG_IDS_JSON" \
            '{StackFileContent: $content, Env: $env, Configs: $configs}')
        log_info "DEBUG: PUT JSON_PAYLOAD: ${JSON_PAYLOAD}"
        local RESPONSE=$(curl -s --cacert "$CA_CERT_PATH" -X PUT "${PORTAINER_URL}/api/stacks/${STACK_EXISTS_ID}?endpointId=${ENDPOINT_ID}" \
          -H "Authorization: Bearer ${JWT}" -H "Content-Type: application/json" -d "${JSON_PAYLOAD}" --retry 5 --retry-delay 10)
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
            --arg content "${STACK_CONTENT}" \
            --argjson env "$ENV_VARS_JSON" \
            --argjson configs "$CONFIG_IDS_JSON" \
            '{Name: $name, StackFileContent: $content, Env: $env, Configs: $configs}')
        log_info "DEBUG: POST JSON_PAYLOAD: ${JSON_PAYLOAD}"
        local RESPONSE=$(curl -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/stacks?type=1&method=string&endpointId=${ENDPOINT_ID}" \
          -H "Authorization: Bearer ${JWT}" -H "Content-Type: application/json" -d "${JSON_PAYLOAD}" --retry 5 --retry-delay 10)
        log_info "DEBUG: POST API RESPONSE: ${RESPONSE}"
        if echo "$RESPONSE" | jq -e '.Id' > /dev/null; then
          log_success "Stack '${STACK_DEPLOY_NAME}' deployed successfully."
        else
          log_fatal "Failed to deploy stack '${STACK_DEPLOY_NAME}'. Response: ${RESPONSE}"
        fi
    fi
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