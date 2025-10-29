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
                exit_code="$guest_exitcode"
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
    elif [ -z "$VM_CONFIG_FILE" ]; then
        log_fatal "VM_CONFIG_FILE environment variable is not set and no override was provided."
    fi

    log_info "Starting orchestration for VMID: $VMID"

    # --- VMID Validation ---
    log_info "Step 0: Validating VMID $VMID against configuration file..."
    if ! jq_get_vm_value "$VMID" "." > /dev/null; then
        log_fatal "VMID $VMID not found in configuration file: $VM_CONFIG_FILE. Please add a valid VM definition."
    fi
    log_info "Step 0: VMID $VMID found in configuration. Proceeding with orchestration."

    log_info "Available storage pools before VM creation:"
    pvesm status

    local is_template
    is_template=$(jq_get_vm_value "$VMID" ".is_template" || echo "false")

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
        local final_cloud_init_exit_code=1 # Default to a failure code
        for ((i=1; i<=retries; i++)); do
            local output
            local exit_code=0
            output=$(run_qm_command guest exec "$VMID" -- /bin/bash -c "cloud-init status --wait") || exit_code=$?
            
            if [ "$exit_code" -eq 0 ]; then
                log_info "Cloud-init has finished successfully."
                final_cloud_init_exit_code=0
                success=true
                break
            elif [ "$exit_code" -eq 2 ]; then
                log_warn "Cloud-init finished with non-fatal errors (Exit Code: 2). Assuming a reboot is required."
                final_cloud_init_exit_code=2
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
        log_info "Step 6: Cloud-init first pass completed in VM template $VMID."

        if [ "$final_cloud_init_exit_code" -eq 2 ]; then
            log_info "Step 6a: Rebooting VM template $VMID to finalize kernel upgrades..."
            run_qm_command reboot "$VMID"
            wait_for_guest_agent "$VMID"
            log_info "Step 6a: VM has been rebooted and guest agent is responsive."

            log_info "Step 6b: Performing second-pass verification of cloud-init status..."
            local second_pass_success=false
            for ((j=1; j<=retries; j++)); do
                local second_pass_exit_code=0
                run_qm_command guest exec "$VMID" -- /bin/bash -c "cloud-init status --wait" || second_pass_exit_code=$?
                
                if [ "$second_pass_exit_code" -eq 0 ]; then
                    log_info "Second-pass cloud-init verification successful."
                    second_pass_success=true
                    break
                else
                    log_warn "Second-pass cloud-init verification failed with exit code $second_pass_exit_code (attempt $j/$retries). Retrying in 15 seconds..."
                    sleep 15
                fi
            done

            if [ "$second_pass_success" = false ]; then
                log_fatal "Cloud-init did not report a clean status after reboot. Template creation failed."
            fi
            log_info "Step 6b: Cloud-init second-pass verification completed."
        fi

        log_info "Step 7: Applying features to VM template $VMID..."
        apply_vm_features "$VMID"
        log_info "Step 8: Features applied to VM template $VMID."

        log_info "Step 9: Aggressively cleaning cloud-init state for VM template $VMID..."
        
        # --- Definitive Fix: Correct Order of Operations for Cleanup ---
        # All other cleanup tasks must be performed *before* the final, destructive
        # 'cloud-init clean' command, which can shut down the guest agent.
        run_qm_command guest exec "$VMID" -- /bin/bash -c "rm -rf /var/lib/cloud/instance"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "rm -f /etc/machine-id"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "touch /etc/machine-id"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "systemctl stop cloud-init"

        # This is the VERY LAST command to be run inside the guest.
        log_info "Step 9a: Performing final cloud-init clean..."
        run_qm_command guest exec "$VMID" -- /bin/bash -c "cloud-init clean --logs"

        log_info "Step 9: Cloud-init state aggressively cleaned for VM template $VMID."

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

        log_info "Step 7: Applying firewall rules for VM $VMID..."
        apply_vm_firewall_rules "$VMID"
        log_info "Step 7: Completed."

        log_info "Step 8: Managing pre-feature snapshots for VM $VMID..."
        manage_snapshots "$VMID" "pre-features"
        log_info "Step 8: Completed."

        log_info "Step 9: Preparing CA staging area for VM $VMID..."
        prepare_vm_ca_staging_area "$VMID"
        log_info "Step 9: Completed."

        log_info "Step 10: Applying features to VM $VMID..."
        apply_vm_features "$VMID"
        log_info "Step 10: Completed."


        log_info "Step 10: Managing post-feature snapshots for VM $VMID..."
        manage_snapshots "$VMID" "post-features"
        log_info "Step 10: Completed."


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

    local clone_from_vmid
    clone_from_vmid=$(jq_get_vm_value "$VMID" ".clone_from_vmid" || echo "")
    local template
    template=$(jq_get_vm_value "$VMID" ".template" || echo "")
    local template_image
    template_image=$(jq_get_vm_value "$VMID" ".template_image" || echo "")

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
    storage_pool=$(get_vm_config_value ".vm_defaults.storage_pool")
    if [ -z "$storage_pool" ]; then
        log_fatal "Missing 'vm_defaults.storage_pool' in $VM_CONFIG_FILE."
    fi
    local network_bridge
    network_bridge=$(get_vm_config_value ".vm_defaults.network_bridge")
    if [ -z "$network_bridge" ]; then
        log_fatal "Missing 'vm_defaults.network_bridge' in $VM_CONFIG_FILE."
    fi
    
    local ubuntu_release
    ubuntu_release=$(get_global_config_value ".vm_defaults.ubuntu_release")
    local image_url="https://cloud-images.ubuntu.com/${ubuntu_release}/current/${template_image}"
    local download_path="/tmp/${template_image}"

    log_info "Forcing fresh download of Ubuntu cloud image from $image_url..."
    if ! wget --progress=bar:force -O "$download_path" "$image_url"; then
        log_fatal "Failed to download cloud image."
    fi

    # --- Install Dependencies ---
    # `libguestfs-tools` is required for `virt-customize`.
    if ! dpkg -l | grep -q "libguestfs-tools"; then
        log_info "Installing libguestfs-tools..."
        apt-get update
        apt-get install -y libguestfs-tools
    fi

    # --- Customize Image ---
    # This is a critical step. `virt-customize` allows us to modify the image offline
    # before it's ever booted. We inject the `qemu-guest-agent`, which is essential
    # for the Proxmox host to communicate reliably with the guest VM.
    log_info "Installing qemu-guest-agent and nfs-common into the cloud image..."
    if ! virt-customize -a "$download_path" --install qemu-guest-agent,nfs-common --run-command 'systemctl enable qemu-guest-agent'; then
        log_fatal "Failed to customize cloud image."
    fi

    log_info "Radically simplified VM creation starting..."
    local vm_name
    vm_name=$(jq_get_vm_value "$VMID" ".name")
    local username
    username=$(jq_get_vm_value "$VMID" ".user_config.username")
    local nameserver
    nameserver=$(jq_get_vm_value "$VMID" ".network_config.nameserver")
    local searchdomain
    searchdomain=$(jq_get_vm_value "$VMID" ".network_config.searchdomain" || echo "phoenix.local")

    # --- The One Command to Rule Them All ---
    # This single, atomic command creates the VM with all necessary settings from the start.
    log_info "Creating VM $VMID with a single, atomic command..."
    run_qm_command create "$VMID" \
        --name "$vm_name" \
        --memory 2048 \
        --net0 "virtio,bridge=${network_bridge}" \
        --serial0 socket \
        --agent 1 \
        --scsihw virtio-scsi-pci \
        --ciuser "$username" \
        --searchdomain "$searchdomain" \
        --ipconfig0 "ip=dhcp"

    log_info "Importing disk and attaching as boot device..."
    run_qm_command importdisk "$VMID" "$download_path" "$storage_pool"
    run_qm_command set "$VMID" --scsi0 "${storage_pool}:vm-${VMID}-disk-0"
    run_qm_command set "$VMID" --boot c --bootdisk scsi0
    log_info "Resizing template disk to 32G..."
    run_qm_command resize "$VMID" scsi0 32G

    log_info "Creating final cloud-init drive..."
    run_qm_command set "$VMID" --ide2 "${storage_pool}:cloudinit"

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

    local clone_from_vmid
    clone_from_vmid=$(jq_get_vm_value "$VMID" ".clone_from_vmid" || echo "")
    local new_vm_name
    new_vm_name=$(jq_get_vm_value "$VMID" ".name" || echo "")

    if [ -z "$clone_from_vmid" ]; then
        log_fatal "VM configuration for $VMID is missing the required 'clone_from_vmid' attribute."
    fi
    if [ -z "$new_vm_name" ]; then
        log_fatal "VM configuration for $VMID is missing the required 'name' attribute."
    fi

    log_info "Cloning from VM $clone_from_vmid to new VM $VMID with name '$new_vm_name'."
    run_qm_command clone "$clone_from_vmid" "$VMID" --name "$new_vm_name" --full

    log_info "Enabling QEMU guest agent for VM $VMID..."
    run_qm_command set "$VMID" --agent 1
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

    local cores
    cores=$(jq_get_vm_value "$VMID" ".cores" || get_vm_config_value ".vm_defaults.cores")
    if [ -z "$cores" ]; then
        log_fatal "Core count for VM $VMID is not defined in its config or in vm_defaults."
    fi
    local memory_mb
    memory_mb=$(jq_get_vm_value "$VMID" ".memory_mb" || get_vm_config_value ".vm_defaults.memory_mb")
    if [ -z "$memory_mb" ]; then
        log_fatal "Memory size for VM $VMID is not defined in its config or in vm_defaults."
    fi
    local start_at_boot
    start_at_boot=$(jq_get_vm_value "$VMID" ".start_at_boot" || echo "false")
    local boot_order
    boot_order=$(jq_get_vm_value "$VMID" ".boot_order" || echo "")
    local boot_delay
    boot_delay=$(jq_get_vm_value "$VMID" ".boot_delay" || echo "")

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
        # Ensure the boot order is correct for scsi devices, which are standard for our templates
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

    local ip
    ip=$(jq_get_vm_value "$VMID" ".network_config.ip" || echo "")
    ip=$(echo -n "$ip" | tr -d '[:cntrl:]') # Sanitize for hidden characters

    if [ -z "$ip" ]; then
        log_info "No IP address configured for VM $VMID. Skipping IP configuration."
    elif [ "$ip" == "dhcp" ]; then
        log_info "Applying network config: IP=dhcp"
        run_qm_command set "$VMID" --ipconfig0 "ip=dhcp"
    else
        local gw
        gw=$(jq_get_vm_value "$VMID" ".network_config.gw" || echo "")
        gw=$(echo -n "$gw" | tr -d '[:cntrl:]') # Sanitize for hidden characters

        if [ -z "$gw" ]; then
            log_fatal "VM configuration for $VMID specifies a static IP but is missing a gateway."
        fi
        log_info "Applying network config: IP=${ip}, Gateway=${gw}"
        run_qm_command set "$VMID" --ipconfig0 "ip=${ip},gw=${gw}"
    fi

    # Apply DNS settings regardless of DHCP or static IP
    # Force nameserver to be the host, ensuring all guests use the centralized DNS
    local nameserver="10.0.0.13"
    local searchdomain
    log_info "Applying DNS config: DNS=${nameserver}"
    run_qm_command set "$VMID" --nameserver "$nameserver"

    # --- THE DEFINITIVE FIX ---
    # After all network and user settings have been applied with `qm set`,
    # we must explicitly regenerate the cloud-init ISO to include these changes.
    log_info "Regenerating cloud-init drive for VM $VMID to apply all pending changes..."
    run_qm_command cloudinit update "$VMID"

    start_vm "$VMID"
    wait_for_guest_agent "$VMID"
    run_qm_command guest exec "$VMID" -- systemctl restart systemd-networkd

    log_info "Forcing DNS resolution to use the hypervisor's DNS server..."
    # run_qm_command guest exec "$VMID" -- /bin/bash -c "echo 'nameserver 10.0.0.13' > /etc/resolv.conf"
}

# =====================================================================================
# Function: apply_volumes
# Description: Applies all NFS volume configurations to a VM by iterating through
#              the volumes defined in its configuration.
# Arguments:
#   $1 - The VMID of the VM to configure.
# =====================================================================================
apply_volumes() {
    local VMID="$1"
    log_info "Applying volume configurations to VM $VMID..."

    # Get all NFS volumes as a JSON array of objects
    local volumes_json
    volumes_json=$(jq_get_vm_value "$VMID" ".volumes[] | select(.type == \"nfs\")")

    if [ -z "$volumes_json" ]; then
        log_info "No NFS volumes defined for VM $VMID. Skipping volume configuration."
        return 0
    fi

    # Wait for cloud-init to complete before attempting any mounts
    wait_for_cloud_init "$VMID"

    # Iterate over each volume object
    echo "$volumes_json" | jq -c '.' | while read -r volume; do
        local server=$(echo "$volume" | jq -r '.server')
        local path=$(echo "$volume" | jq -r '.path')
        local mount_point=$(echo "$volume" | jq -r '.mount_point')

        log_info "Processing NFS volume: ${server}:${path} -> ${mount_point}"

        log_info "Ensuring NFS source directory exists on hypervisor..."
        if [ ! -d "$path" ]; then
            log_info "Creating NFS source directory: $path"
            mkdir -p "$path"
            chmod 777 "$path"
        fi

        log_info "Configuring NFS mount inside VM..."
        run_qm_command guest exec "$VMID" -- /bin/mkdir -p "$mount_point"
        local fstab_entry="${server}:${path} ${mount_point} nfs defaults,auto,nofail 0 0"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "grep -qxF '${fstab_entry}' /etc/fstab || echo '${fstab_entry}' >> /etc/fstab"
        
        if ! run_qm_command guest exec "$VMID" -- /bin/mount -a; then
            log_warn "Initial 'mount -a' failed. This can happen. Verifying mount status before declaring failure."
        fi
        
        if ! run_qm_command guest exec "$VMID" -- /bin/bash -c "mount | grep -q '${mount_point}'"; then
            log_fatal "Failed to mount NFS share ${server}:${path} at ${mount_point} in VM $VMID."
        fi
        log_success "Successfully mounted ${server}:${path} at ${mount_point}."
    done
}

# =====================================================================================
# Function: wait_for_cloud_init
# Description: A helper function to wait for cloud-init to complete, including handling
#              reboots if necessary.
# Arguments:
#   $1 - The VMID of the VM.
# =====================================================================================
wait_for_cloud_init() {
    local VMID="$1"
    log_info "Waiting for cloud-init to complete in VM $VMID..."
    local retries=3
    local success=false
    local final_cloud_init_exit_code=1

    for ((i=1; i<=retries; i++)); do
        local exit_code=0
        run_qm_command guest exec "$VMID" -- /bin/bash -c "cloud-init status --wait" || exit_code=$?

        if [ "$exit_code" -eq 0 ]; then
            log_info "Cloud-init has finished successfully."
            final_cloud_init_exit_code=0
            success=true
            break
        elif [ "$exit_code" -eq 2 ]; then
            log_warn "Cloud-init finished with non-fatal errors. Assuming a reboot is required."
            final_cloud_init_exit_code=2
            success=true
            break
        else
            log_warn "Waiting for cloud-init failed (attempt $i/$retries). Retrying..."
            sleep 15
        fi
    done

    if [ "$success" = false ]; then
        log_fatal "Failed to wait for cloud-init completion in VM $VMID."
    fi

    if [ "$final_cloud_init_exit_code" -eq 2 ]; then
        log_info "Rebooting VM $VMID to clear transient cloud-init error..."
        run_qm_command reboot "$VMID"
        wait_for_guest_agent "$VMID"
        log_info "VM rebooted. Re-verifying cloud-init status..."
        if ! run_qm_command guest exec "$VMID" -- /bin/bash -c "cloud-init status --wait"; then
            log_fatal "Cloud-init did not report a clean status after reboot."
        fi
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
    features=$(jq_get_vm_array "$VMID" "(.features // [])[]" || echo "")

    if [ -z "$features" ]; then
        log_info "No features to apply for VMID $VMID."
        return 0
    fi

    local temp_context_file="/tmp/vm_${VMID}_context.json"
    jq_get_vm_value "$VMID" "." > "$temp_context_file"

    local persistent_volume_path
    persistent_volume_path=$(jq_get_vm_value "$VMID" ".volumes[] | select(.type == \"nfs\") | .path" | head -n 1)

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

        # --- Definitive Fix: Copy HAProxy config ---
        log_info "Copying HAProxy config to VM's persistent storage..."
        cp "${PHOENIX_BASE_DIR}/etc/haproxy/haproxy.cfg" "${hypervisor_scripts_dir}/haproxy.cfg"

        local persistent_mount_point
        persistent_mount_point=$(jq_get_vm_value "$VMID" ".volumes[] | select(.type == \"nfs\") | .mount_point" | head -n 1)
        local vm_script_dir="${persistent_mount_point}/.phoenix_scripts"
        local vm_script_path="${vm_script_dir}/feature_install_${feature}.sh"
        local log_file_in_vm="/var/log/phoenix_feature_${feature}.log"

        # Make scripts executable on the hypervisor before the VM accesses them
        log_info "Setting executable permissions on scripts in $hypervisor_scripts_dir..."
        chmod -R +x "$hypervisor_scripts_dir"

        # Execute the script asynchronously and capture its PID
        log_info "Executing feature script '$feature' in VM $VMID..."
        local log_file_in_vm="/var/log/phoenix_feature_${feature}.log"
        local exit_code_file_in_vm="/tmp/phoenix_feature_${feature}_exit_code"
        
        # Ensure previous exit code file is removed
        run_qm_command guest exec "$VMID" -- /bin/bash -c "rm -f $exit_code_file_in_vm"

        # Read the fingerprint from the shared location
        local fingerprint_file="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/root_ca.fingerprint"
        local ca_fingerprint=""
        if [ -f "$fingerprint_file" ]; then
            ca_fingerprint=$(cat "$fingerprint_file")
        else
            log_warn "CA fingerprint file not found at $fingerprint_file. Bootstrap may fail."
        fi

        # Execute the script in the background, passing the fingerprint as an environment variable
        local exec_command="nohup /bin/bash -c 'export STEP_CA_FINGERPRINT=\"${ca_fingerprint}\"; $vm_script_path $VMID > $log_file_in_vm 2>&1; echo \$? > $exit_code_file_in_vm' &"
        run_qm_command guest exec "$VMID" -- /bin/bash -c "$exec_command"

        log_info "Feature script '$feature' started with dynamic fingerprint. Streaming logs from $log_file_in_vm..."

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
    snapshot_name=$(jq_get_vm_value "$VMID" ".snapshots.\"$lifecycle_point\"" || echo "")

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
# Function: wait_for_step_ca_service
# Description: Waits for the Step-CA service inside LXC 103 to become active.
# =====================================================================================
wait_for_step_ca_service() {
    log_info "Waiting for Step-CA service in LXC 103 to become active..."
    local timeout=300 # 5 minutes
    local start_time=$SECONDS
    while (( SECONDS - start_time < timeout )); do
        if pct exec 103 -- systemctl is-active --quiet step-ca; then
            log_success "Step-CA service is active in LXC 103. Proceeding."
            return 0
        fi
        sleep 5
    done
    log_fatal "Timeout reached while waiting for Step-CA service in LXC 103."
}

# =====================================================================================
# Function: prepare_vm_ca_staging_area
# Description: Creates a dedicated staging area for the VM's CA files and copies
#              the necessary artifacts into it. This allows the VM to securely mount
#              the directory via NFS.
# Arguments:
#   $1 - The VMID of the target VM.
# =====================================================================================
prepare_vm_ca_staging_area() {
    local VMID="$1"
    log_info "Preparing CA file staging area for VM ${VMID}..."

    wait_for_step_ca_service

    local source_dir="/mnt/pve/quickOS/lxc-persistent-data/103/ssl"
    local dest_dir="/quickOS/vm-persistent-data/${VMID}/.step-ca"

    log_info "Creating and preparing staging directory: ${dest_dir}"
    mkdir -p "${dest_dir}"
    rm -f "${dest_dir}"/* # Clean out old files

    log_info "Copying CA files to staging area..."
    cp "${source_dir}/certs/root_ca.crt" "${dest_dir}/root_ca.crt"
    cp "${source_dir}/provisioner_password.txt" "${dest_dir}/provisioner_password.txt"
    cp "${source_dir}/root_ca.fingerprint" "${dest_dir}/root_ca.fingerprint"

    log_info "Setting world-readable permissions on staged CA files..."
    chmod 644 "${dest_dir}/root_ca.crt"
    chmod 644 "${dest_dir}/provisioner_password.txt"
    chmod 644 "${dest_dir}/root_ca.fingerprint"

    log_success "CA staging area for VM ${VMID} is ready."
}

# =====================================================================================
# Function: apply_vm_firewall_rules
# Description: Applies firewall rules to a VM based on its declarative configuration.
# Arguments:
#   $1 - The VMID of the VM to configure.
# =====================================================================================
apply_vm_firewall_rules() {
    local VMID="$1"
    log_info "Configuring firewall for VM $VMID to be managed by the host..."

    local firewall_enabled
    firewall_enabled=$(jq_get_vm_value "$VMID" ".firewall.enabled" || echo "false")
    log_info "Firewall enabled status for VM $VMID from config: '$firewall_enabled'"
    local conf_file="/etc/pve/qemu-server/${VMID}.conf"

    if [ ! -f "$conf_file" ]; then
        log_fatal "VM config file not found at $conf_file."
    fi

    if [ "$firewall_enabled" != "true" ]; then
        log_info "Firewall is not enabled for VM $VMID in its config. Disabling firewall..."
        run_qm_command set "$VMID" --firewall 0
        return 0
    fi

    # Enable the firewall for the VM itself using the correct qm command
    # The '--firewall' flag is not a valid option for `qm set`. The correct procedure
    # is to enable the firewall on the network interface directly, which is handled below.
    # This line is being removed to prevent fatal errors.
    # log_info "Enabling firewall for VM $VMID..."
    # run_qm_command set "$VMID" --firewall 1

    # Enable firewall on the net0 interface
    log_info "Enabling firewall on net0 interface for VM $VMID..."
    local current_net0
    current_net0=$(qm config "$VMID" | grep '^net0:' | sed 's/net0: //')
    if [[ ! "$current_net0" =~ firewall=1 ]]; then
        run_qm_command set "$VMID" --net0 "${current_net0},firewall=1"
    else
        log_info "Firewall is already enabled on net0 for VM $VMID."
    fi

    log_info "VM $VMID is now configured for host-level firewall management. Applying specific rules..."

    local firewall_rules_json
    firewall_rules_json=$(jq_get_vm_value "$VMID" ".firewall.rules")
    local vm_fw_file="/etc/pve/firewall/${VMID}.fw"

    # Create the firewall config file with default options
    echo "[OPTIONS]" > "$vm_fw_file"
    echo "enable: 1" >> "$vm_fw_file"
    echo "" >> "$vm_fw_file"
    echo "[RULES]" >> "$vm_fw_file"

    # Append rules from JSON config
    echo "$firewall_rules_json" | jq -c '.[]' | while read -r rule; do
        local type=$(echo "$rule" | jq -r '.type')
        local action=$(echo "$rule" | jq -r '.action')
        local proto=$(echo "$rule" | jq -r '.proto // ""')
        local port=$(echo "$rule" | jq -r '.port // ""')
        local source=$(echo "$rule" | jq -r '.source // ""')
        local dest=$(echo "$rule" | jq -r '.dest // ""')
        local comment=$(echo "$rule" | jq -r '.comment // ""')

        local rule_line="${type^^} ${action^^}"
        [ -n "$proto" ] && rule_line+=" -p $proto"
        [ -n "$port" ] && rule_line+=" -dport $port"
        [ -n "$source" ] && rule_line+=" -source $source"
        [ -n "$dest" ] && rule_line+=" -dest $dest"
        [ -n "$comment" ] && rule_line+=" # $comment"
        
        echo "$rule_line" >> "$vm_fw_file"
        log_info "  - Added rule: $rule_line"
    done

    log_info "Firewall rules for VM $VMID have been written to $vm_fw_file."
    log_info "Reloading Proxmox firewall to apply changes..."
    pve-firewall restart
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