#!/bin/bash
set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/.." &> /dev/null && pwd)

source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# =====================================================================================
# Function: reconcile_portainer
# Description: Main function to orchestrate the Portainer reconciliation process.
# =====================================================================================
reconcile_portainer() {
    log_info "Starting Portainer reconciliation process on the hypervisor..."

    # --- Configuration ---
    local PORTAINER_URL="https://portainer.phoenix.local"
    local USERNAME="admin"
    local PASSWORD
    PASSWORD=$(get_global_config_value '.portainer_api.admin_password')
    local STACKS_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_stacks_config.json"

    # --- 1. Authenticate and get JWT ---
    log_info "Authenticating with Portainer API..."
    local JWT
    local CA_CERT_PATH="${PHOENIX_BASE_DIR}/persistent-storage/ssl/portainer.phoenix.local.crt"

    # Ensure the certificate file exists
    if [ ! -f "$CA_CERT_PATH" ]; then
        log_fatal "CA certificate file not found at: ${CA_CERT_PATH}. Cannot authenticate with Portainer API."
    fi

    JWT=$(curl -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/auth" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\"}" | jq -r '.jwt // ""')

    if [ -z "$JWT" ]; then
      log_fatal "Failed to authenticate with Portainer API. Check credentials and SSL certificate."
    fi
    log_info "Successfully authenticated with Portainer API."

    # --- 2. Process each agent VM to create endpoints ---
    local agent_vms_json
    agent_vms_json=$(jq -c '[.vms[] | select(.portainer_role == "agent")]' "$VM_CONFIG_FILE")

    echo "$agent_vms_json" | jq -c '.[]' | while read -r agent_vm; do
        local AGENT_IP
        AGENT_IP=$(echo "$agent_vm" | jq -r '.network_config.ip' | cut -d'/' -f1)
        local AGENT_NAME
        AGENT_NAME=$(echo "$agent_vm" | jq -r '.name')
        local AGENT_PORT="9001"

        log_info "Processing agent: ${AGENT_NAME} at ${AGENT_IP}"

        # Check if endpoint already exists
        local ENDPOINT_URL="http://${AGENT_IP}:${AGENT_PORT}"
        local ENDPOINT_ID
        ENDPOINT_ID=$(curl -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/endpoints" -H "Authorization: Bearer ${JWT}" | jq -r --arg url "${ENDPOINT_URL}" '.[] | select(.URL==$url) | .Id // ""')

        if [ -z "$ENDPOINT_ID" ]; then
          log_info "Creating endpoint for ${AGENT_NAME}..."
          local JSON_PAYLOAD
          JSON_PAYLOAD=$(jq -n --arg name "${AGENT_NAME}" --arg url "${ENDPOINT_URL}" '{Name: $name, EndpointType: 2, URL: $url, PublicURL: "", TLS: false}')
          
          local RESPONSE
          RESPONSE=$(curl -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/endpoints" \
            -H "Authorization: Bearer ${JWT}" -H "Content-Type: application/json" -d "${JSON_PAYLOAD}")

          ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.Id // ""')
          if [ -z "$ENDPOINT_ID" ]; then
              log_error "Failed to create endpoint for ${AGENT_NAME}. Response: ${RESPONSE}"
              continue
          fi
          log_info "Endpoint for ${AGENT_NAME} created with ID: ${ENDPOINT_ID}"
        else
          log_info "Endpoint for ${AGENT_NAME} already exists with ID: ${ENDPOINT_ID}"
        fi

        # --- 3. Deploy stacks associated with this agent ---
        echo "$agent_vm" | jq -r '.docker_stacks[]?' | while read -r STACK_NAME; do
            log_info "Processing stack '${STACK_NAME}' for agent '${AGENT_NAME}'"
            
            local STACK_EXISTS_ID
            STACK_EXISTS_ID=$(curl -s --cacert "$CA_CERT_PATH" -X GET "${PORTAINER_URL}/api/stacks" -H "Authorization: Bearer ${JWT}" | jq -r --arg name "${STACK_NAME}" --argjson endpoint_id "${ENDPOINT_ID}" '.[] | select(.Name==$name and .EndpointId==$endpoint_id) | .Id // ""')

            if [ -n "$STACK_EXISTS_ID" ]; then
                log_info "Stack '${STACK_NAME}' already exists on this endpoint. Skipping."
                continue
            fi

            local compose_file_path
            compose_file_path=$(jq -r ".docker_stacks.\"${STACK_NAME}\".compose_file_path" "$STACKS_CONFIG_FILE")
            local FULL_COMPOSE_PATH="${PHOENIX_BASE_DIR}/${compose_file_path}"

            if [ ! -f "$FULL_COMPOSE_PATH" ]; then
                log_error "Stack file ${FULL_COMPOSE_PATH} not found. Skipping."
                continue
            fi

            log_info "Deploying stack: ${STACK_NAME}"
            local STACK_CONTENT
            STACK_CONTENT=$(cat "$FULL_COMPOSE_PATH")

            local JSON_PAYLOAD
            JSON_PAYLOAD=$(jq -n --arg name "${STACK_NAME}" --arg content "${STACK_CONTENT}" '{Name: $name, StackFileContent: $content}')

            local RESPONSE
            RESPONSE=$(curl -s --cacert "$CA_CERT_PATH" -X POST "${PORTAINER_URL}/api/stacks?type=1&method=string&endpointId=${ENDPOINT_ID}" \
              -H "Authorization: Bearer ${JWT}" -H "Content-Type: application/json" -d "${JSON_PAYLOAD}")

            if echo "$RESPONSE" | jq -e '.Id' > /dev/null; then
              log_info "Stack '${STACK_NAME}' deployed successfully."
            else
              log_error "Failed to deploy stack '${STACK_NAME}'. Response: ${RESPONSE}"
            fi
        done
    done

    log_success "Portainer reconciliation process completed successfully."
}

# If the script is executed directly, call the main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    reconcile_portainer "$@"
fi