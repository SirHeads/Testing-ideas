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
# Function: get_portainer_jwt
# Description: Authenticates with the Portainer API and retrieves a JWT.
#
# Returns:
#   The JWT on success, or exits with a fatal error on failure.
# =====================================================================================
get_portainer_jwt() {
    log_info "Attempting to authenticate with Portainer API..."
    local PORTAINER_HOSTNAME="portainer.internal.thinkheads.ai"
    local GATEWAY_URL="https://${PORTAINER_HOSTNAME}"
    local USERNAME=$(get_global_config_value '.portainer_api.admin_user')
    local PASSWORD=$(get_global_config_value '.portainer_api.admin_password')
    local CA_CERT_PATH="${CENTRALIZED_CA_CERT_PATH}"

    # --- Robust API Ready Wait ---
    local MAX_WAIT_ATTEMPTS=12
    local WAIT_INTERVAL=5
    log_info "Waiting for Portainer API to be fully initialized..."
    for ((i=1; i<=MAX_WAIT_ATTEMPTS; i++)); do
        local status_response
        status_response=$(curl -s --cacert "$CA_CERT_PATH" --resolve "${PORTAINER_HOSTNAME}:443:10.0.0.153" "${GATEWAY_URL}/api/system/status")
        if echo "$status_response" | jq -e '.InstanceID' > /dev/null; then
            log_success "Portainer API is initialized and ready."
            break
        fi
        log_info "Portainer not yet initialized. Waiting ${WAIT_INTERVAL}s... (Attempt ${i}/${MAX_WAIT_ATTEMPTS})"
        sleep "$WAIT_INTERVAL"
    done

    if ! echo "$status_response" | jq -e '.InstanceID' > /dev/null; then
        log_fatal "Portainer API did not initialize within the expected time."
    fi
    # --- End Robust API Ready Wait ---

    log_debug "Gateway URL: ${GATEWAY_URL}"
    log_debug "Portainer Username: ${USERNAME}"
    log_debug "Portainer Password (first 3 chars): ${PASSWORD:0:3}..."

    if [ ! -f "$CA_CERT_PATH" ]; then
        log_fatal "CA certificate file not found at: ${CA_CERT_PATH}. Cannot authenticate with Portainer API."
    fi

    local JWT=""
    local AUTH_PAYLOAD
    AUTH_PAYLOAD=$(jq -n --arg user "$USERNAME" --arg pass "$PASSWORD" '{username: $user, password: $pass}')

    local JWT_RESPONSE
    JWT_RESPONSE=$(retry_api_call -X POST \
        -H "Content-Type: application/json" \
        --cacert "$CA_CERT_PATH" \
        --resolve "${PORTAINER_HOSTNAME}:443:10.0.0.153" \
        -d "$AUTH_PAYLOAD" \
        "${GATEWAY_URL}/api/auth" --verbose)

    if [ -n "$JWT_RESPONSE" ]; then
        JWT=$(echo "$JWT_RESPONSE" | jq -r '.jwt // ""')
    fi

    if [ -z "$JWT" ]; then
      log_fatal "Failed to authenticate with Portainer API after multiple attempts."
    fi
    log_success "Successfully authenticated with Portainer API."
    echo "$JWT"
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

    log_info "Setting ownership of certs directory to nobody:nogroup for NFS access..."
    if ! chown -R nobody:nogroup "$hypervisor_cert_dir"; then
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
                    run_qm_command guest exec "$VMID" -- /bin/bash -c "cd $(dirname "$compose_file_path") && docker compose down -v --remove-orphans" || log_warn "Portainer stack was not running or failed to stop cleanly."
                    log_info "Forcefully removing Portainer data volume to ensure a clean slate..."
                    run_qm_command guest exec "$VMID" -- docker volume rm portainer_portainer_data || log_warn "Portainer data volume did not exist or could not be removed."
                    log_info "--- PORTAINER RESET COMPLETE ---"
                fi

                # --- DYNAMIC CERTIFICATE GENERATION ---
                # Certificates are still stored on the host for renewal purposes, but are copied into the container.
                local portainer_fqdn=$(get_global_config_value '.portainer_api.portainer_hostname')
                local hypervisor_cert_dir="/usr/local/phoenix_hypervisor/persistent-storage/portainer/certs"
                ensure_portainer_certificates "$VMID" "/usr/local/phoenix_hypervisor/persistent-storage" "$portainer_fqdn"

                # --- PREPARE FILES FOR PUSHING TO VM ---
                log_info "Preparing Portainer files for deployment to VM..."
                local temp_deploy_dir=$(mktemp -d)
                cp "${PHOENIX_BASE_DIR}/stacks/portainer_service/docker-compose.yml" "${temp_deploy_dir}/docker-compose.yml"
                cp -r "$hypervisor_cert_dir" "${temp_deploy_dir}/certs"

                # Modify the compose file for TLS
                yq -i -y '.services.portainer.command = "--tlsverify --tlscert /certs/portainer.crt --tlskey /certs/portainer.key" | .services.portainer.volumes += ["./certs:/certs"]' "${temp_deploy_dir}/docker-compose.yml"

                # --- PUSH FILES TO VM ---
                log_info "Pushing compose file and certificates to VM ${VMID}..."
                run_qm_command guest exec "$VMID" -- mkdir -p "$(dirname "$compose_file_path")"
                if ! qm_push_dir "$VMID" "$temp_deploy_dir" "$(dirname "$compose_file_path")"; then
                    log_fatal "Failed to push Portainer deployment files to VM ${VMID}."
                fi
                log_info "Setting correct ownership on deployment directory in VM..."
                run_qm_command guest exec "$VMID" -- /bin/chown -R phoenix_user:phoenix_user "/home/phoenix_user/portainer"
                rm -rf "$temp_deploy_dir" # Clean up temp directory

                log_info "Ensuring clean restart for Portainer server on VM $VMID..."
                local DOCKER_TLS_DIR="/etc/docker/tls"
                local DOCKER_CERT_FILE="${DOCKER_TLS_DIR}/cert.pem"
                local DOCKER_KEY_FILE="${DOCKER_TLS_DIR}/key.pem"
                local DOCKER_CA_FILE="${DOCKER_TLS_DIR}/ca.pem"
                local DOCKER_TLS_FLAGS="--tls --tlscert=${DOCKER_CERT_FILE} --tlskey=${DOCKER_KEY_FILE} --tlscacert=${DOCKER_CA_FILE}"
 
                qm guest exec "$VMID" -- /bin/bash -c "cd $(dirname "$compose_file_path") && docker ${DOCKER_TLS_FLAGS} compose down -v --remove-orphans" || log_warn "Portainer server was not running or failed to stop cleanly."
                qm guest exec "$VMID" -- /bin/bash -c "docker ${DOCKER_TLS_FLAGS} rm -f portainer_server" || log_warn "Portainer server container was not running or failed to remove cleanly."
 
                 log_info "Executing docker compose up -d for Portainer server on VM $VMID..."
                if [ "$PHOENIX_DRY_RUN" = "true" ]; then
                    log_info "DRY-RUN: Would execute 'docker compose up -d' for Portainer server on VM $VMID."
                else
                    if ! qm guest exec "$VMID" -- /bin/bash -c "cd $(dirname ${compose_file_path}) && docker compose -f ${compose_file_path} up -d"; then
                        log_fatal "Failed to deploy Portainer server on VM $VMID."
                    fi
                fi
                log_info "Portainer server deployment initiated on VM $VMID."
                
                # --- BEGIN IMMEDIATE ADMIN SETUP ---
                log_info "Waiting for Portainer API and setting up admin user..."
                local portainer_server_ip="10.0.0.111"
                local portainer_server_port="9443" # Use HTTPS port now
                local PORTAINER_URL="https://${portainer_server_ip}:${portainer_server_port}"
                setup_portainer_admin_user "$PORTAINER_URL" "" "--insecure" # Use insecure for initial setup against IP
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
                    if openssl x509 -in "$cert_file" -checkend 86400 >/dev/null 2>&1; then
                        log_info "Existing Portainer Agent certificate is valid. Skipping generation."
                    else
                        log_warn "Existing Portainer Agent certificate is expiring or invalid. Generating a new one."
                    fi
                fi
                
                log_info "Requesting new Portainer Agent certificate for ${agent_fqdn}..."
                step ca bootstrap --ca-url "https://10.0.0.10:9000" --fingerprint "$(cat /mnt/pve/quickOS/lxc-persistent-data/103/ssl/root_ca.fingerprint)" --force
                local vm_ip=$(jq_get_vm_value "$VMID" ".network_config.ip" | cut -d'/' -f1)
                step ca certificate "$agent_fqdn" "$cert_file" "$key_file" --provisioner "admin@thinkheads.ai" --provisioner-password-file "/mnt/pve/quickOS/lxc-persistent-data/103/ssl/provisioner_password.txt" --force --san "$vm_ip" || log_fatal "Failed to obtain Portainer Agent certificate."
                
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
                local docker_command="docker run -d -p 127.0.0.1:${agent_port}:9001 --name portainer_agent --restart=always \
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

    log_info "Attempting to create initial admin user '${ADMIN_USERNAME}'..."

    while [ "$attempt" -le "$MAX_RETRIES" ]; do
        log_info "Admin user creation attempt ${attempt}/${MAX_RETRIES}..."
        
        local response
        local http_status
        
        # Construct curl arguments
        local curl_args=(-s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Content-Type: application/json" --data '{"Username":"'"$ADMIN_USERNAME"'", "Password":"'"$ADMIN_PASSWORD"'"}' "${PORTAINER_URL}/api/users/admin/init")
        [ -n "$CURL_EXTRA_ARGS" ] && curl_args+=($CURL_EXTRA_ARGS)

        response=$(curl "${curl_args[@]}")
        http_status=$(echo -e "$response" | tail -n1 | sed -n 's/.*HTTP_STATUS://p')
        body=$(echo -e "$response" | sed '$d')

        log_debug "Admin creation response body: ${body}"
        log_debug "Admin creation HTTP status: ${http_status}"

        if [[ "$http_status" -eq 200 ]]; then
            log_success "Portainer admin user '${ADMIN_USERNAME}' created successfully."
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
# Function: sync_all
# Description: Synchronizes all Portainer environments and deploys all associated stacks.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error on failure.
# =====================================================================================
sync_all() {
    local reset_portainer_on_sync=${1:-false}
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


    # --- STAGE 2: DEPLOY & VERIFY UPSTREAM SERVICES ---
    log_info "--- Stage 2: Deploying and Verifying Portainer ---"
    local portainer_vmid="1001"
    if qm status "$portainer_vmid" > /dev/null 2>&1; then
        log_info "Portainer VM (1001) is running. Proceeding with deployment."
        
        deploy_portainer_instances "$reset_portainer_on_sync"
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

    # --- STAGE 4: CONFIGURE GATEWAY ---
    log_info "--- Stage 4: Synchronizing NGINX Gateway ---"
    log_info "Generating and applying dynamic NGINX gateway configuration..."
    if ! "${PHOENIX_BASE_DIR}/bin/generate_nginx_gateway_config.sh"; then
        log_fatal "Failed to generate dynamic NGINX configuration."
    fi
    if ! pct push 101 "${PHOENIX_BASE_DIR}/etc/nginx/sites-available/gateway" /etc/nginx/sites-available/gateway; then
        log_fatal "Failed to push generated gateway config to NGINX container."
    fi
   log_info "Creating symbolic link to enable NGINX gateway site..."
   if ! pct exec 101 -- ln -sf /etc/nginx/sites-available/gateway /etc/nginx/sites-enabled/gateway; then
       log_fatal "Failed to create symbolic link for NGINX gateway."
   fi
    log_info "Reloading Nginx in container 101..."
    if ! pct exec 101 -- systemctl reload nginx; then
        log_fatal "Failed to reload Nginx in container 101." "pct exec 101 -- journalctl -u nginx -n 50"
    fi
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

    # --- STAGE 5: SYNCHRONIZE STACKS ---
    log_info "--- Stage 5: Synchronizing Portainer Endpoints and Docker Stacks ---"
    # --- FIX: Proactively restart Portainer to avoid security timeout before API calls ---
    log_info "Proactively restarting Portainer container to reset security timeout..."
    run_qm_command guest exec "$portainer_vmid" -- /bin/bash -c "docker restart portainer_server" || log_warn "Failed to restart Portainer container. It may not have been running."
    log_info "Waiting for Portainer to initialize after restart..."
    sleep 15 # Give Portainer ample time to initialize after restart

    local JWT=$(get_portainer_jwt | tr -d '\n')
    if [ -z "$JWT" ]; then
        log_fatal "Failed to get Portainer JWT. Aborting stack synchronization."
    fi
    local CA_CERT_PATH="${CENTRALIZED_CA_CERT_PATH}"
    sync_portainer_endpoints "$JWT" "$CA_CERT_PATH"
    
    log_info "Discovering all available Docker stacks..."
    local all_stacks_config
    all_stacks_config=$(discover_stacks)
    if [ -z "$all_stacks_config" ] || [ "$all_stacks_config" == "{}" ]; then
        log_info "No stacks found to synchronize."
        log_info "--- Full System State Synchronization Finished ---"
        return
    fi
    log_info "Discovered stacks: $(echo "$all_stacks_config" | jq 'keys_unsorted | join(", ")')"

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
        endpoints_response=$(retry_api_call --cacert "$CA_CERT_PATH" --resolve "${PORTAINER_HOSTNAME}:443:10.0.0.153" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}")
        local ENDPOINT_ID=$(echo "$endpoints_response" | jq -r --arg url "${ENDPOINT_URL}" '.[] | select(.URL==$url) | .Id // ""')
        
        if [ -z "$ENDPOINT_ID" ]; then
            log_warn "Could not find Portainer endpoint for VM ${VMID}. Skipping stack deployment."
            continue
        fi

        echo "$vm_config" | jq -r '.docker_stacks[]' | while read -r stack_name; do
            # We assume the "production" environment by default for now.
            # This could be made more flexible in the future if needed.
            sync_stack "$VMID" "$stack_name" "production" "$all_stacks_config" "$JWT" "$ENDPOINT_ID"
        done
    done < <(echo "$vms_with_stacks" | jq -c '.')
    log_info "--- Docker stack synchronization complete ---"

    # --- FINAL HEALTH CHECK ---
    # wait_for_system_ready

    log_info "--- Full System State Synchronization Finished ---"
}

# =====================================================================================
# Function: sync_stack
# Description: Synchronizes a specific Docker stack to a given VM's Portainer environment
#              using the new convention-based directory structure.
# Arguments:
#   $1 - The VMID of the target VM.
#   $2 - The name of the stack (corresponds to the directory name in /stacks).
#   $3 - The name of the environment to deploy (e.g., "production").
#   $4 - A JSON object containing all discovered stack configurations.
#   $5 - (Optional) The JWT for Portainer API authentication.
#   $6 - (Optional) The Portainer Endpoint ID.
# Returns:
#   None. Exits with a fatal error on failure.
# =====================================================================================
sync_stack() {
    local VMID="$1"
    local STACK_NAME="$2"
    local ENVIRONMENT_NAME="$3"
    local ALL_STACKS_CONFIG="$4"
    local JWT="${5:-}"
    local ENDPOINT_ID="${6:-}"

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
        endpoints_response=$(retry_api_call --cacert "$CA_CERT_PATH" --resolve "${portainer_hostname}:443:10.0.0.153" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}")
        ENDPOINT_ID=$(echo "$endpoints_response" | jq -r --arg url "${ENDPOINT_URL}" '.[] | select(.URL==$url) | .Id // ""')
        if [ -z "$ENDPOINT_ID" ]; then
            log_fatal "Could not find Portainer environment for VMID ${VMID} (URL: ${ENDPOINT_URL}). Ensure agent is running and environment is created."
        fi
    fi

    local STACK_MANIFEST=$(echo "$ALL_STACKS_CONFIG" | jq -r --arg name "$STACK_NAME" '.[$name]')
    if [ -z "$STACK_MANIFEST" ] || [ "$STACK_MANIFEST" == "null" ]; then
        log_fatal "Stack '${STACK_NAME}' not found in discovered configurations."
    fi

    local STACK_DEFINITION=$(echo "$STACK_MANIFEST" | jq -r --arg env "$ENVIRONMENT_NAME" '.environments[$env]')
    if [ -z "$STACK_DEFINITION" ] || [ "$STACK_DEFINITION" == "null" ]; then
        log_fatal "Environment '${ENVIRONMENT_NAME}' not found for stack '${STACK_NAME}'."
    fi

    local FULL_COMPOSE_PATH="${PHOENIX_BASE_DIR}/stacks/${STACK_NAME}/docker-compose.yml"
    if [ ! -f "$FULL_COMPOSE_PATH" ]; then
        log_fatal "Compose file not found for stack '${STACK_NAME}' at ${FULL_COMPOSE_PATH}."
    fi

    # --- BEGIN IN-MEMORY DEPLOYMENT LOGIC ---
    log_info "Preparing stack content for API deployment to VM ${VMID}..."

    # Create a temporary file to hold the modified compose file
    local temp_compose_file
    temp_compose_file=$(mktemp)
    cp "$FULL_COMPOSE_PATH" "$temp_compose_file"

    # --- BEGIN TRAEFIK LABEL INJECTION ---
    log_info "Injecting Traefik labels into temporary compose file for stack '${STACK_NAME}'..."
    local services_to_label
    services_to_label=$(echo "$STACK_DEFINITION" | jq -r '.services | keys[] // ""')
    for service_name in $services_to_label; do
        local labels
        labels=$(echo "$STACK_DEFINITION" | jq -c ".services.\"${service_name}\".traefik_labels // []")
        if [ "$(echo "$labels" | jq 'length')" -gt 0 ]; then
            log_info "  Injecting labels for service: ${service_name}"
            local yq_script=""
            echo "$labels" | jq -r '.[]' | while read -r label; do
                # Ensure the label is properly escaped for yq
                local escaped_label
                escaped_label=$(printf '%s\n' "$label" | sed "s/'/''/g")
                yq_script+=" .services.\"${service_name}\".labels += ['${escaped_label}'] |"
            done
            yq_script=${yq_script%?} # Remove trailing pipe
            yq eval -i "$yq_script" "$temp_compose_file"
        fi
    done
    log_success "Traefik label injection complete."
    # --- END TRAEFIK LABEL INJECTION ---

    # Read the final, modified compose file content into a variable
    local stack_file_content
    stack_file_content=$(cat "$temp_compose_file")
    rm "$temp_compose_file" # Clean up the temporary file

    # --- Handle Docker Volumes ---
    log_info "Ensuring external Docker volumes exist for stack '${STACK_NAME}' on VM ${VMID}..."
    local volumes_to_create=$(yq e '.volumes | keys | .[]' "$temp_compose_file")
    for volume_name in $volumes_to_create; do
        local is_external=$(yq e ".volumes.${volume_name}.external" "$temp_compose_file")
        if [ "$is_external" == "true" ]; then
            log_info "  - Ensuring external volume '${volume_name}' exists..."
            # This command is idempotent. It will create the volume if it doesn't exist,
            # and do nothing if it already exists.
            run_qm_command guest exec "$VMID" -- /bin/bash -c "docker volume create ${volume_name}"
        fi
    done

    # --- Handle Environment Variables ---
    local ENV_VARS_JSON="[]"
    local variables_array=$(echo "$STACK_DEFINITION" | jq -c '.variables // []')
    if [ "$(echo "$variables_array" | jq 'length')" -gt 0 ]; then
        ENV_VARS_JSON=$(echo "$variables_array" | jq -c '. | map({name: .name, value: .value})')
    fi

    # --- Handle Configuration Files (Portainer Configs) ---
    local CONFIG_IDS_JSON="[]"
    local files_array=$(echo "$STACK_DEFINITION" | jq -c '.files // []')
    if [ "$(echo "$files_array" | jq 'length')" -gt 0 ]; then
        local temp_config_ids="[]"
        echo "$files_array" | jq -c '.[]' | while read -r file_config; do
            local SOURCE_PATH=$(echo "$file_config" | jq -r '.source')
            local DESTINATION_PATH=$(echo "$file_config" | jq -r '.destination_in_container')
            local CONFIG_NAME="${STACK_NAME}-${ENVIRONMENT_NAME}-$(basename "$SOURCE_PATH" | tr '.' '-')"

            local full_source_path="${PHOENIX_BASE_DIR}/stacks/${STACK_NAME}/${SOURCE_PATH}"
            if [ ! -f "$full_source_path" ]; then
                log_fatal "Source config file not found: ${full_source_path} for stack '${STACK_NAME}'."
            fi
            local FILE_CONTENT=$(cat "$full_source_path")

            local configs_response
            configs_response=$(retry_api_call -s --cacert "$CA_CERT_PATH" --resolve "${portainer_hostname}:443:10.0.0.153" -X GET "${PORTAINER_URL}/api/configs" -H "Authorization: Bearer ${JWT}")
            local EXISTING_CONFIG_ID=$(echo "$configs_response" | jq -r --arg name "${CONFIG_NAME}" '.[] | select(.Name==$name) | .Id // ""')

            if [ -n "$EXISTING_CONFIG_ID" ]; then
                log_info "Portainer Config '${CONFIG_NAME}' already exists. Deleting and recreating..."
                retry_api_call --cacert "$CA_CERT_PATH" --resolve "${portainer_hostname}:443:10.0.0.153" -X DELETE "${PORTAINER_URL}/api/configs/${EXISTING_CONFIG_ID}" -H "Authorization: Bearer ${JWT}"
            fi

            log_info "Creating Portainer Config '${CONFIG_NAME}'..."
            local CONFIG_PAYLOAD=$(jq -n --arg name "${CONFIG_NAME}" --arg data "${FILE_CONTENT}" '{Name: $name, Data: $data}')
            local CONFIG_RESPONSE
            CONFIG_RESPONSE=$(retry_api_call --cacert "$CA_CERT_PATH" --resolve "${portainer_hostname}:443:10.0.0.153" -X POST "${PORTAINER_URL}/api/configs?endpointId=${ENDPOINT_ID}" \
              -H "Authorization: Bearer ${JWT}" -H "Content-Type: application/json" -d "${CONFIG_PAYLOAD}")
            local NEW_CONFIG_ID=$(echo "$CONFIG_RESPONSE" | jq -r '.Id // ""')
            
            if [ -z "$NEW_CONFIG_ID" ]; then
                log_fatal "Failed to create Portainer Config '${CONFIG_NAME}'. Response: ${CONFIG_RESPONSE}"
            fi
            temp_config_ids=$(echo "$temp_config_ids" | jq --arg id "$NEW_CONFIG_ID" --arg dest "$DESTINATION_PATH" '. + [{configId: $id, fileName: $dest}]')
        done
        CONFIG_IDS_JSON="$temp_config_ids"
    fi

    local STACK_DEPLOY_NAME="${STACK_NAME}-${ENVIRONMENT_NAME}"
    local stacks_response
    stacks_response=$(retry_api_call --cacert "$CA_CERT_PATH" --resolve "${portainer_hostname}:443:10.0.0.153" -X GET "${PORTAINER_URL}/api/stacks" -H "Authorization: Bearer ${JWT}")
    local STACK_EXISTS_ID=$(echo "$stacks_response" | jq -r --arg name "$STACK_DEPLOY_NAME" --argjson endpoint_id "${ENDPOINT_ID}" '.[] | select(.Name==$name and .EndpointId==$endpoint_id) | .Id // ""')

    if [ -n "$STACK_EXISTS_ID" ]; then
        log_info "Stack '${STACK_DEPLOY_NAME}' already exists. Updating..."
        log_info "Updating stack '${STACK_DEPLOY_NAME}' using in-memory content..."
        local JSON_PAYLOAD
        JSON_PAYLOAD=$(jq -n \
            --arg content "$stack_file_content" \
            --argjson env "$ENV_VARS_JSON" \
            --argjson configs "$CONFIG_IDS_JSON" \
            '{StackFileContent: $content, Env: $env, Configs: $configs, Prune: true}')
        
        local RESPONSE
        RESPONSE=$(retry_api_call --cacert "$CA_CERT_PATH" --resolve "${portainer_hostname}:443:10.0.0.153" -X PUT "${PORTAINER_URL}/api/stacks/${STACK_EXISTS_ID}?endpointId=${ENDPOINT_ID}" \
          -H "Authorization: Bearer ${JWT}" -H "Content-Type: application/json" -d "${JSON_PAYLOAD}")
        if ! echo "$RESPONSE" | jq -e '.Id' > /dev/null; then
          log_fatal "Failed to update stack '${STACK_DEPLOY_NAME}'. Response: ${RESPONSE}"
        fi
        log_success "Stack '${STACK_DEPLOY_NAME}' updated successfully."
    else
        log_info "Stack '${STACK_DEPLOY_NAME}' does not exist. Deploying..."
        log_info "Deploying stack '${STACK_DEPLOY_NAME}' using in-memory content..."
        local JSON_PAYLOAD
        JSON_PAYLOAD=$(jq -n \
            --arg name "${STACK_DEPLOY_NAME}" \
            --arg content "$stack_file_content" \
            --argjson env "$ENV_VARS_JSON" \
            --argjson configs "$CONFIG_IDS_JSON" \
            '{Name: $name, StackFileContent: $content, Env: $env, Configs: $configs}')
        
        local RESPONSE
        RESPONSE=$(retry_api_call --cacert "$CA_CERT_PATH" --resolve "${portainer_hostname}:443:10.0.0.153" -X POST "${PORTAINER_URL}/api/stacks?type=2&method=string&endpointId=${ENDPOINT_ID}" \
          -H "Authorization: Bearer ${JWT}" -H "Content-Type: application/json" -d "${JSON_PAYLOAD}")
        if ! echo "$RESPONSE" | jq -e '.Id' > /dev/null; then
          log_fatal "Failed to deploy stack '${STACK_DEPLOY_NAME}'. Response: ${RESPONSE}"
        fi
        log_success "Stack '${STACK_DEPLOY_NAME}' deployed successfully."
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
        local ENDPOINT_URL="https://${AGENT_HOSTNAME}:${AGENT_PORT}"

        log_info "Checking for existing endpoint for VM ${VMID} ('${AGENT_NAME}')..."
        
        local endpoints_response
        endpoints_response=$(retry_api_call --cacert "$CA_CERT_PATH" --resolve "${PORTAINER_HOSTNAME}:443:10.0.0.153" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}")
        local EXISTING_ENDPOINT_ID=$(echo "$endpoints_response" | jq -r --arg name "${AGENT_NAME}" '.[] | select(.Name==$name) | .Id // ""')

        if [ -n "$EXISTING_ENDPOINT_ID" ]; then
            log_info "Endpoint '${AGENT_NAME}' already exists with ID ${EXISTING_ENDPOINT_ID}. Skipping creation."
        else
            log_info "Endpoint '${AGENT_NAME}' not found. Creating it now as a secure TLS endpoint..."
            
            # Correctly escape the CA content for JSON
            local ca_content_escaped
            ca_content_escaped=$(jq -R -s . /mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt)

            local CREATE_RESPONSE
            CREATE_RESPONSE=$(jq -n \
                --arg name "$AGENT_NAME" \
                --arg url "$ENDPOINT_URL" \
                --argjson groupID 1 \
                --argjson ca_content "$ca_content_escaped" \
                '{ "Name": $name, "URL": $url, "Type": 2, "GroupID": $groupID, "TLS": true, "TLSSkipVerify": true, "TLSCACertFileContent": $ca_content }' | \
                retry_api_call --cacert "$CA_CERT_PATH" --resolve "${PORTAINER_HOSTNAME}:443:10.0.0.153" -X POST "${PORTAINER_URL}/api/endpoints" \
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