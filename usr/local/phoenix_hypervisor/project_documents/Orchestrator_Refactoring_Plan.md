# Orchestrator Refactoring Plan

## 1. Objective

This document outlines the specific code changes required to refactor `phoenix_orchestrator.sh` to implement the new `Unprivileged_LXC_Creation_Architecture.md`. The goal is to replace the existing flawed orchestration logic with the new, correct-by-construction workflow.

## 2. Proposed Changes

### 2.1. Modify `ensure_container_defined`

This function will be updated to set the `--unprivileged` flag immediately after a container is cloned, based on its JSON configuration.

**Current Logic in `ensure_container_defined`:**
The current function only creates or clones the container.

**New Logic for `ensure_container_defined`:**
```bash
ensure_container_defined() {
    log_info "Ensuring container $CTID is defined..."
    if ! pct status "$CTID" > /dev/null 2>&1; then
        log_info "Container $CTID does not exist. Proceeding with creation..."
        local clone_from_ctid
        clone_from_ctid=$(jq_get_value "$CTID" ".clone_from_ctid" || echo "")

        if [ -n "$clone_from_ctid" ]; then
            clone_container
        else
            create_container_from_template
        fi

        # NEW: Set unprivileged flag immediately after creation if specified in config
        local unprivileged_bool
        unprivileged_bool=$(jq_get_value "$CTID" ".unprivileged")
        if [ "$unprivileged_bool" == "true" ]; then
            # This check is for cloned containers, as create_from_template handles this.
            if ! pct config "$CTID" | grep -q "unprivileged: 1"; then
                 log_info "Setting container $CTID as unprivileged..."
                 run_pct_command set "$CTID" --unprivileged 1 || log_fatal "Failed to set container as unprivileged."
            fi
        fi
    else
        log_info "Container $CTID already exists. Skipping creation."
    fi
}
```

### 2.2. Rename `finalize_container_config` to `generate_idmap_cycle`

The function will be renamed to clarify its purpose.

**New `generate_idmap_cycle` function:**
```bash
generate_idmap_cycle() {
    local ctid="$1"
    log_info "Performing start/stop cycle for CT $ctid to generate idmap..."

    log_info "Starting container $ctid..."
    if ! pct start "$ctid"; then
        log_error "Failed to start container $ctid during idmap generation cycle."
        return 1
    fi

    log_info "Stopping container $ctid..."
    if ! pct stop "$ctid"; then
        log_error "Failed to stop container $ctid during idmap generation cycle."
        return 1
    fi

    log_info "Start/stop cycle for CT $ctid completed."
    return 0
}
```

### 2.3. Create New `verify_idmap_exists` Function

This new function will add the critical safety check to ensure the `idmap` was generated.

**New `verify_idmap_exists` function:**
```bash
verify_idmap_exists() {
    local ctid="$1"
    local conf_file="/etc/pve/lxc/${ctid}.conf"
    log_info "Verifying idmap existence in $conf_file..."

    if [ ! -f "$conf_file" ]; then
        log_fatal "Container config file not found: $conf_file."
    fi

    if ! grep -q "^lxc.idmap:" "$conf_file"; then
        log_fatal "IDMAP VERIFICATION FAILED: No idmap found in $conf_file after generation cycle."
    fi

    log_info "IDMAP verification successful."
}
```

### 2.4. Replace `orchestrate_container` with `orchestrate_container_stateless`

The existing `orchestrate_container` function will be removed and replaced with the new stateless implementation.

**New `orchestrate_container_stateless` function:**
```bash
orchestrate_container_stateless() {
    local CTID="$1"
    log_info "Starting stateless orchestration for CTID $CTID..."

    # 1. Define the container and set unprivileged flag if needed
    ensure_container_defined "$CTID"

    # 2. Apply all other configurations
    ensure_container_configured "$CTID"

    # 3. Perform start/stop cycle to generate idmap
    generate_idmap_cycle "$CTID"

    # 4. Verify idmap was created
    verify_idmap_exists "$CTID"

    # 5. Apply shared volumes now that idmap is guaranteed to exist
    apply_shared_volumes "$CTID"

    # 6. Start the container for application setup
    start_container "$CTID"

    # 7. Apply features and run application scripts
    apply_features "$CTID"
    run_application_script "$CTID"

    # 8. Create snapshot if it's a template
    create_template_snapshot "$CTID"

    log_info "Successfully completed stateless orchestration for CTID $CTID."
}
```

### 2.5. Update `main` function

The `main` function must be updated to call the new `orchestrate_container_stateless` function.

**Updated `main` function call:**
```bash
# ... inside main function ...
    else
        validate_inputs # Validate inputs for LXC container orchestration
        orchestrate_container_stateless "$CTID"
    fi
# ...
```

These changes will align the orchestrator script with the new, robust architecture, resolving the `idmap` issue permanently.