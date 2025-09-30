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
    local template_image
    template_image=$(echo "$vm_config" | jq -r '.template_image // ""')

    if [ -n "$clone_from_vmid" ]; then
        clone_vm "$VMID"
    elif [ -n "$template" ] || [ -n "$template_image" ]; then
        create_vm_from_template "$VMID"
    else
        log_fatal "VM configuration for $VMID must specify either 'clone_from_vmid', 'template', or 'template_image'."
    fi
}

# =====================================================================================
# Function: create_vm_from_template
# Description: Creates a new VM from a cloud image template.
# Arguments:
#   $1 - The VMID of the VM to create.
# =====================================================================================
create_vm_from_template() {
    local VMID="$1"
    log_info "Creating VM $VMID from template..."

    local vm_config
    vm_config=$(jq -r ".vms[] | select(.vmid == $VMID)" "$VM_CONFIG_FILE")
    local template_image
    template_image=$(echo "$vm_config" | jq -r '.template_image // ""')
    local storage_pool
    storage_pool=$(jq -r "(.vms[] | select(.vmid == $VMID) | .storage_pool) // .vm_defaults.storage_pool" "$VM_CONFIG_FILE")
    local network_bridge
    network_bridge=$(jq -r "(.vms[] | select(.vmid == $VMID) | .network_bridge) // .vm_defaults.network_bridge" "$VM_CONFIG_FILE")

    if [ -z "$template_image" ] || [ -z "$storage_pool" ] || [ -z "$network_bridge" ]; then
        log_fatal "VM configuration for $VMID is missing 'template_image', 'storage_pool', or 'network_bridge'."
    fi

    local image_url="https://cloud-images.ubuntu.com/noble/current/${template_image}"
    local download_path="/tmp/${template_image}"

    if [ ! -f "$download_path" ]; then
        log_info "Downloading Ubuntu cloud image from $image_url..."
        if ! wget -O "$download_path" "$image_url"; then
            log_fatal "Failed to download cloud image."
        fi
    else
        log_info "Cloud image already downloaded."
    fi

    log_info "Installing qemu-guest-agent into the cloud image..."
    if ! virt-customize -a "$download_path" --install qemu-guest-agent --run-command 'systemctl enable qemu-guest-agent'; then
        log_fatal "Failed to customize cloud image."
    fi

    log_info "Creating VM $VMID..."
    local vm_name
    vm_name=$(echo "$vm_config" | jq -r '.name // ""')
    run_qm_command create "$VMID" --name "$vm_name" --memory 2048 --net0 "virtio,bridge=${network_bridge}" --scsihw virtio-scsi-pci --serial0 socket --vga serial0

    log_info "Importing downloaded disk to ${storage_pool}..."
    run_qm_command set "$VMID" --scsi0 "${storage_pool}:0,import-from=${download_path}"

    log_info "Configuring Cloud-Init drive..."
    run_qm_command set "$VMID" --ide2 "${storage_pool}:cloudinit"

    log_info "Setting boot order..."
    run_qm_command set "$VMID" --boot order=scsi0

    log_info "Cleaning up downloaded image file..."
    rm -f "$download_path"
}

# =====================================================================================
# Function: clone_vm
# Description: Clones an existing VM to create a new one.
# Arguments:
#   $1 - The VMID of the new VM to create.
# =====================================================================================
clone_vm() {
    local VMID="$1"
    log_info "Cloning VM $VMID..."

    local vm_config
    vm_config=$(jq -r ".vms[] | select(.vmid == $VMID)" "$VM_CONFIG_FILE")
    local clone_from_vmid
    clone_from_vmid=$(echo "$vm_config" | jq -r '.clone_from_vmid // ""')
    local new_vm_name
    new_vm_name=$(echo "$vm_config" | jq -r '.name // ""')

    if [ -z "$clone_from_vmid" ]; then
        log_fatal "VM configuration for $VMID is missing 'clone_from_vmid'."
    fi

    run_qm_command clone "$clone_from_vmid" "$VMID" --name "$new_vm_name" --full
}

# =====================================================================================
# Function: apply_vm_configurations
# Description: Applies network and user configurations to a VM.
# Arguments:
#   $1 - The VMID of the VM to configure.
# =====================================================================================
apply_vm_configurations() {
    local VMID="$1"
    log_info "Applying configurations to VM $VMID..."

    local vm_config
    vm_config=$(jq -r ".vms[] | select(.vmid == $VMID)" "$VM_CONFIG_FILE")
    local network_config
    network_config=$(echo "$vm_config" | jq -r '.network_config // ""')
    local user_config
    user_config=$(echo "$vm_config" | jq -r '.user_config // ""')

    if [ -n "$network_config" ]; then
        local ip
        ip=$(echo "$network_config" | jq -r '.ip // ""')
        local gw
        gw=$(echo "$network_config" | jq -r '.gw // ""')
        run_qm_command set "$VMID" --ipconfig0 "ip=${ip},gw=${gw}"
    fi

    if [ -n "$user_config" ]; then
        local username
        username=$(echo "$user_config" | jq -r '.username // ""')
        local user_data_template
        user_data_template="${PHOENIX_BASE_DIR}/etc/cloud-init/user-data.template.yml"
        local temp_user_data
        temp_user_data=$(mktemp)

        sed "s/__HOSTNAME__/$(echo "$vm_config" | jq -r '.name')/g; s/__USERNAME__/${username}/g" "$user_data_template" > "$temp_user_data"
        
        local storage_pool
        storage_pool=$(jq -r "(.vms[] | select(.vmid == $VMID) | .storage_pool) // .vm_defaults.storage_pool" "$VM_CONFIG_FILE")
        run_qm_command set "$VMID" --cicustom "user=${storage_pool}:cloudinit"
        
        local snippet_file="/var/lib/vz/snippets/vm-${VMID}-user-data.yml"
        mv "$temp_user_data" "$snippet_file"
        run_qm_command set "$VMID" --cicustom "user=local:snippets/vm-${VMID}-user-data.yml"
    fi
}

# =====================================================================================
# Function: main_vm_orchestrator
# Description: The main entry point for the VM manager script. It parses the
#              action and VMID, and then executes the appropriate lifecycle
#              operations for the VM.
#
# Arguments:
#   $1 - The action to perform (e.g., "create", "start", "stop").
#   $2 - The VMID of the target VM.
# =====================================================================================
main_vm_orchestrator() {
    local action="$1"
    local vmid="$2"

    case "$action" in
        create)
            log_info "Starting 'create' workflow for VMID $vmid..."
            orchestrate_vm "$vmid"
            log_info "'create' workflow completed for VMID $vmid."
            ;;
        start)
            log_info "Starting 'start' workflow for VMID $vmid..."
            start_vm "$vmid"
            log_info "'start' workflow completed for VMID $vmid."
            ;;
        stop)
            log_info "Starting 'stop' workflow for VMID $vmid..."
            run_qm_command stop "$vmid" || log_fatal "Failed to stop VM $vmid."
            log_info "'stop' workflow completed for VMID $vmid."
            ;;
        restart)
            log_info "Starting 'restart' workflow for VMID $vmid..."
            run_qm_command stop "$vmid" || log_warn "Failed to stop VM $vmid before restart."
            start_vm "$vmid"
            log_info "'restart' workflow completed for VMID $vmid."
            ;;
        delete)
            log_info "Starting 'delete' workflow for VMID $vmid..."
            run_qm_command stop "$vmid" || log_warn "VM $vmid was not running before deletion."
            run_qm_command destroy "$vmid" || log_fatal "Failed to delete VM $vmid."
            log_info "'delete' workflow completed for VMID $vmid."
            ;;
        *)
            log_error "Invalid action '$action' for vm-manager."
            exit 1
            ;;
    esac
}

# If the script is executed directly, call the main orchestrator
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_vm_orchestrator "$@"
fi