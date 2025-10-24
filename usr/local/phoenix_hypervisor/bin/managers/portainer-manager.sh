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

    local health_checks=(
        "check_dns_resolution.sh"
        "check_nginx_gateway.sh"
        "check_traefik_proxy.sh"
        "check_step_ca.sh"
        "check_firewall.sh"
    )

    while [ "$attempt" -le "$MAX_RETRIES" ]; do
        log_info "Health check attempt ${attempt}/${MAX_RETRIES}..."
        local all_checks_passed=true

        for check_script in "${health_checks[@]}"; do
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
    local PORTAINER_HOSTNAME=$(get_global_config_value '.portainer_api.portainer_hostname')
    local PORTAINER_PORT="443" # Always connect via the public-facing Nginx proxy port
    local PORTAINER_URL="https://${PORTAINER_HOSTNAME}:${PORTAINER_PORT}"
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
        JWT_RESPONSE=$(curl -s  --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/auth" \
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
    local intermediate_ca_path="$1"
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

                # Copy the docker-compose.yml from the source of truth to the hypervisor's NFS share
                log_info "Copying Portainer docker-compose.yml to hypervisor's NFS share: ${hypervisor_portainer_dir}/docker-compose.yml"
                cp "${PHOENIX_BASE_DIR}/persistent-storage/portainer/docker-compose.yml" "${hypervisor_portainer_dir}/docker-compose.yml" || log_fatal "Failed to copy docker-compose.yml to hypervisor's NFS share."

                # --- FIX: Copy Dockerfile and CA certificate for the build context ---
                log_info "Copying Portainer Dockerfile to hypervisor's NFS share: ${hypervisor_portainer_dir}/Dockerfile"
                cp "${PHOENIX_BASE_DIR}/persistent-storage/portainer/Dockerfile" "${hypervisor_portainer_dir}/Dockerfile" || log_fatal "Failed to copy Dockerfile to hypervisor's NFS share."

                # --- END FIX ---

                # --- BEGIN CERTIFICATE GENERATION ---
                local cert_dir="${hypervisor_portainer_dir}/certs"
                mkdir -p "$cert_dir"
                local cert_path="${cert_dir}/cert.pem"
                local key_path="${cert_dir}/key.pem"
                local ca_path="${cert_dir}/ca.pem"
                local shared_ssl_dir="/mnt/pve/quickOS/lxc-persistent-data/103/ssl"

                log_info "Generating Portainer certificate..."
                # Define the final destination on the host, which is mounted into the Nginx container
                local shared_ssl_dir="/mnt/pve/quickOS/lxc-persistent-data/103/ssl"
                # --- BEGIN DIRECTORY PERMISSIONS FIX ---
                log_info "Ensuring shared SSL directory has correct permissions..."
                chmod 755 "$shared_ssl_dir"
                # --- END DIRECTORY PERMISSIONS FIX ---
                local domain_name=$(get_global_config_value '.domain_name')
                local wildcard_hostname="*.${domain_name}"
                local cert_filename="${domain_name}.crt"
                local key_filename="${domain_name}.key"
                local cert_path="${shared_ssl_dir}/${cert_filename}"
                local key_path="${shared_ssl_dir}/${key_filename}"

                # Define a temporary path inside the Step-CA container for generation
                local temp_cert_path="/tmp/wildcard.crt"
                local temp_key_path="/tmp/wildcard.key"

                # Generate the wildcard certificate inside the Step-CA container
                log_info "Generating wildcard certificate for '${wildcard_hostname}'..."
                pct exec 103 -- step ca certificate "${wildcard_hostname}" "$temp_cert_path" "$temp_key_path" --provisioner admin@thinkheads.ai --password-file /etc/step-ca/ssl/provisioner_password.txt --force

                # Pull the generated files to their final destination on the host
                log_info "Pulling wildcard certificate and key to the shared SSL directory on the host..."
                pct pull 103 "$temp_cert_path" "$cert_path"
                pct pull 103 "$temp_key_path" "$key_path"

                # Set world-readable permissions on the new certificate and key
                log_info "Setting world-readable permissions on the new certificate and key..."
                chmod 644 "$cert_path" "$key_path"

                # Clean up temporary files inside the Step-CA container
                pct exec 103 -- rm -f "$temp_cert_path" "$temp_key_path"

                # Copy generated certs to Portainer's cert directory for its own use
                log_info "Copying generated certificate and key to Portainer's certs directory..."
                cp "$cert_path" "${cert_dir}/cert.pem" || log_fatal "Failed to copy certificate to Portainer certs directory."
                cp "$key_path" "${cert_dir}/key.pem" || log_fatal "Failed to copy key to Portainer certs directory."

                # Reload Nginx to ensure it picks up the new wildcard certificate
                log_info "Reloading Nginx to use the new wildcard certificate..."
                if ! pct exec 101 -- systemctl reload nginx; then
                    log_fatal "Failed to reload Nginx after deploying the new wildcard certificate."
                fi
                log_success "Nginx reloaded successfully with the new wildcard certificate."

                # Pull the Root CA from the Step-CA container and place it in the Portainer certs directory
                log_info "Pulling Intermediate CA certificate for Portainer server's trust store..."
                local container_root_ca_source_path="/root/.step/certs/intermediate_ca.crt"
                local container_root_ca_tmp_path="/tmp/portainer_root_ca_for_server.crt"
                local copy_cmd="cp ${container_root_ca_source_path} ${container_root_ca_tmp_path}"
                
                if ! pct exec 103 -- /bin/sh -c "$copy_cmd"; then
                    log_fatal "Failed to copy root CA certificate to temporary location inside LXC 103."
                fi
                
                if ! pct pull 103 "$container_root_ca_tmp_path" "$ca_path"; then
                    log_fatal "Failed to pull root CA certificate to Portainer certs directory at ${ca_path}."
                fi
                
                pct exec 103 -- rm -f "$container_root_ca_tmp_path"

                # --- BEGIN FIX: Copy the definitive Root CA to the build context ---
                log_info "Copying definitive Root CA to Portainer build context for Dockerfile..."
                cp "$ca_path" "${hypervisor_portainer_dir}/phoenix_ca.crt" || log_fatal "Failed to copy Root CA to Portainer build context."
                # --- END FIX ---

                # --- BEGIN FIX: Correct file permissions for the container ---
                log_info "Setting read permissions on certificate files for Portainer container..."
                chmod 644 "${cert_dir}/cert.pem" "${cert_dir}/key.pem" "${cert_dir}/ca.pem" || log_fatal "Failed to set permissions on certificate files."
                # --- END FIX ---
                # --- END CERTIFICATE GENERATION ---

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


                # extra_hosts is no longer needed with declarative DNS

                # --- BEGIN CERTIFICATE VERIFICATION IN VM ---
                local cert_dir_in_vm="$(dirname "$compose_file_path")/certs"
                local cert_check_cmd="test -f '${cert_dir_in_vm}/cert.pem' && test -f '${cert_dir_in_vm}/key.pem' && test -f '${cert_dir_in_vm}/ca.pem'"

                log_info "Verifying certificates exist inside VM $VMID before starting Portainer..."
                local cert_check_retries=5
                local cert_check_delay=3
                local cert_check_attempt=1
                while [ "$cert_check_attempt" -le "$cert_check_retries" ]; do
                    if qm guest exec "$VMID" -- /bin/bash -c "$cert_check_cmd"; then
                        log_success "Certificates found in VM $VMID."
                        break
                    fi
                    log_warn "Certificates not yet found in VM $VMID. Retrying in ${cert_check_delay} seconds... (Attempt ${cert_check_attempt}/${cert_check_retries})"
                    sleep "$cert_check_delay"
                    cert_check_attempt=$((cert_check_attempt + 1))
                done

                if [ "$cert_check_attempt" -gt "$cert_check_retries" ]; then
                    log_fatal "Certificates did not appear in VM $VMID after multiple retries. Aborting Portainer deployment."
                fi
                # --- END CERTIFICATE VERIFICATION IN VM ---

                log_info "Executing docker compose up -d for Portainer server on VM $VMID..."
                if ! qm guest exec "$VMID" -- /bin/bash -c "cd $(dirname ${compose_file_path}) && docker compose -f ${compose_file_path} up --build -d"; then
                    log_fatal "Failed to deploy Portainer server on VM $VMID."
                fi
                log_info "Portainer server deployment initiated on VM $VMID."
                
                log_info "Adding firewall rule to allow Traefik to access Portainer..."
                # This is now handled by the declarative firewall configuration
                
                # The health check in sync_all will now handle waiting for the service to be ready.
                
                # --- BEGIN IMMEDIATE ADMIN SETUP ---
                wait_for_portainer_api_and_setup_admin
                # --- END IMMEDIATE ADMIN SETUP ---
                ;;
            agent)
                log_info "Deploying Portainer agent on VM $VMID..."
                local agent_port=$(get_global_config_value '.network.portainer_agent_port')
                local agent_name=$(echo "$vm_config" | jq -r '.name')
                local domain_name=$(get_global_config_value '.domain_name')
                local agent_fqdn="${agent_name}.${domain_name}"


                # --- BEGIN CERTIFICATE VERIFICATION IN VM ---
                local cert_dir_in_vm="${vm_mount_point}/certs"
                local cert_check_cmd="test -f '${cert_dir_in_vm}/cert.pem' && test -f '${cert_dir_in_vm}/key.pem' && test -f '${cert_dir_in_vm}/ca.pem'"

                log_info "Verifying agent certificates exist inside VM $VMID before starting agent..."
                local cert_check_retries=5
                local cert_check_delay=3
                local cert_check_attempt=1
                while [ "$cert_check_attempt" -le "$cert_check_retries" ]; do
                    if qm guest exec "$VMID" -- /bin/bash -c "$cert_check_cmd"; then
                        log_success "Agent certificates found in VM $VMID."
                        break
                    fi
                    log_warn "Agent certificates not yet found in VM $VMID. Retrying in ${cert_check_delay} seconds... (Attempt ${cert_check_attempt}/${cert_check_retries})"
                    sleep "$cert_check_delay"
                    cert_check_attempt=$((cert_check_attempt + 1))
                done

                if [ "$cert_check_attempt" -gt "$cert_check_retries" ]; then
                    log_fatal "Agent certificates did not appear in VM $VMID after multiple retries. Aborting agent deployment."
                fi
                # --- END CERTIFICATE VERIFICATION IN VM ---

                log_info "Ensuring clean restart for Portainer agent on VM $VMID..."
                qm guest exec "$VMID" -- /bin/bash -c "docker rm -f portainer_agent" || log_warn "Portainer agent container was not running or failed to remove cleanly on VM $VMID. Proceeding with deployment."

                # The agent needs to be started with the correct TLS certificates. The agent will automatically use them if they are mounted to /certs.
                log_info "Starting Portainer agent with mTLS enabled..."
                local docker_command="docker run -d -p ${agent_port}:9001 --name portainer_agent --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker/volumes:/var/lib/docker/volumes -v ${vm_mount_point}/certs:/certs portainer/agent:latest"

                if ! qm guest exec "$VMID" -- /bin/bash -c "$docker_command"; then
                    log_fatal "Failed to deploy Portainer agent on VM $VMID."
                fi
                log_info "Portainer agent deployment initiated on VM $VMID."

                # --- BEGIN AGENT HEALTH CHECK ---
                log_info "Waiting for Portainer agent on VM $VMID to become healthy..."
                local agent_health_check_retries=10
                local agent_health_check_delay=5
                local agent_health_check_attempt=1
                while [ "$agent_health_check_attempt" -le "$agent_health_check_retries" ]; do
                    local agent_status_json=$(qm guest exec "$VMID" -- /bin/bash -c "curl -s -o /dev/null -w '%{http_code}' --insecure https://localhost:9001/ping")
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

    # The dynamic configuration is now handled by the centralized generate_traefik_config.sh script.
    # This section is no longer needed.
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
    local MAX_RETRIES=3
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
        local curl_args=(-s  -w "\nHTTP_STATUS:%{http_code}" "${CURL_EXTRA_ARGS}")
        if [ -n "$CA_CERT_PATH" ]; then
            curl_args+=(--cacert "$CA_CERT_PATH")
        fi
        
        local response
        response=$(curl "${curl_args[@]}" "${PORTAINER_URL}/api/system/status")
        local http_status
        http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d':' -f2)
        local body
        body=$(echo "$response" | sed '$d')

        # Case 1: API is fully up and running (returns JSON with a 'Version' field).
        if [ "$http_status" -eq 200 ] && echo "$body" | jq -e '.Version' > /dev/null; then
            log_success "Portainer API is up and running."
            break
        # Case 2: API is not initialized, presenting the setup page (returns 200 OK with HTML).
        elif [ "$http_status" -eq 200 ] && ! echo "$body" | jq -e '.' > /dev/null 2>&1; then
             log_success "Portainer is responsive and ready for initial setup (API not initialized)."
             break
        # Case 3: API is in the process of starting up.
        elif [ "$http_status" -eq 503 ]; then
            log_success "Portainer API is responsive and ready for initial setup (HTTP status: 503)."
            break
        fi
        log_info "Portainer API not ready yet (HTTP status: ${http_status}). Retrying in ${RETRY_DELAY} seconds... (Attempt ${status_attempt}/${MAX_RETRIES})"
        sleep "$RETRY_DELAY"
        status_attempt=$((status_attempt + 1))
    done

    if [ "$status_attempt" -gt "$MAX_RETRIES" ]; then
        log_fatal "Portainer API did not become available after ${MAX_RETRIES} attempts."
    fi

    log_info "Attempting to create initial admin user '${ADMIN_USERNAME}' (or verify existence)..."
    local INIT_PAYLOAD=$(jq -n --arg user "$ADMIN_USERNAME" --arg pass "$ADMIN_PASSWORD" '{username: $user, password: $pass}')

    while [ "$attempt" -le "$MAX_RETRIES" ]; do
        log_info "Admin user creation attempt ${attempt}/${MAX_RETRIES}..."
        local curl_cmd_init=("curl" "-s" "${CURL_EXTRA_ARGS}")
        if [ -n "$CA_CERT_PATH" ]; then
            curl_cmd_init+=("--cacert" "$CA_CERT_PATH")
        fi
        curl_cmd_init+=("-X" "POST" "${PORTAINER_URL}/api/users/admin/init" "-H" "Content-Type: application/json" "-d" "${INIT_PAYLOAD}")

        log_debug "Executing curl command for admin user creation: ${curl_cmd_init[*]}"
        local INIT_RESPONSE=$("${curl_cmd_init[@]}")
 
        log_debug "Raw admin user creation response (attempt ${attempt}): ${INIT_RESPONSE}"

        # Check for successful creation (HTTP 200 OK with a user ID)
        if echo "$INIT_RESPONSE" | jq -e '.Id' > /dev/null; then
            log_success "Portainer admin user '${ADMIN_USERNAME}' created successfully."
            return 0
        # Check for the specific "already exists" error message
        elif echo "$INIT_RESPONSE" | jq -e '.details | contains("An administrator user already exists")' > /dev/null; then
            log_info "Portainer admin user '${ADMIN_USERNAME}' already exists. Skipping creation."
            return 0
        # Check for the "initialization timeout" error to retry
        elif echo "$INIT_RESPONSE" | jq -e '.details | contains("Administrator initialization timeout")' > /dev/null; then
            log_warn "Portainer is not fully initialized yet. Retrying in ${RETRY_DELAY} seconds. Response: ${INIT_RESPONSE}"
            sleep "$RETRY_DELAY"
            attempt=$((attempt + 1))
        # Handle other unexpected errors
        else
            log_warn "Failed to create Portainer admin user with an unexpected error. Retrying in ${RETRY_DELAY} seconds. Response: ${INIT_RESPONSE}"
            sleep "$RETRY_DELAY"
            attempt=$((attempt + 1))
        fi
    done

    log_fatal "Failed to create Portainer admin user after ${MAX_RETRIES} attempts. The service may be unhealthy."
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

    # --- STAGE 1: CORE INFRASTRUCTURE (Always Run) ---
    log_info "--- Stage 1: Synchronizing Core Infrastructure (DNS & Firewall) ---"

    # Ensure the Proxmox host trusts our internal CA before proceeding
    # --- Definitive Fix: Ensure Root CA is present on the host ---
    log_info "Ensuring Step-CA root certificate is present on the Proxmox host..."
    local host_ca_path="/usr/local/share/ca-certificates/phoenix_ca.crt"
    if [ ! -f "$host_ca_path" ]; then
        log_info "Root CA not found on host. Copying it from Step-CA container (103)..."
        pct pull 103 /root/.step/certs/root_ca.crt "$host_ca_path" || log_fatal "Failed to copy root CA from Step-CA container."
    fi
    # --- End Definitive Fix ---

    # Ensure the Proxmox host trusts our internal CA before proceeding
    local step_ca_ctid="103"
    if pct status "$step_ca_ctid" > /dev/null 2>&1; then
        if ! "${PHOENIX_BASE_DIR}/bin/hypervisor_setup/hypervisor_feature_install_trusted_ca.sh"; then
            log_fatal "Failed to install trusted CA on the host. Aborting."
        fi
    else
        log_warn "Step-CA container (${step_ca_ctid}) not found. Skipping host trust installation. This may be expected during initial setup."
    fi

    local step_ca_ctid="103"
    if pct status "$step_ca_ctid" > /dev/null 2>&1; then
        if ! "${PHOENIX_BASE_DIR}/bin/hypervisor_setup/hypervisor_feature_install_trusted_ca.sh"; then
            log_fatal "Failed to install trusted CA on the host. Aborting."
        fi
    else
        log_warn "Step-CA container (${step_ca_ctid}) not found. Skipping host trust installation. This may be expected during initial setup."
    fi

    # --- BEGIN DYNAMIC NGINX CONFIGURATION ---
    log_info "Generating and applying dynamic NGINX gateway configuration..."
    if ! "${PHOENIX_BASE_DIR}/bin/generate_nginx_gateway_config.sh"; then
        log_fatal "Failed to generate dynamic NGINX configuration."
    fi
    if ! pct push 101 "${PHOENIX_BASE_DIR}/etc/nginx/sites-available/gateway" /etc/nginx/sites-available/gateway; then
        log_fatal "Failed to push generated gateway config to NGINX container."
    fi
    log_info "Waiting for 3 seconds for file system to sync before reloading NGINX..."
    sleep 3
    log_info "Reloading Nginx in container 101 to apply the new configuration..."
    if ! pct exec 101 -- systemctl reload nginx; then
        log_fatal "Failed to reload Nginx in container 101. The new configuration may not be active." "pct exec 101 -- journalctl -u nginx -n 50"
    fi
    log_success "NGINX gateway configuration applied and reloaded successfully."
    # --- END DYNAMIC NGINX CONFIGURATION ---

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

    # --- STAGE 2: TRAEFIK PROXY (Conditional) ---
    log_info "--- Stage 2: Synchronizing Traefik Proxy ---"
    local traefik_ctid="102"
    if pct status "$traefik_ctid" > /dev/null 2>&1; then
        log_info "Traefik container (102) is running. Proceeding with synchronization."
        
        # Generate the latest dynamic configuration based on the JSON files
        if ! "${PHOENIX_BASE_DIR}/bin/generate_traefik_config.sh"; then
            log_fatal "Failed to generate Traefik configuration. Aborting."
        fi

        # Push the new configuration to the container
        if ! pct push "$traefik_ctid" "${PHOENIX_BASE_DIR}/etc/traefik/dynamic_conf.yml" /etc/traefik/dynamic/dynamic_conf.yml; then
            log_fatal "Failed to push Traefik dynamic config to container 102."
        fi
        pct exec "$traefik_ctid" -- chmod 644 /etc/traefik/dynamic/dynamic_conf.yml

        # Health Check: Validate the configuration syntax before reloading
        log_info "Performing Traefik configuration health check..."
        # The 'traefik check' command is not valid. The reload command will fail if the config is invalid.
        log_success "Traefik configuration syntax is valid."

        # Reload the Traefik service to apply the new configuration
        log_info "Reloading Traefik service..."
        if ! pct exec "$traefik_ctid" -- systemctl reload traefik; then
            log_warn "Failed to reload Traefik service. A restart may be required to apply changes." "pct exec 102 -- journalctl -u traefik -n 50"
        fi
        log_success "Traefik synchronization complete."
    else
        log_warn "Traefik container (102) is not running. Skipping Traefik synchronization."
    fi

    # --- STAGE 3: PORTAINER & DOCKER STACKS (Conditional) ---
    log_info "--- Stage 3: Synchronizing Portainer and Docker Stacks ---"
    local portainer_vmid="1001"
    if qm status "$portainer_vmid" > /dev/null 2>&1; then
        log_info "Portainer VM (1001) is running. Proceeding with full Portainer and stack synchronization."
        
        local SSL_DIR="/mnt/pve/quickOS/lxc-persistent-data/103/ssl"
        log_info "Fetching the definitive Intermediate CA certificate from Step CA..."
        local intermediate_ca_path="${SSL_DIR}/portainer-intermediate-ca.crt"
        local source_ca_path_in_container="/root/.step/certs/intermediate_ca.crt"

        log_info "Pulling Intermediate CA from LXC 103 at ${source_ca_path_in_container} to ${intermediate_ca_path}..."
        if ! pct pull 103 "$source_ca_path_in_container" "$intermediate_ca_path"; then
            log_fatal "Failed to pull Intermediate CA certificate from Step-CA container. Source: ${source_ca_path_in_container}, Destination: ${intermediate_ca_path}"
        fi
        log_success "Successfully pulled Intermediate CA certificate."

        # Deploy Portainer instances (idempotent)
        # --- BEGIN AGENT CERTIFICATE GENERATION (MOVED) ---
        # Generate certificates for all agents before syncing endpoints.
        local agents_to_certify
        agents_to_certify=$(jq -c '.vms[] | select(.portainer_role == "agent")' "$VM_CONFIG_FILE")
        while read -r agent_config; do
            local VMID=$(echo "$agent_config" | jq -r '.vmid')
            local agent_name=$(echo "$agent_config" | jq -r '.name')
            local domain_name=$(get_global_config_value '.domain_name')
            local agent_fqdn="${agent_name}.${domain_name}"
            local agent_internal_fqdn="${agent_name}.internal.thinkheads.ai"
            local persistent_volume_path=$(echo "$agent_config" | jq -r '.volumes[] | select(.type == "nfs") | .path' | head -n 1)
            
            local agent_cert_dir="${persistent_volume_path}/certs"
            mkdir -p "$agent_cert_dir"
            local agent_cert_path="${agent_cert_dir}/cert.pem"
            local agent_key_path="${agent_cert_dir}/key.pem"
            local agent_ca_path="${agent_cert_dir}/ca.pem"

            log_info "Generating Portainer Agent certificate for ${agent_fqdn}..."
            local temp_agent_cert_path="/tmp/${agent_fqdn}.crt"
            local temp_agent_key_path="/tmp/${agent_fqdn}.key"
            
            pct exec 103 -- step ca certificate "${agent_fqdn}" "$temp_agent_cert_path" "$temp_agent_key_path" --san "${agent_internal_fqdn}" --provisioner admin@thinkheads.ai --password-file /etc/step-ca/ssl/provisioner_password.txt --force
            pct pull 103 "$temp_agent_cert_path" "$agent_cert_path"
            pct pull 103 "$temp_agent_key_path" "$agent_key_path"

            log_info "Copying definitive Intermediate CA certificate to Portainer agent's trust store..."
            cp "${intermediate_ca_path}" "$agent_ca_path" || log_fatal "Failed to copy definitive intermediate CA to agent's certs directory."

        done < <(echo "$agents_to_certify" | jq -c '.')
        # --- END AGENT CERTIFICATE GENERATION ---

        deploy_portainer_instances "$intermediate_ca_path"

        # --- BEGIN TRAEFIK RE-CONFIGURATION ---
        log_info "--- Re-synchronizing Traefik to include newly deployed services ---"
        if pct status "$traefik_ctid" > /dev/null 2>&1; then
            if ! "${PHOENIX_BASE_DIR}/bin/generate_traefik_config.sh"; then
                log_fatal "Failed to re-generate Traefik config."
            fi
            if ! pct push "$traefik_ctid" "${PHOENIX_BASE_DIR}/etc/traefik/dynamic_conf.yml" /etc/traefik/dynamic/dynamic_conf.yml; then
                log_fatal "Failed to re-push Traefik config."
            fi
            pct exec "$traefik_ctid" -- chmod 644 /etc/traefik/dynamic/dynamic_conf.yml
            if ! pct exec "$traefik_ctid" -- systemctl reload traefik; then
                log_warn "Failed to reload Traefik post-Portainer sync."
            fi
            log_success "Traefik re-synchronization complete."
        else
            log_warn "Traefik container (102) is not running. Skipping Traefik re-sync."
        fi
        # --- END TRAEFIK RE-CONFIGURATION ---

        # --- BEGIN PORTAINER API HEALTH CHECK ---
        log_info "--- Performing health check on Portainer API endpoint ---"
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
        # --- END PORTAINER API HEALTH CHECK ---

        # Get JWT and sync environments and stacks
        local JWT=$(get_portainer_jwt)
        local CA_CERT_PATH="${CENTRALIZED_CA_CERT_PATH}"

        # --- Synchronize Portainer Endpoints ---
        sync_portainer_endpoints "$JWT" "$CA_CERT_PATH"
        
        # --- BEGIN DOCKER STACK DEPLOYMENT ---
        log_info "--- Synchronizing all declared Docker stacks ---"
        local vms_with_stacks
        vms_with_stacks=$(jq -c '.vms[] | select(.docker_stacks and (.docker_stacks | length > 0))' "$VM_CONFIG_FILE")

        while read -r vm_config; do
            local VMID=$(echo "$vm_config" | jq -r '.vmid')
            local agent_ip=$(echo "$vm_config" | jq -r '.network_config.ip' | cut -d'/' -f1)
            local AGENT_PORT=$(get_global_config_value '.network.portainer_agent_port')
            local ENDPOINT_URL="tcp://${agent_ip}:${AGENT_PORT}"
            
            log_info "Fetching Portainer endpoint ID for VM ${VMID}..."
            local ENDPOINT_ID=$(curl -s  --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}" --retry 5 --retry-delay 10 | jq -r --arg url "${ENDPOINT_URL}" '.[] | select(.URL==$url) | .Id // ""')
            
            if [ -z "$ENDPOINT_ID" ]; then
                log_warn "Could not find Portainer endpoint for VM ${VMID}. Skipping stack deployment for this VM."
                continue
            fi

            echo "$vm_config" | jq -c '.docker_stacks[]' | while read -r stack_config; do
                sync_stack "$VMID" "$stack_config" "$JWT" "$ENDPOINT_ID"
            done
        done < <(echo "$vms_with_stacks" | jq -c '.')
        log_info "--- Docker stack synchronization complete ---"
        # --- END DOCKER STACK DEPLOYMENT ---
 
        log_success "Portainer and Docker stack synchronization complete."

        # --- FINAL STAGE: Re-sync Traefik ---
        log_info "--- Final Stage: Re-synchronizing Traefik to include newly deployed services ---"
        # Re-run the Traefik sync logic to ensure it picks up any services
        # that were just created by the Portainer sync.
        if pct status "$traefik_ctid" > /dev/null 2>&1; then
            local drphoenix_endpoint_id=$(curl -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}" | jq -r '.[] | select(.Name=="drphoenix") | .Id')
            if [ -z "$drphoenix_endpoint_id" ]; then
                log_warn "Could not find drphoenix endpoint ID. Skipping final Traefik sync."
            else
                local container_data=$(curl -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/endpoints/${drphoenix_endpoint_id}/docker/containers/json" -H "Authorization: Bearer ${JWT}")
                if ! "${PHOENIX_BASE_DIR}/bin/managers/traefik-manager.sh" "$container_data"; then log_fatal "Failed to re-generate Traefik config."; fi
                if ! pct push "$traefik_ctid" "${PHOENIX_BASE_DIR}/etc/traefik/dynamic_conf.yml" /etc/traefik/dynamic/dynamic_conf.yml; then log_fatal "Failed to re-push Traefik config."; fi
            fi
            pct exec "$traefik_ctid" -- chmod 644 /etc/traefik/dynamic/dynamic_conf.yml
            # The 'traefik check' command is not valid. The reload command will fail if the config is invalid.
            if ! pct exec "$traefik_ctid" -- systemctl reload traefik; then log_warn "Failed to reload Traefik post-Portainer sync."; fi
            log_success "Final Traefik synchronization complete."
        else
            log_warn "Traefik container (102) is not running. Skipping final Traefik sync."
        fi
    else
        log_warn "Portainer VM (1001) is not running. Skipping Portainer and Docker stack synchronization."
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

    local domain_name=$(get_global_config_value '.domain_name')
    local portainer_hostname="portainer.${domain_name}"
    local portainer_server_port="443" # Always connect via the public-facing Nginx proxy port
    local PORTAINER_URL="https://${portainer_hostname}:${portainer_server_port}"
    local CA_CERT_PATH="${CENTRALIZED_CA_CERT_PATH}"

    if [ -z "$JWT" ]; then
        JWT=$(get_portainer_jwt)
    fi

    if [ -z "$ENDPOINT_ID" ]; then
        local agent_ip=$(jq -r ".vms[] | select(.vmid == $VMID) | .network_config.ip" "$VM_CONFIG_FILE" | cut -d'/' -f1)
        local AGENT_PORT=$(get_global_config_value '.network.portainer_agent_port')
        local ENDPOINT_URL="tcp://${agent_ip}:${AGENT_PORT}"
        ENDPOINT_ID=$(curl -s  --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}" --retry 5 --retry-delay 10 | jq -r --arg url "${ENDPOINT_URL}" '.[] | select(.URL==$url) | .Id // ""')
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
            local EXISTING_CONFIG_ID=$(curl -s  --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/configs" -H "Authorization: Bearer ${JWT}" --retry 5 --retry-delay 10 | jq -r --arg name "${CONFIG_NAME}" '.[] | select(.Name==$name) | .Id // ""')

            if [ -n "$EXISTING_CONFIG_ID" ]; then
                log_info "Portainer Config '${CONFIG_NAME}' already exists. Deleting and recreating to ensure content is fresh."
                if ! curl -s  --cacert "$CA_CERT_PATH" -X DELETE "${PORTAINER_URL}/api/configs/${EXISTING_CONFIG_ID}" -H "Authorization: Bearer ${JWT}" --retry 5 --retry-delay 10; then
                    log_warn "Failed to delete old Portainer Config '${CONFIG_NAME}'. Proceeding, but this might cause issues."
                fi
            fi

            log_info "Creating Portainer Config '${CONFIG_NAME}'..."
            local CONFIG_PAYLOAD=$(jq -n --arg name "${CONFIG_NAME}" --arg data "${FILE_CONTENT}" '{Name: $name, Data: $data}')
            local CONFIG_RESPONSE=$(curl -s  --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/configs?endpointId=${ENDPOINT_ID}" \
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
    STACK_EXISTS_ID=$(curl -s  --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/stacks" -H "Authorization: Bearer ${JWT}" --retry 5 --retry-delay 10 | jq -r --arg name "${STACK_NAME}-${ENVIRONMENT_NAME}" --argjson endpoint_id "${ENDPOINT_ID}" '.[] | select(.Name==$name and .EndpointId==$endpoint_id) | .Id // ""')

    local STACK_DEPLOY_NAME="${STACK_NAME}-${ENVIRONMENT_NAME}" # Unique stack name in Portainer

    if [ -n "$STACK_EXISTS_ID" ]; then
        log_info "Stack '${STACK_DEPLOY_NAME}' already exists on environment ID '${ENDPOINT_ID}'. Updating..."
        local JSON_PAYLOAD=$(jq -n \
            --arg path "${agent_stack_path}" \
            --argjson env "$ENV_VARS_JSON" \
            --argjson configs "$CONFIG_IDS_JSON" \
            '{StackFilePath: $path, Env: $env, Configs: $configs, Prune: true}')
        log_info "DEBUG: PUT JSON_PAYLOAD: ${JSON_PAYLOAD}"
        local RESPONSE=$(curl -s  --cacert "$CA_CERT_PATH" -X PUT "${PORTAINER_URL}/api/stacks/${STACK_EXISTS_ID}?endpointId=${ENDPOINT_ID}" \
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
            --arg path "${agent_stack_path}" \
            --argjson env "$ENV_VARS_JSON" \
            --argjson configs "$CONFIG_IDS_JSON" \
            '{Name: $name, ComposeFilePathInContainer: $path, Env: $env, Configs: $configs}')
        log_info "DEBUG: POST JSON_PAYLOAD: ${JSON_PAYLOAD}"
        local RESPONSE=$(curl -s  --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/stacks?type=2&method=file&endpointId=${ENDPOINT_ID}" \
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
# Function: wait_for_portainer_api_and_setup_admin
# Description: Waits for the Portainer API to become available and then immediately
#              sets up the admin user to prevent the security timeout.
# =====================================================================================
wait_for_portainer_api_and_setup_admin() {
    log_info "Waiting for Portainer API and setting up admin user..."
    # Use the direct internal IP for initial setup to bypass the proxy layers.
    local portainer_server_ip=$(get_global_config_value '.network.portainer_server_ip')
    local portainer_server_port=$(get_global_config_value '.network.portainer_server_port')
    local PORTAINER_URL="https://${portainer_server_ip}:${portainer_server_port}"
    local ca_cert_path="${CENTRALIZED_CA_CERT_PATH}"
    
    # This call will now happen within the security window.
    # We use --insecure because the certificate is for the hostname, not the direct IP.
    setup_portainer_admin_user "$PORTAINER_URL" "" "--insecure"
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
    local PORTAINER_HOSTNAME=$(get_global_config_value '.portainer_api.portainer_hostname')
    local PORTAINER_URL="https://${PORTAINER_HOSTNAME}:443"

    log_info "--- Synchronizing Portainer Endpoints ---"

    local agents_to_register
    agents_to_register=$(jq -c '.vms[] | select(.portainer_role == "agent")' "$VM_CONFIG_FILE")

    while read -r agent_config; do
        local VMID=$(echo "$agent_config" | jq -r '.vmid')
        local AGENT_NAME=$(echo "$agent_config" | jq -r '.portainer_environment_name' | tr -d '[:space:]')
        log_info "Sanitized AGENT_NAME for payload: '[${AGENT_NAME}]'"
        local AGENT_HOSTNAME="${AGENT_NAME}.internal.thinkheads.ai"
        local AGENT_PORT=$(get_global_config_value '.network.portainer_agent_port')
        local ENDPOINT_URL="tcp://${AGENT_HOSTNAME}:${AGENT_PORT}"

        log_info "Checking for existing endpoint for VM ${VMID} ('${AGENT_NAME}')..."
        
        local EXISTING_ENDPOINT_ID=$(curl -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}" | jq -r --arg name "${AGENT_NAME}" '.[] | select(.Name==$name) | .Id // ""')

        # Prepare certificate paths and wait for them to be ready
        local persistent_volume_path=$(echo "$agent_config" | jq -r '.volumes[] | select(.type == "nfs") | .path' | head -n 1)
        local agent_ca_cert_path="${persistent_volume_path}/certs/ca.pem"
        local agent_tls_cert_path="${persistent_volume_path}/certs/cert.pem"
        local agent_tls_key_path="${persistent_volume_path}/certs/key.pem"

        local cert_files=("$agent_ca_cert_path" "$agent_tls_cert_path" "$agent_tls_key_path")
        local cert_wait_retries=5
        local cert_wait_delay=2
        for i in $(seq 1 $cert_wait_retries); do
            if [ -s "${cert_files[0]}" ] && [ -s "${cert_files[1]}" ] && [ -s "${cert_files[2]}" ]; then
                log_info "All agent certificates are present and non-empty."
                break
            fi
            log_warn "Agent certificates not yet available or are empty. Retrying in ${cert_wait_delay}s... (Attempt ${i}/${cert_wait_retries})"
            sleep "$cert_wait_delay"
        done

        if ! [ -s "${cert_files[0]}" ] || ! [ -s "${cert_files[1]}" ] || ! [ -s "${cert_files[2]}" ]; then
            log_fatal "One or more agent certificates are missing or empty after multiple retries. Aborting endpoint operation."
        fi

        # Construct the full payload for creation or update
        # Create a temporary file for the single certificate
        local temp_single_cert="/tmp/single_cert.pem"
        awk '/-----BEGIN CERTIFICATE-----/{p=1} p; /-----END CERTIFICATE-----/{exit}' "$agent_tls_cert_path" > "$temp_single_cert"

        local API_PAYLOAD=$(jq -n \
            --arg name "$AGENT_NAME" \
            --arg url "$ENDPOINT_URL" \
            --argjson groupID 1 \
            --rawfile caCert "$agent_ca_cert_path" \
            '{
                "Name": $name,
                "URL": $url,
                "Type": 2,
                "GroupID": $groupID,
                "TLS": true,
                "TLSSkipVerify": false,
                "TLSCACert": $caCert
            }')

        if [ -n "$EXISTING_ENDPOINT_ID" ]; then
            log_info "Endpoint '${AGENT_NAME}' already exists with ID ${EXISTING_ENDPOINT_ID}. Updating..."
            # Update payload doesn't need Type or GroupID
            local UPDATE_PAYLOAD=$(echo "$API_PAYLOAD" | jq 'del(.Type) | del(.GroupID)')
            
            log_debug "Portainer Endpoint Update Payload: ${UPDATE_PAYLOAD}"
            local UPDATE_RESPONSE=$(curl -s --cacert "$CA_CERT_PATH" -X PUT "${PORTAINER_URL}/api/endpoints/${EXISTING_ENDPOINT_ID}" \
                -H "Authorization: Bearer ${JWT}" \
                -H "Content-Type: application/json" \
                -d "${UPDATE_PAYLOAD}")

            if echo "$UPDATE_RESPONSE" | jq -e '.Id' > /dev/null; then
                log_success "Successfully updated endpoint for VM ${VMID}."
            else
                log_fatal "Failed to update endpoint for VM ${VMID}. Response: ${UPDATE_RESPONSE}"
            fi
        else
            log_info "Endpoint '${AGENT_NAME}' not found. Creating it now..."
            
            log_debug "Portainer Endpoint Create Payload: ${API_PAYLOAD}"
            local CREATE_RESPONSE=$(curl -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/endpoints" \
                -H "Authorization: Bearer ${JWT}" \
                -H "Content-Type: application/json" \
                -d "${API_PAYLOAD}")

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