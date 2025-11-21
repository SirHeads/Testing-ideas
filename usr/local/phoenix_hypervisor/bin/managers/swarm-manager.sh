#!/bin/bash
#
# File: swarm-manager.sh
# Description: This script manages all Docker Swarm-related operations for the Phoenix Hypervisor system.
#              It handles the initialization of the Swarm, joining of manager and worker nodes,
#              and the deployment and removal of environment-specific Docker stacks.
#
# Dependencies:
#   - phoenix_hypervisor_common_utils.sh: A library of shared shell functions.
#   - jq: For parsing JSON configuration files.
#   - docker: For all Swarm commands.
#
# Version: 1.0.0
# Author: Phoenix Hypervisor Team
#

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# --- Source common utilities ---
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"
source "${PHOENIX_BASE_DIR}/bin/managers/vm-manager.sh"

# =====================================================================================
# FUNCTION: get_manager_vmid
# DESCRIPTION: Finds the VMID of the Swarm manager node from the configuration.
# =====================================================================================
get_manager_vmid() {
    jq -r '.vms[] | select(.swarm_role == "manager") | .vmid' "$VM_CONFIG_FILE"
}

# =====================================================================================
# FUNCTION: init_swarm
# DESCRIPTION: Initializes a new Docker Swarm on the designated manager node.
# =====================================================================================
init_swarm() {
    log_info "Initializing Docker Swarm..."
    local manager_vmid=$(get_manager_vmid)
    if [ -z "$manager_vmid" ]; then
        log_fatal "No VM with swarm_role 'manager' found in vm_configs.json."
    fi

    local manager_ip=$(jq_get_vm_value "$manager_vmid" ".network_config.ip" | cut -d'/' -f1)
    
    log_info "Initializing Swarm on manager node VM ${manager_vmid} (${manager_ip})..."
    run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "docker swarm init --advertise-addr ${manager_ip}"
    log_success "Docker Swarm initialized successfully."
}

# =====================================================================================
# FUNCTION: get_join_token
# DESCRIPTION: Retrieves the join token for a specific role (worker or manager).
# =====================================================================================
get_join_token() {
    local role="$1" # "worker" or "manager"
    local manager_vmid=$(get_manager_vmid)
    
    log_info "Retrieving ${role} join token from manager VM ${manager_vmid}..."
    local token_output
    token_output=$(run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "docker swarm join-token -q ${role}")
    
    # The join-token command with -q outputs a raw string, not JSON.
    # We need to extract the raw output directly.
    echo "$token_output" | tr -d '\n'
}

# =====================================================================================
# FUNCTION: join_swarm
# DESCRIPTION: Joins a worker or manager node to the Swarm.
# =====================================================================================
join_swarm() {
    local target_vmid="$1"
    if [ -z "$target_vmid" ]; then
        log_fatal "Usage: phoenix swarm join <vmid>"
    fi

    local swarm_role=$(jq_get_vm_value "$target_vmid" ".swarm_role")
    if [ -z "$swarm_role" ] || [ "$swarm_role" == "null" ]; then
        log_fatal "VM ${target_vmid} does not have a 'swarm_role' defined."
    fi

    local token=$(get_join_token "$swarm_role")
    if [ -z "$token" ]; then
        log_fatal "Failed to retrieve ${swarm_role} join token."
    fi

    local manager_vmid=$(get_manager_vmid)
    local manager_ip=$(jq_get_vm_value "$manager_vmid" ".network_config.ip" | cut -d'/' -f1)
    
    log_info "Joining VM ${target_vmid} to the swarm as a ${swarm_role}..."
    log_info "Ensuring VM ${target_vmid} has left any previous swarm..."
    run_qm_command guest exec "$target_vmid" -- /bin/bash -c "docker swarm leave --force" || log_warn "Node was not part of a swarm, which is normal."
    
    log_info "Joining VM ${target_vmid} to the new swarm as a ${swarm_role}..."
    run_qm_command guest exec "$target_vmid" -- /bin/bash -c "docker swarm join --token ${token} ${manager_ip}:2377"
    
    log_info "Applying node labels to VM ${target_vmid}..."
    label_node "$target_vmid"

    log_success "VM ${target_vmid} successfully joined the swarm."
}

# =====================================================================================
# FUNCTION: label_node
# DESCRIPTION: Applies labels from phoenix_vm_configs.json to a Swarm node.
# =====================================================================================
label_node() {
    local target_vmid="$1"
    local node_labels=$(jq_get_vm_array "$target_vmid" ".node_labels[]")
    
    if [ -z "$node_labels" ]; then
        log_info "No node labels to apply for VM ${target_vmid}."
        return
    fi

    local manager_vmid=$(get_manager_vmid)
    local node_hostname=$(jq_get_vm_value "$target_vmid" ".name")

    for label in $node_labels; do
        log_info "Applying label '${label}' to node ${node_hostname}..."
        run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "docker node update --label-add ${label} ${node_hostname}"
    done
}

# =====================================================================================
# FUNCTION: deploy_stack
# DESCRIPTION: Deploys a Docker stack to the Swarm. If a phoenix.json manifest is present,
#              it dynamically injects environment-specific configurations.
# =====================================================================================
deploy_stack() {
    local stack_name=""
    local env_name=""
    local host_mode=false

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --env)
                env_name="$2"
                shift 2
                ;;
            --host-mode)
                host_mode=true
                shift
                ;;
            *)
                if [ -z "$stack_name" ]; then
                    stack_name="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$stack_name" ] || [ -z "$env_name" ]; then
        log_fatal "Usage: phoenix swarm deploy <stack_name> --env <environment_name>"
    fi

    if ! command -v yq &> /dev/null; then
        log_fatal "'yq' is not installed. Please install it to proceed. (e.g., 'pip install yq')"
    fi

    local stack_dir="/quickOS/portainer_stacks/${stack_name}"
    local compose_file="${stack_dir}/docker-compose.yml"
    local manifest_file="${PHOENIX_BASE_DIR}/etc/phoenix_stacks_config.json"

    if [ ! -f "$compose_file" ]; then
        log_fatal "Stack '${stack_name}' is missing a docker-compose.yml file."
    fi

    local manager_vmid=$(get_manager_vmid)
    local final_stack_name="${env_name}_${stack_name}"

    log_info "Preparing deployment for stack '${stack_name}' in environment '${env_name}'..."
    
    local temp_compose_file=$(mktemp)
    cp "$compose_file" "$temp_compose_file"

    # If a manifest file exists, validate it and perform dynamic substitutions.
    if [ -f "$manifest_file" ]; then
        log_info "Manifest file found. Validating and processing..."
        if ! jq . "$manifest_file" > /dev/null 2>&1; then
            log_fatal "Stack manifest file for '${stack_name}' is not valid JSON. Please check the syntax in: ${manifest_file}"
        fi

        # --- Environment Variable Substitution ---
        log_info "Injecting environment variables..."
        local env_vars_json=$(jq -c --arg stack "$stack_name" --arg env "$env_name" '.docker_stacks[$stack].environments[$env].variables // []' "$manifest_file")
        echo "$env_vars_json" | jq -c '.[]' | while read -r var_obj; do
            local var_name=$(echo "$var_obj" | jq -r '.name')
            local var_value=$(echo "$var_obj" | jq -r '.value')
            log_info "Substituting \${${var_name}} with '${var_value}'"
            sed -i "s|\${${var_name}}|${var_value}|g" "$temp_compose_file"
        done

        # --- Traefik Label Injection (Resilient Logic) ---
        local services_with_labels=$(jq -r --arg stack "$stack_name" --arg env "$env_name" '(.docker_stacks[$stack]? | .environments[$env]? | .services? // {}) | keys | .[]' "$manifest_file")
        for service in $services_with_labels; do
            local labels=$(jq -r --arg stack "$stack_name" --arg env "$env_name" --arg svc "$service" '.docker_stacks[$stack].environments[$env].services[$svc].traefik_labels[]? // ""' "$manifest_file")
            if [ -n "$labels" ]; then
                log_info "Injecting Traefik labels for service '${service}'..."
                local yq_expr=".services.\"$service\".deploy.labels = [$(echo "$labels" | jq -R . | jq -s -c . | sed 's/\[//;s/\]//')]"
                yq -i -y "$yq_expr" "$temp_compose_file"
            fi
        done
    else
        log_info "No manifest file found. Proceeding with standard docker-compose.yml."
    fi

    log_info "Deploying stack '${final_stack_name}' using dynamically generated compose file..."
    local nfs_stacks_path="/mnt/stacks"
    local temp_vm_compose_path="${nfs_stacks_path}/${stack_name}/docker-compose.tmp.yml"
    
    # The 'sync_stack_files' rsyncs the whole stacks dir, so we just need to place the temp file in the correct location on the host.
    local nfs_share_path="/quickOS/portainer_stacks"
    local final_temp_path="${nfs_share_path}/${stack_name}/docker-compose.tmp.yml"
    cp "$temp_compose_file" "$final_temp_path"
    chmod 644 "$final_temp_path"
    
    # The command is executed *inside* the guest, so it uses the local docker socket, not a remote TCP host.
    # --- Diagnostic Logging ---
    log_debug "--- BEGIN DYNAMIC COMPOSE FILE ---"
    log_debug "$(cat "$temp_compose_file")"
    log_debug "--- END DYNAMIC COMPOSE FILE ---"

    local deploy_command="docker stack deploy --compose-file ${temp_vm_compose_path} --with-registry-auth ${final_stack_name}"
    
    # --- Diagnostic Logging ---
    log_debug "Final deploy command to be executed in guest: ${deploy_command}"

    run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "$deploy_command"

    # --- Cleanup ---
    rm "$temp_compose_file"
    rm "${nfs_share_path}/${stack_name}/docker-compose.tmp.yml"

    log_success "Stack '${final_stack_name}' deployed successfully."
}

# =====================================================================================
# FUNCTION: remove_stack
# DESCRIPTION: Removes an environment-specific stack from the Swarm.
# =====================================================================================
remove_stack() {
    local stack_name="$1"
    local env_name="$3" # expecting --env <name>

    if [ -z "$stack_name" ] || [ -z "$env_name" ]; then
        log_fatal "Usage: phoenix swarm rm <stack_name> --env <environment_name>"
    fi

    local manager_vmid=$(get_manager_vmid)
    local final_stack_name="${env_name}_${stack_name}"

    log_info "Removing stack '${final_stack_name}'..."
    run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "docker stack rm ${final_stack_name}"
    log_success "Stack '${final_stack_name}' removed successfully."
}

# =====================================================================================
# FUNCTION: get_swarm_status
# DESCRIPTION: Provides a summary of the Swarm's health.
# =====================================================================================
get_swarm_status() {
    log_info "Getting Docker Swarm status..."
    local manager_vmid=$(get_manager_vmid)
    run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "docker node ls"
}

# =====================================================================================
# Main Dispatcher
# =====================================================================================
main() {
    local action="$1"
    shift

    case "$action" in
        init)
            init_swarm "$@"
            ;;
        join)
            join_swarm "$@"
            ;;
        deploy)
            deploy_stack "$@"
            ;;
        rm)
            remove_stack "$@"
            ;;
        status)
            get_swarm_status "$@"
            ;;
        *)
            log_error "Invalid action '$action' for swarm-manager. Valid actions: init, join, deploy, rm, status"
            exit 1
            ;;
    esac
}

# If the script is executed directly, call the main dispatcher
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi