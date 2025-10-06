#!/bin/bash
#
# File: portainer_api_setup.sh
# Description: This script automates the entire Portainer setup process via its API.

set -ex

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/phoenix_hypervisor_common_utils.sh"

LOG_FILE="/var/log/phoenix_hypervisor/portainer_api_setup.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec &> >(tee -a "$LOG_FILE")

CONTEXT_FILE="${SCRIPT_DIR}/vm_context.json"
VM_CONFIG_FILE_IN_VM="/persistent-storage/.phoenix_scripts/phoenix_vm_configs.json"
STACKS_CONFIG_FILE_IN_VM="/persistent-storage/.phoenix_scripts/phoenix_stacks_config.json"
HYPERVISOR_CONFIG_FILE_IN_VM="/persistent-storage/.phoenix_scripts/phoenix_hypervisor_config.json"

PORTAINER_URL="https://portainer.phoenix.local"

# =====================================================================================
# Function: wait_for_portainer_api
# Description: Waits for the Portainer API to become available.
# =====================================================================================
wait_for_portainer_api() {
    log_info "Waiting for Portainer API to become available at $PORTAINER_URL..."
    local attempts=0
    local max_attempts=30 # 5 minutes
    local interval=10

    while [ $attempts -lt $max_attempts ]; do
        if curl -s -k --insecure --head "$PORTAINER_URL/api/status" | head -n 1 | grep " 200" > /dev/null; then
            log_info "Portainer API is up."
            return 0
        fi
        log_info "Portainer API not yet available. Retrying in $interval seconds... (Attempt $((attempts + 1))/$max_attempts)"
        sleep $interval
        attempts=$((attempts + 1))
    done

    log_fatal "Portainer API did not become available after $max_attempts attempts."
}

# =====================================================================================
# Function: get_jwt_token
# Description: Retrieves a JWT token from the Portainer API.
# =====================================================================================
get_jwt_token() {
    log_info "Retrieving Portainer JWT token..."
    local admin_user
    admin_user=$(jq -r '.portainer_admin_user' "$CONTEXT_FILE")
    local admin_password
    admin_password=$(jq -r '.portainer_admin_password' "$CONTEXT_FILE")

    local response
    response=$(curl -s -k -w "\n%{http_code}" -X POST \
                    -H "Content-Type: application/json" \
                    --data "{\"username\":\"$admin_user\",\"password\":\"$admin_password\"}" \
                    "$PORTAINER_URL/api/auth")

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local response_body
    response_body=$(echo "$response" | sed '$d')

    if [ "$http_code" -ne 200 ]; then
        log_fatal "Failed to get JWT token. HTTP Code: $http_code, Response: $response_body"
    fi

    local jwt_token
    jwt_token=$(echo "$response_body" | jq -r '.jwt')
    if [ -z "$jwt_token" ] || [ "$jwt_token" == "null" ]; then
        log_fatal "Extracted JWT token is empty."
    fi
    
    echo "$jwt_token"
}

# =====================================================================================
# Function: ensure_agent_endpoint_exists
# Description: Ensures a Portainer endpoint exists for the agent. If it doesn't, it creates one.
# Arguments:
#   $1 - The URL of the Portainer server.
#   $2 - The JWT token.
#   $3 - The name of the agent VM.
#   $4 - The IP address of the agent VM.
# =====================================================================================
ensure_agent_endpoint_exists() {
    local portainer_url="$1"
    local jwt_token="$2"
    local agent_vm_name="$3"
    local agent_vm_ip="$4"
    log_info "Ensuring endpoint exists for agent: $agent_vm_name..."

    local endpoints
    endpoints=$(curl -s -k -H "Authorization: Bearer $jwt_token" "$portainer_url/api/endpoints")
    
    local endpoint_id
    endpoint_id=$(echo "$endpoints" | jq -r ".[] | select(.Name == \"$agent_vm_name\") | .Id")

    if [ -n "$endpoint_id" ] && [ "$endpoint_id" != "null" ]; then
        log_info "Endpoint '$agent_vm_name' already exists with ID: $endpoint_id."
        echo "$endpoint_id"
        return
    fi

    log_info "Endpoint '$agent_vm_name' not found. Creating it..."
    local agent_url="${agent_vm_ip}:9001"
    
    # NEW: Wait for agent to be responsive
    log_info "Waiting for Portainer agent at $agent_url to become responsive..."
    local attempts=0
    local max_attempts=12 # 2 minutes
    local interval=10
    while [ $attempts -lt $max_attempts ]; do
        if curl -s "http://${agent_url}/ping" | grep -q "OK"; then
            log_info "Portainer agent at $agent_url is responsive."
            break
        fi
        log_info "Agent not yet responsive. Retrying in $interval seconds... (Attempt $((attempts + 1))/$max_attempts)"
        sleep $interval
        attempts=$((attempts + 1))
    done

    if [ $attempts -eq $max_attempts ]; then
        log_fatal "Portainer agent at $agent_url did not become responsive."
    fi
    
    local attempts=0
    local max_attempts=5
    local interval=10
    local response
    local http_code
    local response_body
    local new_endpoint_id

    while [ $attempts -lt $max_attempts ]; do
        response=$(curl -s -k -w "\n%{http_code}" -X POST \
                        -H "Authorization: Bearer $jwt_token" \
                        -F "Name=$agent_vm_name" \
                        -F "URL=tcp://${agent_vm_ip}:9001" \
                        -F "EndpointType=2" \
                        -F "GroupId=1" \
                        -F "TLS=true" \
                        -F "TLSSkipVerify=true" \
                        "$portainer_url/api/endpoints")

        http_code=$(echo "$response" | tail -n1)
        response_body=$(echo "$response" | sed '$d')

        if [ "$http_code" -eq 200 ]; then
            new_endpoint_id=$(echo "$response_body" | jq -r '.Id')
            log_info "Endpoint '$agent_vm_name' created successfully with ID: $new_endpoint_id."
            echo "$new_endpoint_id"
            return
        fi
        
        log_warn "Failed to create endpoint for agent '$agent_vm_name' (Attempt $((attempts + 1))/$max_attempts). HTTP Code: $http_code, Response: $response_body"
        attempts=$((attempts + 1))
        sleep $interval
    done

    log_fatal "Failed to create endpoint for agent '$agent_vm_name' after $max_attempts attempts."
}

# =====================================================================================
# Function: verify_agent_connection
# Description: Verifies that the Portainer server can connect to the agent.
# Arguments:
#   $1 - The JWT token.
#   $2 - The endpoint ID.
# =====================================================================================
verify_agent_connection() {
    local jwt_token="$1"
    local endpoint_id="$2"
    log_info "Verifying connection to agent endpoint ID: $endpoint_id..."

    local attempts=0
    local max_attempts=12 # 2 minutes
    local interval=10
    while [ $attempts -lt $max_attempts ]; do
        local response
        response=$(curl -s -k -H "Authorization: Bearer $jwt_token" "$PORTAINER_URL/api/endpoints/$endpoint_id/docker/version")
        if echo "$response" | jq -e '.Version' > /dev/null; then
            log_info "Successfully connected to agent and retrieved Docker version."
            return 0
        fi
        log_warn "Agent connection verification failed. Retrying in $interval seconds... (Attempt $((attempts + 1))/$max_attempts)"
        sleep $interval
        attempts=$((attempts + 1))
    done

    log_fatal "Failed to verify connection to agent endpoint ID: $endpoint_id after $max_attempts attempts."
}

# =====================================================================================
# Function: get_stack_id
# Description: Retrieves the ID of a stack by its name and endpoint.
# Arguments:
#   $1 - The JWT token.
#   $2 - The endpoint ID.
#   $3 - The name of the stack.
# =====================================================================================
get_stack_id() {
    local jwt_token="$1"
    local endpoint_id="$2"
    local stack_name="$3"

    curl -s -k -H "Authorization: Bearer $jwt_token" \
         "$PORTAINER_URL/api/stacks" | \
    jq -r ".[] | select(.Name == \"$stack_name\" and .EndpointId == $endpoint_id) | .Id"
}

# =====================================================================================
# Function: deploy_stack
# Description: Deploys a Docker stack to a specified endpoint.
# Arguments:
#   $1 - The JWT token.
#   $2 - The endpoint ID.
#   $3 - The name of the stack to deploy (must match a key in phoenix_stacks_config.json).
# =====================================================================================
deploy_stack() {
    local jwt_token="$1"
    local endpoint_id="$2"
    local stack_name="$3"

    log_info "Looking up stack configuration for '$stack_name'..."
    local stack_config
    stack_config=$(jq -r ".docker_stacks.\"$stack_name\"" "$STACKS_CONFIG_FILE_IN_VM")

    if [ -z "$stack_config" ] || [ "$stack_config" == "null" ]; then
        log_error "Stack '$stack_name' not found in $STACKS_CONFIG_FILE_IN_VM. Skipping deployment."
        return 1
    fi

    local compose_file_path
    compose_file_path=$(echo "$stack_config" | jq -r '.compose_file_path')
    local stack_dir_name
    stack_dir_name=$(echo "$stack_config" | jq -r '.name')
    
    local full_compose_path="/persistent-storage/stacks/${stack_dir_name}/docker-compose.yml"

    if [ ! -f "$full_compose_path" ]; then
        log_error "Compose file for stack '$stack_name' not found at expected path: $full_compose_path. Skipping."
        return 1
    fi

    local stack_content
    stack_content=$(cat "$full_compose_path")

    local stack_id
    stack_id=$(get_stack_id "$jwt_token" "$endpoint_id" "$stack_dir_name")

    if [ -n "$stack_id" ]; then
        log_info "Stack '$stack_dir_name' already exists with ID $stack_id. Updating it..."
        local response
        response=$(curl -s -k -w "\n%{http_code}" -X PUT \
                        -H "Authorization: Bearer $jwt_token" \
                        -H "Content-Type: application/json" \
                        --data-binary @- \
                        "$PORTAINER_URL/api/stacks/$stack_id?endpointId=$endpoint_id" <<EOF
{
  "stackFileContent": $(echo "$stack_content" | jq -R -s '.'),
  "prune": true
}
EOF
)
        local http_code
        http_code=$(echo "$response" | tail -n1)
        local response_body
        response_body=$(echo "$response" | sed '$d')
        if [ "$http_code" -ne 200 ]; then
            log_error "Failed to update stack '$stack_dir_name'. HTTP Code: $http_code, Response: $response_body"
            return 1
        fi
    else
        log_info "Stack '$stack_dir_name' does not exist. Creating it..."
        local response
        response=$(curl -s -k -w "\n%{http_code}" -X POST \
                        -H "Authorization: Bearer $jwt_token" \
                        -H "Content-Type: application/json" \
                        --data-binary @- \
                        "$PORTAINER_URL/api/stacks?type=2&method=string&endpointId=$endpoint_id" <<EOF
{
  "name": "$stack_dir_name",
  "stackFileContent": $(echo "$stack_content" | jq -R -s '.')
}
EOF
)
        local http_code
        http_code=$(echo "$response" | tail -n1)
        local response_body
        response_body=$(echo "$response" | sed '$d')
        if [ "$http_code" -ne 200 ]; then
            log_error "Failed to create stack '$stack_dir_name'. HTTP Code: $http_code, Response: $response_body"
            return 1
        fi
    fi
    log_info "Stack deployment request for '$stack_dir_name' sent."
}

main() {
    if [ ! -f "$VM_CONFIG_FILE_IN_VM" ]; then
        log_fatal "VM config file missing: $VM_CONFIG_FILE_IN_VM"
    fi
    if [ ! -f "$STACKS_CONFIG_FILE_IN_VM" ]; then
        log_fatal "Stacks config file missing: $STACKS_CONFIG_FILE_IN_VM"
    fi

    local VMID
    VMID=$(jq -r '.vmid' "$CONTEXT_FILE")

    wait_for_portainer_api
    
    local jwt_token
    jwt_token=$(get_jwt_token)

    # This script now runs on the Portainer server, so it deploys stacks to *other* agents
    # We need to find all agents and ensure their endpoints and stacks are deployed.
    local agent_vmids
    agent_vmids=$(jq -r '.vms[] | select(.portainer_role == "agent") | .vmid' "$VM_CONFIG_FILE_IN_VM")

    if [ -z "$agent_vmids" ]; then
        log_info "No agent VMs found in the configuration. Reconciliation is complete for now."
    else
        for agent_vmid in $agent_vmids; do
            local agent_vm_name
            agent_vm_name=$(jq -r ".vms[] | select(.vmid == $agent_vmid) | .name" "$VM_CONFIG_FILE_IN_VM")
            local agent_vm_ip
            agent_vm_ip=$(jq -r ".vms[] | select(.vmid == $agent_vmid) | .network_config.ip" "$VM_CONFIG_FILE_IN_VM" | cut -d'/' -f1)

            local agent_endpoint_id
            agent_endpoint_id=$(ensure_agent_endpoint_exists "$PORTAINER_URL" "$jwt_token" "$agent_vm_name" "$agent_vm_ip")
            verify_agent_connection "$jwt_token" "$agent_endpoint_id"

            local docker_stacks
            docker_stacks=$(jq -c ".vms[] | select(.vmid == $agent_vmid) | .docker_stacks[]?" "$VM_CONFIG_FILE_IN_VM")

            if [ -z "$docker_stacks" ]; then
                log_info "No docker_stacks to provision for VMID $agent_vmid."
                continue
            fi

            echo "$docker_stacks" | while read -r stack_name_json; do
                local stack_name
                stack_name=$(echo "$stack_name_json" | jq -r '.')
                log_info "Deploying stack '$stack_name' to endpoint '$agent_endpoint_id'..."
                deploy_stack "$jwt_token" "$agent_endpoint_id" "$stack_name"
            done
        done
    fi

    log_info "Portainer API setup and stack deployment complete."
}

main