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
    local DOCKER_COMMAND="docker -H tcp://127.0.0.1:2376 --tls --tlscert=/etc/docker/tls/cert.pem --tlskey=/etc/docker/tls/key.pem --tlscacert=/etc/docker/tls/ca.pem"
    run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "${DOCKER_COMMAND} swarm init --advertise-addr ${manager_ip}"
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
    local DOCKER_COMMAND="docker -H tcp://127.0.0.1:2376 --tls --tlscert=/etc/docker/tls/cert.pem --tlskey=/etc/docker/tls/key.pem --tlscacert=/etc/docker/tls/ca.pem"
    token_output=$(run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "${DOCKER_COMMAND} swarm join-token -q ${role}")
    
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
    local DOCKER_COMMAND="docker -H tcp://127.0.0.1:2376 --tls --tlscert=/etc/docker/tls/cert.pem --tlskey=/etc/docker/tls/key.pem --tlscacert=/etc/docker/tls/ca.pem"
    run_qm_command guest exec "$target_vmid" -- /bin/bash -c "${DOCKER_COMMAND} swarm join --token ${token} ${manager_ip}:2377"
    
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
        local DOCKER_COMMAND="docker -H tcp://127.0.0.1:2376 --tls --tlscert=/etc/docker/tls/cert.pem --tlskey=/etc/docker/tls/key.pem --tlscacert=/etc/docker/tls/ca.pem"
        run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "${DOCKER_COMMAND} node update --label-add ${label} ${node_hostname}"
    done
}

# =====================================================================================
# FUNCTION: deploy_stack
# DESCRIPTION: Deploys a Docker stack to the Swarm with environment-specific naming.
# =====================================================================================
deploy_stack() {
    local stack_name="$1"
    local env_name="$3" # expecting --env <name>

    if [ -z "$stack_name" ] || [ -z "$env_name" ]; then
        log_fatal "Usage: phoenix swarm deploy <stack_name> --env <environment_name>"
    fi

    local stack_dir="${PHOENIX_BASE_DIR}/stacks/${stack_name}"
    local compose_file="${stack_dir}/docker-compose.yml"
    local manifest_file="${stack_dir}/phoenix.json"

    if [ ! -f "$compose_file" ] || [ ! -f "$manifest_file" ]; then
        log_fatal "Stack '${stack_name}' not found or is missing required files."
    fi

    local manager_vmid=$(get_manager_vmid)
    local stack_prefix="${env_name}_"
    local final_stack_name="${env_name}_${stack_name}"

    log_info "Deploying stack '${stack_name}' to environment '${env_name}'..."
    
    # We will deploy from the manager node, which has access to the stacks via NFS
    local nfs_stacks_path="/mnt/stacks"
    local vm_compose_path="${nfs_stacks_path}/${stack_name}/docker-compose.yml"

    local DOCKER_COMMAND="docker -H tcp://127.0.0.1:2376 --tls --tlscert=/etc/docker/tls/cert.pem --tlskey=/etc/docker/tls/key.pem --tlscacert=/etc/docker/tls/ca.pem"
    run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "${DOCKER_COMMAND} stack deploy --compose-file ${vm_compose_path} ${final_stack_name}"

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
    local DOCKER_COMMAND="docker -H tcp://127.0.0.1:2376 --tls --tlscert=/etc/docker/tls/cert.pem --tlskey=/etc/docker/tls/key.pem --tlscacert=/etc/docker/tls/ca.pem"
    run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "${DOCKER_COMMAND} stack rm ${final_stack_name}"
    log_success "Stack '${final_stack_name}' removed successfully."
}

# =====================================================================================
# FUNCTION: get_swarm_status
# DESCRIPTION: Provides a summary of the Swarm's health.
# =====================================================================================
get_swarm_status() {
    log_info "Getting Docker Swarm status..."
    local manager_vmid=$(get_manager_vmid)
    local DOCKER_COMMAND="docker -H tcp://127.0.0.1:2376 --tls --tlscert=/etc/docker/tls/cert.pem --tlskey=/etc/docker/tls/key.pem --tlscacert=/etc/docker/tls/ca.pem"
    run_qm_command guest exec "$manager_vmid" -- /bin/bash -c "${DOCKER_COMMAND} node ls"
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