#!/bin/bash
#
# File: vm-manager.sh
# Description: This script manages all VM-related operations for the Phoenix Hypervisor system.

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# --- Source common utilities ---
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- Load external configurations ---
STACKS_CONFIG_FILE="${PHOENIX_BASE_DIR}/etc/phoenix_stacks_config.json"

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
    local is_guest_exec=false

    # Check if the command is 'qm guest exec'
    if [[ "$1" == "guest" && "$2" == "exec" ]]; then
        is_guest_exec=true
    fi

    output=$(qm "$@" 2>&1) || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "Command failed: $cmd_description (Exit Code: $exit_code)"
        log_error "Output:\n$output"
    elif [ "$is_guest_exec" = true ]; then
        # Check if the output is valid JSON before attempting to parse it.
        if ! echo "$output" | jq -e . > /dev/null 2>&1; then
            # If not JSON, print the raw output and assume success if the exit code was 0.
            echo "$output"
        else
            # If it is JSON, parse it for details.
            local out_data
            out_data=$(echo "$output" | jq -r '."out-data" // ""')
            local guest_exitcode
            guest_exitcode=$(echo "$output" | jq -r '.exitcode // "0"') # Default to "0"
            local exited_status
            exited_status=$(echo "$output" | jq -r '.exited // "0"') # Default to "0"

            if [ -n "$out_data" ]; then
                echo -e "$out_data"
            fi

            # Proxmox's qm guest exec itself might return 0 even if the guest command failed.
            # We must check the exitcode from within the JSON payload.
            if [ "$exited_status" -eq 1 ] && [ "$guest_exitcode" -ne 0 ]; then
                log_error "Guest command exited with non-zero status: $guest_exitcode"
                return "$guest_exitcode"
            fi
        fi
    else
        echo "$output"
    fi
    return $exit_code
}

# =====================================================================================
# Function: wait_for_guest_agent
# Description: Waits for the QEMU guest agent to be running and responsive inside the VM.
# Arguments:
#   $1 - The VMID of the VM.
# Returns:
#   None. Exits with a fatal error if the agent does not become responsive within the timeout.
# =====================================================================================
wait_for_guest_agent() {
    local VMID="$1"
    log_info "Waiting for guest agent on VM $VMID to become responsive..."
    local timeout=300 # 5 minutes
    local start_time=$SECONDS

    while (( SECONDS - start_time < timeout )); do
        if qm agent "$VMID" ping &> /dev/null; then
            log_info "Guest agent on VM $VMID is responsive."
            return 0
        fi
        sleep 5
    done

    log_fatal "Timeout reached while waiting for guest agent on VM $VMID."
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
    log_info "Step 0: Validating VMID $VMID against configuration file..."
    if ! jq -e ".vms[] | select(.vmid == $VMID)" "$VM_CONFIG_FILE" > /dev/null; then
        log_fatal "VMID $VMID not found in configuration file: $VM_CONFIG_FILE. Please add a valid VM definition."
    fi
    log_info "Step 0: VMID $VMID found in configuration. Proceeding with orchestration."

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

        log_info "Step 4: Starting VM template $VMID..."
        start_vm "$VMID"
        wait_for_guest_agent "$VMID"
        log_info "Step 4: Completed."

        log_info "Step 5: Waiting for guest agent on VM template $VMID..."
        wait_for_guest_agent "$VMID"
        log_info "Step 5: Completed."

        log_info "Step 6: Waiting for cloud-init to complete before proceeding in VM template $VMID..."
        local retries=3
        local success=false
        for ((i=1; i<=retries; i++)); do
            local output
            local exit_code=0
            output=$(run_qm_command guest exec "$VMID" -- /bin/bash -c "cloud-init status --wait") || exit_code=$?
            
            if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 2 ]; then
                log_info "Cloud-init has finished (Exit Code: $exit_code)."
                success=true
                break
            else
                log_warn "Waiting for cloud-init failed with unexpected exit code $exit_code (attempt $i/$retries). Retrying in 15 seconds..."
                sleep 15
            fi
        done
        if [ "$success" = false ]; then
            log_fatal "Failed to wait for cloud-init completion in template VM $VMID after $retries attempts."
        fi
        log_info "Step 6: Cloud-init completed in VM template $VMID."

        log_info "Step 7: Applying features to VM template $VMID..."
        apply_vm_features "$VMID"
        log_info "Step 8: Features applied to VM template $VMID."

        log_info "Step 9: Cleaning cloud-init state for VM template $VMID..."
        run_qm_command guest exec "$VMID" -- /bin/bash -c "cloud-init clean"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "rm -f /etc/machine-id"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "touch /etc/machine-id"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "systemctl stop cloud-init"
        log_info "Step 9: Cloud-init state cleaned for VM template $VMID."

        log_info "Step 10: Stopping VM template $VMID..."
        stop_vm "$VMID"
        log_info "Step 10: Completed."

        log_info "Step 11: Creating final template snapshot for VM $VMID..."
        manage_snapshots "$VMID" "post-features"
        log_info "Step 11: Completed."

        log_info "Step 12: Converting VM $VMID to template..."
        run_qm_command template "$VMID"
        log_info "Step 12: Completed. Template creation for VMID $VMID completed successfully."
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

    if ! command -v virt-customize &> /dev/null; then
        log_fatal "The 'virt-customize' command is not found. Please run the hypervisor setup to install it."
    fi

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
    
    local ubuntu_release
    ubuntu_release=$(jq -r ".vm_defaults.ubuntu_release // \"noble\"" "$HYPERVISOR_CONFIG_FILE")
    local image_url="https://cloud-images.ubuntu.com/${ubuntu_release}/current/${template_image}"
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

    # Apply nameserver from config if it exists
    local network_config
    network_config=$(jq -r ".vms[] | select(.vmid == $VMID) | .network_config // \"\"" "$VM_CONFIG_FILE")
    if [ -n "$network_config" ]; then
        local nameserver
        nameserver=$(echo "$network_config" | jq -r '.nameserver // ""')
        if [ -n "$nameserver" ]; then
            log_info "Applying DNS config: DNS=${nameserver}"
            run_qm_command set "$VMID" --nameserver "$nameserver"
        fi
    fi

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
        local nameserver
        nameserver=$(echo "$network_config" | jq -r '.nameserver // ""')
        if [ -z "$ip" ] || [ -z "$gw" ]; then
            log_fatal "VM configuration for $VMID has an incomplete network_config. Both 'ip' and 'gw' must be specified."
        fi
        log_info "Applying initial network config: IP=${ip}, Gateway=${gw}, DNS=${nameserver}"
        run_qm_command set "$VMID" --ipconfig0 "ip=${ip},gw=${gw}"
        if [ -n "$nameserver" ]; then
            run_qm_command set "$VMID" --nameserver "$nameserver"
        fi
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
            local nameserver="10.0.0.153" # Default to the internal DNS server
            if [ -z "$ip" ] || [ -z "$gw" ]; then
                log_fatal "VM configuration for $VMID has an incomplete network_config. Both 'ip' and 'gw' must be specified."
            fi
            log_info "Applying network config: IP=${ip}, Gateway=${gw}"
            run_qm_command set "$VMID" --ipconfig0 "ip=${ip},gw=${gw}"
        fi
    start_vm "$VMID"
    wait_for_guest_agent "$VMID"


    run_qm_command guest exec "$VMID" -- systemctl restart systemd-networkd
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
    local retries=3
    local success=false
    for ((i=1; i<=retries; i++)); do
        local output
        local exit_code=0
        output=$(run_qm_command guest exec "$VMID" -- /bin/bash -c "cloud-init status --wait") || exit_code=$?

        if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 2 ]; then
            log_info "Cloud-init has finished (Exit Code: $exit_code)."
            success=true
            break
        else
            log_warn "Waiting for cloud-init failed with unexpected exit code $exit_code (attempt $i/$retries). Retrying in 15 seconds..."
            sleep 15
        fi
    done
    if [ "$success" = false ]; then
        log_fatal "Failed to wait for cloud-init completion in VM $VMID after $retries attempts."
    fi

    log_info "Configuring NFS mount for VM $VMID: ${server}:${path} -> ${mount_point}"
    # nfs-common is now installed via virt-customize, so this is no longer needed.
    run_qm_command guest exec "$VMID" -- /bin/mkdir -p "$mount_point"
    run_qm_command guest exec "$VMID" -- /bin/bash -c "grep -qxF '${server}:${path} ${mount_point} nfs defaults,auto,nofail 0 0' /etc/fstab || echo '${server}:${path} ${mount_point} nfs defaults,auto,nofail 0 0' >> /etc/fstab"
    
    if ! run_qm_command guest exec "$VMID" -- /bin/mount -a; then
        log_warn "Initial 'mount -a' failed. This can happen. Verifying mount status before declaring failure."
    fi
    
    # Robust mount verification
    if ! run_qm_command guest exec "$VMID" -- /bin/bash -c "mount | grep -q '${mount_point}'"; then
        log_fatal "Failed to mount NFS share ${server}:${path} at ${mount_point} in VM $VMID. Please check NFS server logs and network connectivity."
    fi
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
# Description: Asynchronously executes feature installation scripts inside the VM,
#              providing real-time log streaming and robust completion detection.
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

    local temp_context_file="/tmp/vm_${VMID}_context.json"
    jq -r ".vms[] | select(.vmid == $VMID)" "$VM_CONFIG_FILE" > "$temp_context_file"

    local persistent_volume_path
    persistent_volume_path=$(jq -r ".vms[] | select(.vmid == $VMID) | .volumes[] | select(.type == \"nfs\") | .path" "$VM_CONFIG_FILE" | head -n 1)

    if [ -z "$persistent_volume_path" ]; then
        log_fatal "No NFS volume found for VM $VMID. Cannot apply features."
    fi

    # Prepare scripts on the hypervisor's NFS share ONCE before the loop
    local hypervisor_scripts_dir="${persistent_volume_path}/.phoenix_scripts"
    log_info "Preparing script directory at $hypervisor_scripts_dir..."
    rm -rf "$hypervisor_scripts_dir"
    mkdir -p "$hypervisor_scripts_dir"

    for feature in $features; do
        local feature_script_path="${PHOENIX_BASE_DIR}/bin/vm_features/feature_install_${feature}.sh"
        if [ ! -f "$feature_script_path" ]; then
            log_fatal "Feature script not found: $feature_script_path"
        fi

        cp "$feature_script_path" "$hypervisor_scripts_dir/"
        cp "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh" "$hypervisor_scripts_dir/"
        cp "$temp_context_file" "${hypervisor_scripts_dir}/vm_context.json"
        
        # --- Definitive Fix: Copy all required configs ---
        log_info "Copying core configuration files to VM's persistent storage..."
        cp "$VM_CONFIG_FILE" "${hypervisor_scripts_dir}/phoenix_vm_configs.json"
        cp "$STACKS_CONFIG_FILE" "${hypervisor_scripts_dir}/phoenix_stacks_config.json"
        cp "$HYPERVISOR_CONFIG_FILE" "${hypervisor_scripts_dir}/phoenix_hypervisor_config.json"

        # --- Verification Step ---
        if [ ! -f "${hypervisor_scripts_dir}/phoenix_hypervisor_config.json" ]; then
            log_fatal "Verification failed: phoenix_hypervisor_config.json not found in ${hypervisor_scripts_dir}"
        fi
        log_info "Successfully copied and verified phoenix_hypervisor_config.json."

        # --- Definitive Fix: Copy Portainer compose file ---
        log_info "Copying Portainer docker-compose.yml to VM's persistent storage..."
        local portainer_compose_dest_dir="${persistent_volume_path}/portainer"
        mkdir -p "$portainer_compose_dest_dir"
        cp "${PHOENIX_BASE_DIR}/persistent-storage/portainer/docker-compose.yml" "$portainer_compose_dest_dir/"

        # --- Definitive Fix: Copy Portainer config.json ---
        log_info "Copying Portainer config.json to VM's persistent storage..."
        cp "${PHOENIX_BASE_DIR}/etc/portainer/config.json" "${hypervisor_scripts_dir}/portainer_config.json"

        # --- Definitive Fix: Copy Step-CA root certificate ---
        log_info "Copying Step-CA root certificate to VM's persistent storage..."
        local ca_cert_source_path="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_ca.crt"
        if [ -f "$ca_cert_source_path" ]; then
            cp "$ca_cert_source_path" "${hypervisor_scripts_dir}/phoenix_ca.crt"
        else
            log_warn "Step-CA root certificate not found at $ca_cert_source_path. Docker feature might fail if it needs to trust internal services."
        fi

        # --- Definitive Fix: Copy Step-CA provisioner password file ---
        log_info "Copying Step-CA provisioner password file to VM's persistent storage..."
        local provisioner_password_source_path="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/provisioner_password.txt"
        if [ -f "$provisioner_password_source_path" ]; then
            cp "$provisioner_password_source_path" "${hypervisor_scripts_dir}/provisioner_password.txt"
        else
            log_warn "Step-CA provisioner password file not found at $provisioner_password_source_path. Certificate generation for Portainer will fail."
        fi

        local persistent_mount_point
        persistent_mount_point=$(jq -r ".vms[] | select(.vmid == $VMID) | .volumes[] | select(.type == \"nfs\") | .mount_point" "$VM_CONFIG_FILE" | head -n 1)
        local vm_script_dir="${persistent_mount_point}/.phoenix_scripts"
        local vm_script_path="${vm_script_dir}/feature_install_${feature}.sh"
        local log_file_in_vm="/var/log/phoenix_feature_${feature}.log"

        # Make scripts executable
        run_qm_command guest exec "$VMID" -- /bin/chmod -R +x "$vm_script_dir"

        # Execute the script asynchronously and capture its PID
        log_info "Executing feature script '$feature' in VM $VMID..."
        local log_file_in_vm="/var/log/phoenix_feature_${feature}.log"
        local exit_code_file_in_vm="/tmp/phoenix_feature_${feature}_exit_code"
        
        # Ensure previous exit code file is removed
        run_qm_command guest exec "$VMID" -- /bin/bash -c "rm -f $exit_code_file_in_vm"

        # Execute the script in the background, redirecting output to log file and capturing exit code
        local exec_command="nohup /bin/bash -c '$vm_script_path $VMID > $log_file_in_vm 2>&1; echo \$? > $exit_code_file_in_vm' &"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "$exec_command"

        log_info "Feature script '$feature' started. Streaming logs from $log_file_in_vm..."

        local timeout=1800 # 30 minutes timeout
        local start_time=$SECONDS
        local last_log_line=0

        while true; do
            # Stream new log content
            local new_log_output
            new_log_output=$(qm guest exec "$VMID" -- /bin/bash -c "tail -n +$((last_log_line + 1)) $log_file_in_vm" 2>/dev/null)
            local new_log_content
            new_log_content=$(echo "$new_log_output" | jq -r '."out-data" // ""')
            if [ -n "$new_log_content" ]; then
                echo -e "$new_log_content"
                new_lines_count=$(echo "$new_log_content" | wc -l | tr -d '[:space:]')
                last_log_line=$((last_log_line + new_lines_count))
            fi

            # Check if the exit code file exists and contains a value
            local exit_code_output
            exit_code_output=$(qm guest exec "$VMID" -- /bin/bash -c "cat $exit_code_file_in_vm" 2>/dev/null)
            local exit_code
            exit_code=$(echo "$exit_code_output" | jq -r '."out-data" // ""' | tr -d '[:space:]')

            if [ -n "$exit_code" ]; then
                if [ "$exit_code" -eq 0 ]; then
                    log_success "Feature script '$feature' completed successfully."
                    break
                else
                    log_fatal "Feature script '$feature' failed with exit code $exit_code."
                fi
            fi

            # Check for timeout
            if (( SECONDS - start_time > timeout )); then
                log_fatal "Timeout reached while waiting for feature script '$feature' to complete."
            fi

            sleep 5
        done
    done

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