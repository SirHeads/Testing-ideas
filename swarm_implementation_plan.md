# Docker Swarm Integration: Implementation Plan

This document provides the detailed technical specifications for integrating Docker Swarm into the `phoenix-cli`.

## Phase 1: Create the Swarm Manager and Update Configuration

### 1.1. Create `swarm-manager.sh`

Create the following file at `usr/local/phoenix_hypervisor/bin/managers/swarm-manager.sh`. This script will encapsulate all Swarm-related logic.

```bash
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
# FUNCTION: init_swarm
# DESCRIPTION: Initializes a new Docker Swarm on the designated manager node.
# =====================================================================================
init_swarm() {
    log_info "Function: init_swarm - Placeholder"
    # Implementation to be added in Code mode
}

# =====================================================================================
# FUNCTION: generate_join_tokens
# DESCRIPTION: Retrieves the join tokens for both managers and workers.
# =====================================================================================
generate_join_tokens() {
    log_info "Function: generate_join_tokens - Placeholder"
    # Implementation to be added in Code mode
}

# =====================================================================================
# FUNCTION: join_swarm
# DESCRIPTION: Joins a worker or manager node to the Swarm.
# =====================================================================================
join_swarm() {
    log_info "Function: join_swarm - Placeholder"
    # Implementation to be added in Code mode
}

# =====================================================================================
# FUNCTION: label_node
# DESCRIPTION: Applies labels from phoenix_vm_configs.json to a Swarm node.
# =====================================================================================
label_node() {
    log_info "Function: label_node - Placeholder"
    # Implementation to be added in Code mode
}

# =====================================================================================
# FUNCTION: deploy_stack
# DESCRIPTION: Deploys a Docker stack to the Swarm with environment-specific naming.
# =====================================================================================
deploy_stack() {
    log_info "Function: deploy_stack - Placeholder"
    # Implementation to be added in Code mode
}

# =====================================================================================
# FUNCTION: remove_stack
# DESCRIPTION: Removes an environment-specific stack from the Swarm.
# =====================================================================================
remove_stack() {
    log_info "Function: remove_stack - Placeholder"
    # Implementation to be added in Code mode
}

# =====================================================================================
# FUNCTION: get_swarm_status
# DESCRIPTION: Provides a summary of the Swarm's health.
# =====================================================================================
get_swarm_status() {
    log_info "Function: get_swarm_status - Placeholder"
    # Implementation to be added in Code mode
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
            log_error "Invalid action '$action' for swarm-manager."
            exit 1
            ;;
    esac
}

# If the script is executed directly, call the main dispatcher
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

### 1.2. Update `phoenix_vm_configs.json`

Modify `usr/local/phoenix_hypervisor/etc/phoenix_vm_configs.json` to include the `swarm_role` and `node_labels` attributes for the relevant VMs.

**Apply the following changes:**

*   For VM 1001 ("Portainer"), set `swarm_role` to `"manager"`.
*   For VM 1002 ("drphoenix"), set `swarm_role` to `"worker"` and add a `node_labels` array.

### 1.3. Update Stack Configurations (`phoenix.json`)

Modify the `phoenix.json` file for each stack that will be deployed to the Swarm to include placement constraints.

**Example for `stacks/thinkheads_ai_app/phoenix.json`:**

Add a `placement_constraints` array to the service definition. For services that require a GPU, the constraint should be `["node.labels.gpu == true"]`. For general services, it can be left empty or omitted.

---

## Phase 2: Integrate Swarm Commands into the Phoenix CLI

Modify `usr/local/phoenix_hypervisor/bin/phoenix-cli` to add the new `swarm` verb and its sub-commands.

### 2.1. Add `swarm` to `valid_verbs`

In the `main` function, add `swarm` to the `valid_verbs` list.

### 2.2. Add `swarm` Command Handling

Add a new case to the main command handling logic to route `swarm` commands to the `swarm-manager.sh` script. This new block should handle the various sub-commands (`init`, `join`, `deploy`, `rm`, `status`) and pass the appropriate arguments to the manager script.

```bash
# --- ADD THIS BLOCK TO THE PHOENIX-CLI MAIN FUNCTION ---

    elif [ "$VERB" == "swarm" ]; then
        log_info "Swarm command detected. Routing to swarm-manager.sh..."
        local swarm_action="${TARGETS[0]}"
        shift
        "$SCRIPT_DIR/managers/swarm-manager.sh" "$swarm_action" "$@"
        exit $?
```

## Phase 3: Migrate Portainer to a Swarm Service

The existing Portainer deployment will be migrated to run as a Swarm service.

### 3.1. Update `portainer_service/docker-compose.yml`

Modify `usr/local/phoenix_hypervisor/stacks/portainer_service/docker-compose.yml` to include a `deploy` key. This will ensure Portainer is deployed as a replicated service on the Swarm manager node.

```yaml
# --- ADD THIS 'deploy' KEY TO THE PORTAINER SERVICE DEFINITION ---
deploy:
  replicas: 1
  placement:
    constraints:
      - node.role == manager
```

### 3.2. Update `portainer-manager.sh`

Modify the `deploy_portainer_instances` function in `usr/local/phoenix_hypervisor/bin/managers/portainer-manager.sh` to use the `swarm-manager.sh` to deploy Portainer as a service. The existing logic that deploys Portainer to a standalone Docker host will be replaced with a call to `swarm-manager.sh deploy_stack`.

## Phase 4: Adapt Existing Stacks for Swarm Deployment

The existing stacks will be migrated to the new Swarm-compatible format.

### 4.1. Create `phoenix.json` Manifests

For each existing stack (`qdrant_service`, `thinkheads_ai_app`), create a `phoenix.json` manifest file in the root of the stack's directory. This file will define the stack's metadata and any placement constraints.

**Example for `stacks/qdrant_service/phoenix.json`:**

```json
{
    "description": "Qdrant vector database for RAG.",
    "placement_constraints": []
}
```

### 4.2. Update `docker-compose.yml` Files

For each existing stack, modify the `docker-compose.yml` file to include a `deploy` key for each service. This will specify how the service should be deployed on the Swarm.

**Example for `stacks/qdrant_service/docker-compose.yml`:**

```yaml
# --- ADD THIS 'deploy' KEY TO THE QDRANT SERVICE DEFINITION ---
deploy:
  replicas: 1
  placement:
    constraints: []
```

## Phase 5: Create Documentation for the New Workflow

Create a new documentation file at `Thinkheads.AI_docs/02_technical_strategy_and_architecture/swarm_workflow_guide.md`. This guide will explain the new Swarm-based workflow for managing isolated application environments.

### 5.1. Create `swarm_workflow_guide.md`

The new file should contain the following content:

```markdown
# Swarm Workflow Guide

This guide outlines the new workflow for managing isolated, multi-tenant application environments using the Docker Swarm integration in `phoenix-cli`.

## 1. One-Time Setup

To initialize the Swarm cluster and deploy the Portainer dashboard, run the following command:

```bash
phoenix sync all
```

This command will:
1.  Create the necessary VMs.
2.  Initialize the Docker Swarm.
3.  Join the manager and worker nodes to the Swarm.
4.  Deploy the Portainer service to the manager node.

## 2. Managing Environments

### 2.1. Deploying a New Environment

To deploy a new, isolated environment for a specific stack, use the `phoenix swarm deploy` command:

```bash
phoenix swarm deploy <stack_name> --env <environment_name>
```

For example, to deploy a new development environment for the `thinkheads_ai_app` stack, you would run:

```bash
phoenix swarm deploy thinkheads_ai_app --env dev1
```

This will create a new, isolated environment named `dev1`, with all services, networks, and configs prefixed with `dev1_`.

### 2.2. Removing an Environment

To remove an environment, use the `phoenix swarm rm` command:

```bash
phoenix swarm rm <stack_name> --env <environment_name>
```

For example, to remove the `dev1` environment:

```bash
phoenix swarm rm thinkheads_ai_app --env dev1
```

## 3. Monitoring

The Portainer UI is available for monitoring the state of the Swarm and the various deployed environments. It should be used as a "pane of glass" for observation, not for deployments.
```