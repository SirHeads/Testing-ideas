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
    local cmd_description="qm $*"
    log_info "Executing qm command: $cmd_description"
    if [ "$DRY_RUN" = true ]; then
        log_info "Dry-run: Skipping actual qm command execution."
        return 0
    fi

    local output
    local exit_code=0
    output=$(qm "$@" 2>&1) || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "Command failed: $cmd_description (Exit Code: $exit_code)"
        log_error "Output:\n$output"
    fi
    return $exit_code
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
        log_fatal "VMID $VMID not found in configuration file: $VM_CONFIG_FILE. Please add a valid VM definition."
    fi
    log_info "VMID $VMID found in configuration file. Proceeding with orchestration."

    log_info "Available storage pools before VM creation:"
    pvesm status

    local is_template
    is_template=$(jq -r ".vms[] | select(.vmid == $VMID) | .is_template" "$VM_CONFIG_FILE")

    if [ "$is_template" == "true" ]; then
        log_info "Step 1: Ensuring VM template $VMID is defined..."
        ensure_vm_defined "$VMID"
        log_info "Step 1: Completed."

        log_info "Step 2: Applying core configurations for VM template $VMID..."
        apply_core_configurations "$VMID"
        log_info "Step 2: Completed."

        log_info "Step 3: Applying network configurations for VM template $VMID..."
        apply_network_configurations "$VMID"
        log_info "Step 3: Completed."

        log_info "Finalizing template for VM $VMID..."
        start_vm "$VMID"
        wait_for_guest_agent "$VMID"

        log_info "Waiting for cloud-init to complete before proceeding..."
        run_qm_command guest exec "$VMID" -- /bin/bash -c "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 5; done"

        log_info "Installing nfs-common in template..."
        if ! run_qm_command guest exec "$VMID" -- /bin/bash -c "apt-get update && apt-get install -y nfs-common"; then
            log_fatal "Failed to install nfs-common in template."
        fi

        log_info "Applying features to VM template $VMID..."
        apply_vm_features "$VMID"
        log_info "Features applied to VM template."

        log_info "Cleaning cloud-init state for template..."
        run_qm_command guest exec "$VMID" -- /bin/bash -c "cloud-init clean"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "rm -f /etc/machine-id"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "touch /etc/machine-id"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "systemctl stop cloud-init"
        stop_vm "$VMID"
        log_info "Creating final template snapshot..."
        manage_snapshots "$VMID" "post-features"
        log_info "Converting VM to template..."
        run_qm_command template "$VMID"
        log_info "Template creation for VMID $VMID completed successfully."
        return 0
    else
        log_info "Step 1: Ensuring VM $VMID is defined..."
        ensure_vm_defined "$VMID"
        log_info "Step 1: Completed."

        log_info "Step 2: Applying core configurations for VM $VMID..."
        apply_core_configurations "$VMID"
        log_info "Step 2: Completed."

        log_info "Step 3: Applying network configurations for VM $VMID..."
        apply_network_configurations "$VMID"
        log_info "Step 3: Completed."

        log_info "Step 4: Starting VM $VMID..."
        start_vm "$VMID"
        log_info "Step 4: Completed."

        log_info "Step 5: Waiting for guest agent on VM $VMID..."
        wait_for_guest_agent "$VMID"
        log_info "Step 5: Completed."

        log_info "Step 6: Applying volumes for VM $VMID..."
        apply_volumes "$VMID"
        log_info "Step 6: Completed."

        log_info "Step 6.5: Provisioning declarative files for VM $VMID..."
        provision_declarative_files "$VMID"
        log_info "Step 6.5: Completed."

        log_info "Step 7: Managing pre-feature snapshots for VM $VMID..."
        manage_snapshots "$VMID" "pre-features"
        log_info "Step 7: Completed."

        log_info "Step 8: Applying features to VM $VMID..."
        apply_vm_features "$VMID"
        log_info "Step 8: Completed."

        log_info "Step 9: Managing post-feature snapshots for VM $VMID..."
        manage_snapshots "$VMID" "post-features"
        log_info "Step 9: Completed."
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
        create_vm_from_image "$VMID" "$template_image"
    else
        log_fatal "VM configuration for $VMID is invalid. It must specify either 'clone_from_vmid' or 'template_image'."
    fi
}

# =====================================================================================
# Function: create_vm_from_image
# Description: Creates a new VM from a cloud image, incorporating best practices from
#              the user-provided guide. This includes downloading the image, injecting
#              the guest agent, creating a base VM, and importing the disk.
#
# Arguments:
#   $1 - The VMID for the new VM.
#   $2 - The name of the template image.
# =====================================================================================
create_vm_from_image() {
    local VMID="$1"
    local template_image="$2"
    log_info "Creating VM $VMID from image ${template_image}..."

    local storage_pool
    storage_pool=$(jq -r ".vm_defaults.storage_pool // \"\"" "$VM_CONFIG_FILE")
    if [ -z "$storage_pool" ]; then
        log_fatal "Missing 'vm_defaults.storage_pool' in $VM_CONFIG_FILE."
    fi
    local network_bridge
    network_bridge=$(jq -r ".vm_defaults.network_bridge // \"\"" "$VM_CONFIG_FILE")
    if [ -z "$network_bridge" ]; then
        log_fatal "Missing 'vm_defaults.network_bridge' in $VM_CONFIG_FILE."
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

    log_info "Installing essential packages (qemu-guest-agent, nfs-common) into the cloud image..."
    if ! virt-customize -a "$download_path" --install qemu-guest-agent,nfs-common --run-command 'systemctl enable qemu-guest-agent'; then
        log_fatal "Failed to customize cloud image with essential packages."
    fi

    log_info "Creating base VM..."
    local vm_name
    vm_name=$(jq -r ".vms[] | select(.vmid == $VMID) | .name" "$VM_CONFIG_FILE")
    run_qm_command create "$VMID" --name "$vm_name" --memory 2048 --net0 "virtio,bridge=${network_bridge}" --agent 1

    log_info "Importing disk to storage pool '$storage_pool'..."
    run_qm_command importdisk "$VMID" "$download_path" "$storage_pool"

    log_info "Configuring VM hardware..."
    run_qm_command set "$VMID" --scsihw virtio-scsi-pci --scsi0 "${storage_pool}:vm-${VMID}-disk-0"
    run_qm_command set "$VMID" --boot c --bootdisk scsi0
    run_qm_command set "$VMID" --ide2 "${storage_pool}:cloudinit"

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
        log_fatal "VM configuration for $VMID is missing the required 'clone_from_vmid' attribute."
    fi
    if [ -z "$new_vm_name" ]; then
        log_fatal "VM configuration for $VMID is missing the required 'name' attribute."
    fi

    log_info "Cloning from VM $clone_from_vmid to new VM $VMID with name '$new_vm_name'."
    run_qm_command clone "$clone_from_vmid" "$VMID" --name "$new_vm_name" --full

    # Apply initial network configurations
    local network_config
    network_config=$(echo "$vm_config" | jq -r '.network_config // ""')
    if [ -n "$network_config" ]; then
        local ip
        ip=$(echo "$network_config" | jq -r '.ip // ""')
        local gw
        gw=$(echo "$network_config" | jq -r '.gw // ""')
        if [ -z "$ip" ] || [ -z "$gw" ]; then
            log_fatal "VM configuration for $VMID has an incomplete network_config. Both 'ip' and 'gw' must be specified."
        fi
        log_info "Applying initial network config: IP=${ip}, Gateway=${gw}"
        run_qm_command set "$VMID" --ipconfig0 "ip=${ip},gw=${gw}"
    fi
    
    # Apply initial user configurations
    local user_config
    user_config=$(echo "$vm_config" | jq -r '.user_config // ""')
    if [ -n "$user_config" ]; then
        local username
        username=$(echo "$user_config" | jq -r '.username // ""')
        if [ -z "$username" ] || [ "$username" == "null" ]; then
            log_warn "VM configuration for $VMID has a 'user_config' section but is missing a 'username'. Skipping user configuration."
        else
            log_info "Applying initial user config: Username=${username}"
            run_qm_command set "$VMID" --ciuser "$username"
        fi
    fi

    log_info "Resizing disk for VM $VMID..."
    run_qm_command resize "$VMID" scsi0 +10G || log_warn "Failed to resize disk for VM $VMID."
}

# =====================================================================================
# Function: apply_core_configurations
# Description: Applies core VM configurations such as CPU, memory, and boot settings.
# Arguments:
#   $1 - The VMID of the VM to configure.
# =====================================================================================
apply_core_configurations() {
    local VMID="$1"
    log_info "Applying core configurations to VM $VMID..."

    local vm_config
    vm_config=$(jq -r ".vms[] | select(.vmid == $VMID)" "$VM_CONFIG_FILE")
    
    local cores
    cores=$(jq -r "(.vms[] | select(.vmid == $VMID) | .cores) // .vm_defaults.cores // \"\"" "$VM_CONFIG_FILE")
    if [ -z "$cores" ]; then
        log_fatal "Core count for VM $VMID is not defined in its config or in vm_defaults."
    fi
    local memory_mb
    memory_mb=$(jq -r "(.vms[] | select(.vmid == $VMID) | .memory_mb) // .vm_defaults.memory_mb // \"\"" "$VM_CONFIG_FILE")
    if [ -z "$memory_mb" ]; then
        log_fatal "Memory size for VM $VMID is not defined in its config or in vm_defaults."
    fi
    local start_at_boot
    start_at_boot=$(echo "$vm_config" | jq -r '.start_at_boot // "false"')
    local boot_order
    boot_order=$(echo "$vm_config" | jq -r '.boot_order // ""')
    local boot_delay
    boot_delay=$(echo "$vm_config" | jq -r '.boot_delay // ""')

    log_info "Setting cores to $cores and memory to ${memory_mb}MB for VM $VMID."
    run_qm_command set "$VMID" --cores "$cores"
    run_qm_command set "$VMID" --memory "$memory_mb"
    
    if [ "$start_at_boot" == "true" ]; then
        log_info "Enabling start on boot for VM $VMID."
        run_qm_command set "$VMID" --onboot 1
    else
        log_info "Disabling start on boot for VM $VMID."
        run_qm_command set "$VMID" --onboot 0
    fi

    if [ -n "$boot_order" ]; then
        run_qm_command set "$VMID" --boot "order=scsi0;net0" --startup "order=${boot_order},up=${boot_delay}"
    fi
}

# =====================================================================================
# Function: apply_network_configurations
# Description: Applies network configurations to a VM.
# Arguments:
#   $1 - The VMID of the VM to configure.
# =====================================================================================
apply_network_configurations() {
    local VMID="$1"
    log_info "Applying network configurations to VM $VMID..."

    local vm_config
    vm_config=$(jq -r ".vms[] | select(.vmid == $VMID)" "$VM_CONFIG_FILE")
    local network_config
    network_config=$(echo "$vm_config" | jq -r '.network_config // ""')

    if [ -n "$network_config" ]; then
        local ip
        ip=$(echo "$network_config" | jq -r '.ip // ""')
        if [ "$ip" == "dhcp" ]; then
            log_info "Applying network config: IP=dhcp"
            run_qm_command set "$VMID" --ipconfig0 "ip=dhcp"
        else
            local gw
            gw=$(echo "$network_config" | jq -r '.gw // ""')
            if [ -z "$ip" ] || [ -z "$gw" ]; then
                log_fatal "VM configuration for $VMID has an incomplete network_config. Both 'ip' and 'gw' must be specified."
            fi
            log_info "Applying network config: IP=${ip}, Gateway=${gw}"
            run_qm_command set "$VMID" --ipconfig0 "ip=${ip},gw=${gw}"
        fi
    else
        log_info "No network configurations to apply for VM $VMID."
    fi
}

# =====================================================================================
# Function: apply_volumes
# Description: Applies volume configurations to a VM.
# Arguments:
#   $1 - The VMID of the VM to configure.
# =====================================================================================
apply_volumes() {
    local VMID="$1"
    log_info "Applying volume configurations to VM $VMID..."

    local volumes
    volumes=$(jq -r ".vms[] | select(.vmid == $VMID) | .volumes[]? | select(.type == \"nfs\")" "$VM_CONFIG_FILE")
    if [ -z "$volumes" ]; then
        log_info "No NFS volumes defined for VM $VMID. Skipping volume configuration."
        return 0
    fi

    local server mount_point path
    server=$(echo "$volumes" | jq -r '.server')
    path=$(echo "$volumes" | jq -r '.path')
    mount_point=$(echo "$volumes" | jq -r '.mount_point')

    log_info "Ensuring NFS source directory exists on hypervisor..."
    # The 'path' from JSON is the absolute path on the hypervisor
    local hypervisor_nfs_path="$path"
    if [ ! -d "$hypervisor_nfs_path" ]; then
        log_info "Creating NFS source directory: $hypervisor_nfs_path"
        mkdir -p "$hypervisor_nfs_path"
        chmod 777 "$hypervisor_nfs_path"
    fi

    log_info "Waiting for cloud-init to complete in VM $VMID before mounting volumes..."
    run_qm_command guest exec "$VMID" -- /bin/bash -c "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 5; done"

    log_info "Configuring NFS mount for VM $VMID: ${server}:${path} -> ${mount_point}"
    run_qm_command guest exec "$VMID" -- /bin/bash -c "apt-get update && apt-get install -y nfs-common"
    run_qm_command guest exec "$VMID" -- /bin/mkdir -p "$mount_point"
    run_qm_command guest exec "$VMID" -- /bin/bash -c "grep -qxF '${server}:${path} ${mount_point} nfs defaults,auto,nofail 0 0' /etc/fstab || echo '${server}:${path} ${mount_point} nfs defaults,auto,nofail 0 0' >> /etc/fstab"
    
    if ! run_qm_command guest exec "$VMID" -- /bin/mount -a; then
        log_warn "Initial 'mount -a' failed. This can happen. Verifying mount status before declaring failure."
    fi
    
    # Robust mount verification
    if ! run_qm_command guest exec "$VMID" -- /bin/bash -c "mount | grep -q '${mount_point}'"; then
        log_fatal "Failed to mount NFS share ${server}:${path} at ${mount_point} in VM $VMID. Please check NFS server logs and network connectivity."
    fi
    
    log_info "NFS mount configured and verified successfully."
}

# =====================================================================================
# Function: provision_declarative_files
# Description: Provisions declarative files, such as Docker Compose files, from the
#              hypervisor to the VM's persistent storage. It reads the
#              'docker_compose_files' array from the VM's configuration.
#
# Arguments:
#   $1 - The VMID of the VM.
#
# Returns:
#   None.
# =====================================================================================
provision_declarative_files() {
    local VMID="$1"
    log_info "Provisioning declarative files for VMID: $VMID"

    local persistent_volume_path
    persistent_volume_path=$(jq -r ".vms[] | select(.vmid == $VMID) | .volumes[] | select(.type == \"nfs\") | .path" "$VM_CONFIG_FILE" | head -n 1)

    if [ -z "$persistent_volume_path" ]; then
        log_info "No NFS persistent volume found for VM $VMID. Skipping declarative file provisioning."
        return 0
    fi

    local compose_files
    compose_files=$(jq -c ".vms[] | select(.vmid == $VMID) | .docker_compose_files[]?" "$VM_CONFIG_FILE")

    if [ -z "$compose_files" ]; then
        log_info "No docker_compose_files to provision for VMID $VMID."
        return 0
    fi

    echo "$compose_files" | while read -r file_entry; do
        local source_path_from_config
        source_path_from_config=$(echo "$file_entry" | jq -r '.source')
        local destination_path
        destination_path=$(echo "$file_entry" | jq -r '.destination')

        if [ -z "$source_path_from_config" ] || [ -z "$destination_path" ]; then
            log_warn "Invalid docker_compose_files entry: $file_entry. Missing source or destination. Skipping."
            continue
        fi

        # The source path from config is the absolute path within the project structure.
        local source_path="$source_path_from_config"

        if [ ! -f "$source_path" ]; then
            log_warn "Source file not found: $source_path. Skipping."
            continue
        fi

        local full_destination_path="${persistent_volume_path}/${destination_path}"
        local destination_dir
        destination_dir=$(dirname "$full_destination_path")

        log_info "Ensuring destination directory exists: $destination_dir"
        if ! mkdir -p "$destination_dir"; then
            log_error "Failed to create destination directory: $destination_dir"
            continue
        fi

        log_info "Copying '$source_path' to '$full_destination_path'"
        if ! cp "$source_path" "$full_destination_path"; then
            log_error "Failed to copy file to $full_destination_path"
        fi
    done
}

# =====================================================================================
# Function: start_vm
# Description: Starts a VM if it is not already running.
# Arguments:
#   $1 - The VMID of the VM to start.
# =====================================================================================
start_vm() {
    local VMID="$1"
    log_info "Ensuring VM $VMID is started..."
    if qm status "$VMID" | grep -q "running"; then
        log_info "VM $VMID is already running."
    else
        run_qm_command start "$VMID"
    fi
}

# =====================================================================================
# Function: stop_vm
# Description: Stops a VM if it is running.
# Arguments:
#   $1 - The VMID of the VM to stop.
# =====================================================================================
stop_vm() {
    local VMID="$1"
    log_info "Ensuring VM $VMID is stopped..."
    if qm status "$VMID" | grep -q "running"; then
        run_qm_command stop "$VMID"
    else
        log_info "VM $VMID is already stopped."
    fi
}

# =====================================================================================
# Function: apply_vm_features
# Description: Executes feature installation scripts inside the VM. This function handles
#              the secure transfer of scripts and configurations into the VM, executes them,
#              and cleans up afterward.
#
# Arguments:
#   $1 - The VMID of the VM.
#
# Returns:
#   None. Exits with a fatal error if a feature script fails.
# =====================================================================================
apply_vm_features() {
    local VMID="$1"
    log_info "Applying features for VMID: $VMID"

    local features
    features=$(jq -r ".vms[] | select(.vmid == $VMID) | .features[]?" "$VM_CONFIG_FILE")

    if [ -z "$features" ]; then
        log_info "No features to apply for VMID $VMID."
        return 0
    fi

    # Create a temporary JSON context file for the VM
    local temp_context_file="/tmp/vm_${VMID}_context.json"
    jq -r ".vms[] | select(.vmid == $VMID)" "$VM_CONFIG_FILE" > "$temp_context_file"

    for feature in $features; do
        # --- NFS-based Script Deployment ---
        # Read the volumes array to find the persistent storage path
        local persistent_volume_path
        persistent_volume_path=$(jq -r ".vms[] | select(.vmid == $VMID) | .volumes[] | select(.type == \"nfs\") | .path" "$VM_CONFIG_FILE" | head -n 1)

        if [ -z "$persistent_volume_path" ]; then
            log_warn "No NFS volume found for VM $VMID. Skipping NFS script deployment."
        else
            # If the feature is 'docker', copy the Portainer configuration to the persistent storage.
            if [ "$feature" == "docker" ]; then
                local portainer_role
                portainer_role=$(jq -r ".vms[] | select(.vmid == $VMID) | .portainer_role // \"none\"" "$VM_CONFIG_FILE")

                if [ "$portainer_role" == "primary" ]; then
                    local portainer_source_path="${PHOENIX_BASE_DIR}/persistent-storage/portainer"
                    if [ -d "$portainer_source_path" ]; then
                        log_info "Copying Portainer configuration from $portainer_source_path to $persistent_volume_path..."
                        if ! cp -r "$portainer_source_path" "$persistent_volume_path/"; then
                            log_fatal "Failed to copy Portainer configuration."
                        fi
                        # Ensure the data directory exists
                        mkdir -p "${persistent_volume_path}/portainer/data"
                    else
                        log_warn "Portainer source directory not found at $portainer_source_path. Skipping copy."
                    fi
                else
                    log_info "Skipping Portainer server configuration copy for role: $portainer_role"
                fi
            fi

            # The 'persistent_volume_path' is the absolute path on the hypervisor
            local hypervisor_scripts_dir="${persistent_volume_path}/.phoenix_scripts"
            log_info "Creating script directory on hypervisor: $hypervisor_scripts_dir"
            mkdir -p "$hypervisor_scripts_dir"
            chmod 777 "$hypervisor_scripts_dir"

            local feature_script_path="${PHOENIX_BASE_DIR}/bin/vm_features/feature_install_${feature}.sh"
            if [ ! -f "$feature_script_path" ]; then
                log_fatal "Feature script not found at $feature_script_path. Cannot apply feature '$feature'."
            fi

            log_info "Copying feature script and common utils to $hypervisor_scripts_dir"
            cp "$feature_script_path" "$hypervisor_scripts_dir/"
            cp "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh" "$hypervisor_scripts_dir/"

            log_info "Copying Portainer setup scripts to $hypervisor_scripts_dir"
            cp "${PHOENIX_BASE_DIR}/bin/vm_features/portainer_api_setup.sh" "$hypervisor_scripts_dir/"
            cp "${PHOENIX_BASE_DIR}/bin/vm_features/portainer_agent_setup.sh" "$hypervisor_scripts_dir/"
            
            log_info "Copying VM context file to $hypervisor_scripts_dir"
            cp "$temp_context_file" "${hypervisor_scripts_dir}/vm_context.json"
        fi
        
        local persistent_mount_point
        persistent_mount_point=$(jq -r ".vms[] | select(.vmid == $VMID) | .volumes[] | select(.type == \"nfs\") | .mount_point" "$VM_CONFIG_FILE" | head -n 1)
        
        if [ -z "$persistent_mount_point" ]; then
            log_fatal "No NFS volume with a mount_point found for VM $VMID. Cannot execute feature scripts."
        fi

        local vm_script_dir="${persistent_mount_point}/.phoenix_scripts"
        local vm_script_path="${vm_script_dir}/feature_install_${feature}.sh"

        log_info "Making feature script executable in VM $VMID at $vm_script_path..."
        run_qm_command guest exec "$VMID" -- /bin/chmod +x "$vm_script_path"

        log_info "Executing feature script '$feature' in VM $VMID from NFS share..."
        if ! run_qm_command guest exec "$VMID" -- "$vm_script_path"; then
            log_fatal "Execution of feature script '$feature' failed for VMID $VMID. Check the feature log inside the VM for details."
        fi
        log_info "Feature script '$feature' executed successfully."

        log_info "Cleaning up script files from hypervisor NFS share..."
        # The 'persistent_volume_path' is the absolute path on the hypervisor
        local hypervisor_scripts_dir="${persistent_volume_path}/.phoenix_scripts"
        rm -rf "$hypervisor_scripts_dir"
    done

    # Clean up the local temporary context file
    rm -f "$temp_context_file"

    log_info "All features applied successfully for VMID $VMID."
}

# =====================================================================================
# Function: manage_snapshots
# Description: Manages the creation of VM snapshots at different lifecycle points as
#              defined in the configuration file.
#
# Arguments:
#   $1 - The VMID of the VM.
#   $2 - The lifecycle point (e.g., "pre-features", "post-features").
#
# Returns:
#   None. Exits with a fatal error if snapshot creation fails.
# =====================================================================================
manage_snapshots() {
    local VMID="$1"
    local lifecycle_point="$2"
    log_info "Managing snapshots for VMID $VMID at lifecycle point: $lifecycle_point"

    local snapshot_name
    snapshot_name=$(jq -r ".vms[] | select(.vmid == $VMID) | .snapshots.\"$lifecycle_point\" // \"\"" "$VM_CONFIG_FILE")

    if [ -z "$snapshot_name" ]; then
        log_info "No snapshot defined for '$lifecycle_point' for VMID $VMID. Skipping."
        return 0
    fi

    if qm listsnapshot "$VMID" | grep -q "$snapshot_name"; then
        log_info "Snapshot '$snapshot_name' already exists for VMID $VMID. Skipping."
        return 0
    fi

    log_info "Creating snapshot '$snapshot_name' for VM $VMID..."
    if ! run_qm_command snapshot "$VMID" "$snapshot_name"; then
        log_fatal "Failed to create snapshot '$snapshot_name' for VMID $VMID."
    fi

    log_info "Snapshot '$snapshot_name' created successfully."
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