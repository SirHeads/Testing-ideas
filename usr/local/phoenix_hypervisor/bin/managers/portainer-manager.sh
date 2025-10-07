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

# --- Load external configurations ---
HYPERVISOR_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_hypervisor_config.json"
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
    log_info "Authenticating with Portainer API..."
    local PORTAINER_URL="https://$(get_global_config_value '.network.portainer_server_ip'):$(get_global_config_value '.network.portainer_server_port')"
    local USERNAME=$(get_global_config_value '.portainer_api.admin_user')
    local PASSWORD=$(get_global_config_value '.portainer_api.admin_password')
    local CA_CERT_PATH="${PHOENIX_BASE_DIR}/persistent-storage/ssl/portainer.phoenix.local.crt"

    if [ ! -f "$CA_CERT_PATH" ]; then
        log_fatal "CA certificate file not found at: ${CA_CERT_PATH}. Cannot authenticate with Portainer API."
    fi

    local JWT
    JWT=$(curl -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/auth" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\"}" | jq -r '.jwt // ""')

    if [ -z "$JWT" ]; then
      log_fatal "Failed to authenticate with Portainer API. Check credentials and SSL certificate."
    fi
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

    local vms_with_portainer
    vms_with_portainer=$(jq -c '.vms[] | select(.portainer_role != "none")' "$VM_CONFIG_FILE")

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

                # Ensure the compose file and config.json are present on the VM's persistent storage
                # These files are copied by vm-manager.sh during feature_install_docker.sh
                if ! qm guest exec "$VMID" -- /bin/bash -c "test -f $compose_file_path"; then
                    log_fatal "Portainer server compose file not found in VM $VMID at $compose_file_path."
                fi
                if ! qm guest exec "$VMID" -- /bin/bash -c "test -f $config_json_path"; then
                    log_warn "Portainer server config.json not found in VM $VMID at $config_json_path. Declarative endpoints may not be created."
                fi

                log_info "Executing docker compose up -d for Portainer server on VM $VMID..."
                if ! qm guest exec "$VMID" -- /bin/bash -c "cd $(dirname "$compose_file_path") && docker compose up -d"; then
                    log_fatal "Failed to deploy Portainer server on VM $VMID."
                fi
                log_info "Portainer server deployment initiated on VM $VMID."
                ;;
            agent)
                log_info "Deploying Portainer agent on VM $VMID..."
                local agent_script_path="${vm_mount_point}/.phoenix_scripts/portainer_agent_setup.sh"

                if ! qm guest exec "$VMID" -- /bin/bash -c "test -f $agent_script_path"; then
                    log_fatal "Portainer agent setup script not found in VM $VMID at $agent_script_path."
                fi

                log_info "Executing Portainer agent setup script on VM $VMID..."
                if ! qm guest exec "$VMID" -- /bin/bash -c "$agent_script_path"; then
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
    local portainer_server_ip=$(get_global_config_value '.network.portainer_server_ip')
    local portainer_server_port=$(get_global_config_value '.network.portainer_server_port')
    local cert_path="${PHOENIX_BASE_DIR}/persistent-storage/ssl/portainer.phoenix.local.crt"

    if ! "${PHOENIX_BASE_DIR}/bin/health_checks/check_portainer_api.sh" "$portainer_server_ip" "$portainer_server_port" "$cert_path"; then
        log_fatal "Portainer API health check failed. Cannot proceed with environment and stack synchronization."
    fi
    log_info "Portainer API is responsive."

    local JWT=$(get_portainer_jwt)
    local PORTAINER_URL="https://${portainer_server_ip}:${portainer_server_port}"
    local CA_CERT_PATH="${PHOENIX_BASE_DIR}/persistent-storage/ssl/portainer.phoenix.local.crt"

    # 3. Process each agent VM to create/update environments (endpoints)
    local agent_vms_json
    agent_vms_json=$(jq -c '[.vms[] | select(.portainer_role == "agent")]' "$VM_CONFIG_FILE")

    echo "$agent_vms_json" | jq -c '.[]' | while read -r agent_vm; do
        local AGENT_IP=$(echo "$agent_vm" | jq -r '.network_config.ip' | cut -d'/' -f1)
        local AGENT_NAME=$(echo "$agent_vm" | jq -r '.name')
        local AGENT_PORT=$(get_global_config_value '.network.portainer_agent_port')

        log_info "Synchronizing environment for agent: ${AGENT_NAME} at ${AGENT_IP}"

        local ENDPOINT_URL="tcp://${AGENT_IP}:${AGENT_PORT}"
        local ENDPOINT_ID=$(curl -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}" | jq -r --arg url "${ENDPOINT_URL}" '.[] | select(.URL==$url) | .Id // ""')

        if [ -z "$ENDPOINT_ID" ]; then
          log_info "Creating environment for ${AGENT_NAME}..."
          local JSON_PAYLOAD=$(jq -n --arg name "${AGENT_NAME}" --arg url "${ENDPOINT_URL}" '{Name: $name, EndpointType: 2, URL: $url, PublicURL: "", TLS: true, TLSSkipVerify: true}')
          
          local RESPONSE=$(curl -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/endpoints" \
            -H "Authorization: Bearer ${JWT}" -H "Content-Type: application/json" -d "${JSON_PAYLOAD}")

          ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.Id // ""')
          if [ -z "$ENDPOINT_ID" ]; then
              log_error "Failed to create environment for ${AGENT_NAME}. Response: ${RESPONSE}"
              continue
          fi
          log_info "Environment for ${AGENT_NAME} created with ID: ${ENDPOINT_ID}"
        else
          log_info "Environment for ${AGENT_NAME} already exists with ID: ${ENDPOINT_ID}"
        fi

        # 4. Deploy/Update stacks associated with this agent
        echo "$agent_vm" | jq -r '.docker_stacks[]?' | while read -r STACK_CONFIG_JSON; do
            log_info "Synchronizing stack '$(echo "$STACK_CONFIG_JSON" | jq -r '.name')' (environment: '$(echo "$STACK_CONFIG_JSON" | jq -r '.environment')') for environment '${AGENT_NAME}'"
            sync_stack "$VMID" "$STACK_CONFIG_JSON" "$JWT" "$ENDPOINT_ID"
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

    local portainer_server_ip=$(get_global_config_value '.network.portainer_server_ip')
    local portainer_server_port=$(get_global_config_value '.network.portainer_server_port')
    local PORTAINER_URL="https://${portainer_server_ip}:${portainer_server_port}"
    local CA_CERT_PATH="${PHOENIX_BASE_DIR}/persistent-storage/ssl/portainer.phoenix.local.crt"

    if [ -z "$JWT" ]; then
        JWT=$(get_portainer_jwt)
    fi

    if [ -z "$ENDPOINT_ID" ]; then
        local agent_ip=$(jq -r ".vms[] | select(.vmid == $VMID) | .network_config.ip" "$VM_CONFIG_FILE" | cut -d'/' -f1)
        local AGENT_PORT=$(get_global_config_value '.network.portainer_agent_port')
        local ENDPOINT_URL="tcp://${agent_ip}:${AGENT_PORT}"
        ENDPOINT_ID=$(curl -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}" | jq -r --arg url "${ENDPOINT_URL}" '.[] | select(.URL==$url) | .Id // ""')
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
            local EXISTING_CONFIG_ID=$(curl -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/configs" -H "Authorization: Bearer ${JWT}" | jq -r --arg name "${CONFIG_NAME}" '.[] | select(.Name==$name) | .Id // ""')

            if [ -n "$EXISTING_CONFIG_ID" ]; then
                log_info "Portainer Config '${CONFIG_NAME}' already exists. Deleting and recreating to ensure content is fresh."
                if ! curl -s --cacert "$CA_CERT_PATH" -X DELETE "${PORTAINER_URL}/api/configs/${EXISTING_CONFIG_ID}" -H "Authorization: Bearer ${JWT}"; then
                    log_warn "Failed to delete old Portainer Config '${CONFIG_NAME}'. Proceeding, but this might cause issues."
                fi
            fi

            log_info "Creating Portainer Config '${CONFIG_NAME}'..."
            local CONFIG_PAYLOAD=$(jq -n --arg name "${CONFIG_NAME}" --arg data "${FILE_CONTENT}" '{Name: $name, Data: $data}')
            local CONFIG_RESPONSE=$(curl -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/configs?endpointId=${ENDPOINT_ID}" \
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
    STACK_EXISTS_ID=$(curl -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/stacks" -H "Authorization: Bearer ${JWT}" | jq -r --arg name "${STACK_NAME}-${ENVIRONMENT_NAME}" --argjson endpoint_id "${ENDPOINT_ID}" '.[] | select(.Name==$name and .EndpointId==$endpoint_id) | .Id // ""')

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
            --arg content "${STACK_CONTENT}" \
            --argjson env "$ENV_VARS_JSON" \
            --argjson configs "$CONFIG_IDS_JSON" \
            '{Name: $name, StackFileContent: $content, Env: $env, Configs: $configs}')
        log_info "DEBUG: POST JSON_PAYLOAD: ${JSON_PAYLOAD}"
        local RESPONSE=$(curl -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/stacks?type=1&method=string&endpointId=${ENDPOINT_ID}" \
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
# Function: main_portainer_orchestrator
# Description: The main entry point for the Portainer manager script. It parses the
#              action and arguments, and then executes the appropriate operations.
# Arguments:
#   $@ - The command-line arguments passed to the script.
# =====================================================================================
main_portainer_orchestrator() {
    local action="$1"
    shift

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