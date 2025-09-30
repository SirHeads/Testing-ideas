#!/bin/bash
#
# File: vm-manager.sh
# Description: This script manages all VM-related operations for the Phoenix Hypervisor system.

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# --- Source common utilities ---
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# =====================================================================================
# Function: run_qm_command
# Description: A robust wrapper for executing `qm` (Proxmox QEMU/KVM) commands. It handles
#              logging and dry-run mode, ensuring that all VM operations are consistently
#              managed.
#
# Arguments:
#   $@ - The `qm` command and its arguments.
#
# Returns:
#   0 on success, 1 on failure.
# =====================================================================================
run_qm_command() {
    local cmd_description="qm $*" # Description of the command for logging
    log_info "Executing: $cmd_description"
    echo "Executing: $cmd_description"
    # If dry-run mode is enabled, log the command without executing it
    if [ "$DRY_RUN" = true ]; then
        log_info "Dry-run: Skipping actual command execution."
        return 0
    fi
    # Execute the `qm` command
    if ! qm "$@"; then
        log_error "Command failed: $cmd_description"
        return 1
    fi
    return 0
}

# =====================================================================================
# Function: orchestrate_vm
# Description: The main state machine for VM provisioning. This function orchestrates the
#              entire lifecycle of a VM, from creation and configuration to feature
#              application and snapshotting.
#
# Arguments:
#   $1 - The VMID of the VM to orchestrate.
#
# Returns:
#   None. The function will exit with a fatal error if any step in the orchestration fails.
# =====================================================================================
orchestrate_vm() {
    local VMID="$1"
    shift
    local config_file_override=""
    if [ "$1" == "--config" ]; then
        config_file_override="$2"
        shift 2
    fi

    if [ -n "$config_file_override" ]; then
        VM_CONFIG_FILE="$config_file_override"
    fi

    log_info "Starting orchestration for VMID: $VMID"

    # --- VMID Validation ---
    if ! jq -e ".vms[] | select(.vmid == $VMID)" "$VM_CONFIG_FILE" > /dev/null; then
        log_fatal "Configuration for VMID $VMID not found in $VM_CONFIG_FILE."
    fi
    log_info "VMID $VMID found in configuration file. Proceeding with orchestration."

    log_info "Available storage pools before VM creation:"
    pvesm status
    ensure_vm_defined "$VMID"
    apply_vm_configurations "$VMID"
    start_vm "$VMID"
    # Wait for the VM to boot and the guest agent to be ready
    wait_for_guest_agent "$VMID"
    apply_vm_features "$VMID"
    create_vm_snapshot "$VMID"

    # --- Template Finalization ---
    local is_template
    is_template=$(jq -r ".vms[] | select(.vmid == $VMID) | .is_template" "$VM_CONFIG_FILE")
    if [ "$is_template" == "true" ]; then
        log_info "Finalizing template for VM $VMID..."
        run_qm_command stop "$VMID"
        run_qm_command start "$VMID"
        wait_for_guest_agent "$VMID"
        log_info "Cleaning cloud-init state for template..."
        run_qm_command guest exec "$VMID" -- /bin/bash -c "cloud-init clean"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "rm -f /etc/machine-id"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "touch /etc/machine-id"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "systemctl stop cloud-init"
        run_qm_command stop "$VMID"
        log_info "Creating final template snapshot..."
        create_vm_snapshot "$VMID"
        log_info "Converting VM to template..."
        run_qm_command template "$VMID"
    fi

    log_info "Available storage pools after VM creation:"
    pvesm status

    log_info "VM orchestration for VMID $VMID completed successfully."
}

# =====================================================================================
# Function: ensure_vm_defined
# Description: Checks if the VM exists. If not, it calls the appropriate function to create
#              the VM, either from a template image or by cloning an existing VM. This is
#              a key part of the idempotent state machine for VMs.
#
# Arguments:
#   $1 - The VMID to check.
#
# Returns:
#   None. The function will exit with a fatal error if the VM definition is invalid.
# =====================================================================================
ensure_vm_defined() {
    local VMID="$1"
    log_info "Ensuring VM $VMID is defined..."
    if qm status "$VMID" > /dev/null 2>&1; then
        log_info "VM $VMID already exists. Skipping creation."
        return 0
    fi
    log_info "VM $VMID does not exist. Proceeding with creation..."

    local vm_config
    vm_config=$(jq -r ".vms[] | select(.vmid == $VMID)" "$VM_CONFIG_FILE")
    local clone_from_vmid
    clone_from_vmid=$(echo "$vm_config" | jq -r '.clone_from_vmid // ""')
    local template
    template=$(echo "$vm_config" | jq -r '.template // ""')

    if [ -n "$clone_from_vmid" ]; then
        clone_vm "$VMID"
    elif [ -n "$template" ]; then
        create_vm_from_template "$VMID"
    else
        log_fatal "VM configuration for $VMID must specify either 'clone_from_vmid' or 'template'."
    fi
}