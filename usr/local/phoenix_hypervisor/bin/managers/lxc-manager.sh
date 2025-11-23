#!/bin/bash
#
# File: lxc-manager.sh
# Description: This script provides a centralized set of functions for managing LXC containers within the
#              Phoenix Hypervisor system. It encapsulates all the logic for creating, configuring, starting,
#              and snapshotting containers, ensuring a consistent and reusable implementation across the platform.
#              This manager is designed to be executed by the main orchestrator or other management scripts.
#
# Dependencies:
#   - phoenix_hypervisor_common_utils.sh: A library of shared shell functions for logging, error handling, etc.
#   - jq: For parsing JSON configuration files.
#   - pct: The Proxmox command-line tool for LXC container management.
#
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

# --- Source common utilities ---
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# =====================================================================================
# Function: manage_ca_password_on_hypervisor
# Description: Ensures a persistent CA password file exists on the hypervisor for CTID 103.
#              If the file does not exist, a new strong password is generated and stored.
# Arguments:
#   $1 - The CTID of the container (expected to be 103).
# Returns:
#   None. Exits with a fatal error if directory or file operations fail.
# =====================================================================================
ca_password_file_on_host=""

# =====================================================================================
# Function: validate_inputs
# Description: Validates the essential inputs required for the script to operate, such as the
#              presence of the LXC configuration file and the validity of the provided CTID.
#              This function is a critical part of the script's pre-flight checks.
#
# Arguments:
#   $1 - The CTID of the container to validate.
#
# Returns:
#   None. The function will exit the script with a fatal error if any of the inputs are invalid.
# =====================================================================================
validate_inputs() {
    local CTID="$1"

    log_info "Starting input validation for CTID $CTID..."
    # Check if LXC_CONFIG_FILE environment variable is set
    if [ -z "$LXC_CONFIG_FILE" ]; then
        log_fatal "LXC_CONFIG_FILE environment variable is not set."
    fi
    log_info "LXC_CONFIG_FILE: $LXC_CONFIG_FILE"

    # Check if the LXC configuration file exists and is readable
    if [ ! -f "$LXC_CONFIG_FILE" ]; then
        log_fatal "LXC configuration file not found or not readable at $LXC_CONFIG_FILE."
    fi

    # Validate CTID format (positive integer)
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [ "$CTID" -le 0 ]; then
        log_fatal "Invalid CTID '$CTID'. Must be a positive integer."
    fi

    # Check if configuration for the given CTID exists in the LXC config file
    if ! jq_get_value "$CTID" ".name" > /dev/null; then
        log_fatal "Configuration for CTID $CTID not found in $LXC_CONFIG_FILE."
    fi
    log_info "Input validation passed."
}

# =====================================================================================
# Function: check_storage_pool_exists
# Description: Checks if a given storage pool exists on the Proxmox server. This is a crucial
#              pre-flight check to ensure that the storage specified in the configuration is
#              available before attempting to create a container or VM.
#
# Arguments:
#   $1 - The name of the storage pool to check.
#
# Returns:
#   None. The function will exit the script with a fatal error if the storage pool does not exist.
# =====================================================================================
check_storage_pool_exists() {
    local storage_pool_name="$1"
    log_info "Checking for existence of storage pool: $storage_pool_name"

    # The `pvesm status` command lists all available storage pools on the Proxmox server.
    # We parse the output to check if the specified pool is in the list.
    if ! pvesm status | awk 'NR>1 {print $1}' | grep -q "^${storage_pool_name}$"; then
        log_fatal "Storage pool '$storage_pool_name' does not exist on the Proxmox server."
    fi
    log_info "Storage pool '$storage_pool_name' found."
}

# =====================================================================================
# Function: create_container_from_template
# Description: Creates a new LXC container from a specified template file. This function reads
#              all the necessary parameters from the JSON configuration file, constructs the
#              `pct create` command, and executes it. It also handles the downloading of the
#              template if it is not already present on the system.
#
# Arguments:
#   $1 - The CTID of the container to create.
#
# Returns:
#   None. The function will exit the script with a fatal error if the `pct create` command fails.
# =====================================================================================
create_container_from_template() {
    local CTID="$1"
    log_info "Starting creation of container $CTID from template."

    # --- Retrieve all necessary parameters from the config file ---
    local hostname=$(jq_get_value "$CTID" ".name")
    local memory_mb=$(jq_get_value "$CTID" ".memory_mb")
    local cores=$(jq_get_value "$CTID" ".cores")
    local template_filename
    template_filename=$(jq_get_value "$CTID" ".template_file")
    local storage_id
    storage_id=$(get_global_config_value ".proxmox_storage_ids.fastData_shared_iso")
    local template_file="${storage_id}:vztmpl/${template_filename}"
    local storage_pool=$(jq_get_value "$CTID" ".storage_pool")
    local storage_size_gb=$(jq_get_value "$CTID" ".storage_size_gb")

    # --- Check for storage pool existence ---
    check_storage_pool_exists "$storage_pool"
    local features=$(jq_get_value "$CTID" ".features | join(\",\")" || echo "") # Features are handled separately
    local mac_address=$(jq_get_value "$CTID" ".mac_address")
    local unprivileged_bool=$(jq_get_value "$CTID" ".unprivileged")
    local unprivileged_val=$([ "$unprivileged_bool" == "true" ] && echo "1" || echo "0") # Convert boolean to 0 or 1

    # --- Construct network configuration string ---
    local net0_name=$(jq_get_value "$CTID" ".network_config.name")
    local net0_bridge=$(jq_get_value "$CTID" ".network_config.bridge")
    local net0_ip=$(jq_get_value "$CTID" ".network_config.ip")
    local net0_gw=$(jq_get_value "$CTID" ".network_config.gw")
    local mac_address=$(jq_get_value "$CTID" ".mac_address")
    local net0_string="name=${net0_name},bridge=${net0_bridge},ip=${net0_ip},gw=${net0_gw},hwaddr=${mac_address}" # Assemble network string
    local nameservers=$(jq_get_value "$CTID" ".network_config.nameservers" || echo "")
 
     # --- Build the pct create command array ---
    local pct_create_cmd=(
        create "$CTID" "$template_file"
        --hostname "$hostname"
        --memory "$memory_mb"
        --cores "$cores"
        --storage "$storage_pool"
        --rootfs "${storage_pool}:${storage_size_gb}"
        --net0 "$net0_string"
        --unprivileged "$unprivileged_val"
    )

    if [ -n "$nameservers" ]; then
        pct_create_cmd+=(--nameserver "$nameservers")
    fi

    # --- Execute the command ---
    if ! run_pct_command "${pct_create_cmd[@]}"; then
        log_fatal "'pct create' command failed for CTID $CTID."
    fi
    log_info "Container $CTID created from template successfully."
}

# =====================================================================================
# Function: clone_container
# Description: Clones an LXC container from a specified source container and snapshot. This
#              is a more efficient way to create new containers that are based on a common
#              template. The function performs pre-flight checks to ensure that the source
#              container and snapshot exist before attempting the clone operation.
#
# Arguments:
#   $1 - The CTID of the new container to create.
#
# Returns:
#   None. The function will exit the script with a fatal error if the `pct clone` command fails.
# =====================================================================================
clone_container() {
    local CTID="$1"
    local source_ctid=$(jq_get_value "$CTID" ".clone_from_ctid") # Retrieve source CTID from config
    log_info "Starting clone of container $CTID from source CTID $source_ctid."

    # --- Pre-flight checks for cloning ---
    # Ensure the source template exists before proceeding.
    if ! pct status "$source_ctid" > /dev/null 2>&1; then
        log_fatal "Source template $source_ctid does not exist. Cannot proceed with cloning."
    fi

    local hostname=$(jq_get_value "$CTID" ".name") # New hostname for the cloned container
 
     # --- Build the pct clone command array ---
    local pct_clone_cmd=(
        clone "$source_ctid" "$CTID"
        --hostname "$hostname"
    )

    # --- Execute the command ---
    if ! run_pct_command "${pct_clone_cmd[@]}"; then
        log_fatal "'pct clone' command failed for CTID $CTID."
    fi
    log_info "Container $CTID cloned from $source_ctid successfully."
}

# =====================================================================================
# Function: apply_resource_configs
# Description: Applies resource-related configurations to a container.
apply_resource_configs() {
    local CTID="$1"
    log_info "Applying resource configurations for CTID: $CTID"
    local memory_mb=$(jq_get_value "$CTID" ".memory_mb")
    local cores=$(jq_get_value "$CTID" ".cores")
    run_pct_command set "$CTID" --memory "$memory_mb" || log_fatal "Failed to set memory."
    run_pct_command set "$CTID" --cores "$cores" || log_fatal "Failed to set cores."
}

# Function: apply_startup_configs
# Description: Applies startup and boot-related configurations to a container.
apply_startup_configs() {
    local CTID="$1"
    log_info "Applying startup configurations for CTID: $CTID"
    local start_at_boot=$(jq_get_value "$CTID" ".start_at_boot")
    local boot_order=$(jq_get_value "$CTID" ".boot_order")
    local boot_delay=$(jq_get_value "$CTID" ".boot_delay")
    local start_at_boot_val=$([ "$start_at_boot" == "true" ] && echo "1" || echo "0")
    run_pct_command set "$CTID" --onboot "${start_at_boot_val}" || log_fatal "Failed to set onboot."
    run_pct_command set "$CTID" --startup "order=${boot_order},up=${boot_delay},down=${boot_delay}" || log_fatal "Failed to set startup."
}

# Function: apply_network_configs
# Description: Applies network configurations to a container.
apply_network_configs() {
    local CTID="$1"
    log_info "Applying network configurations for CTID: $CTID"
    local net0_name=$(jq_get_value "$CTID" ".network_config.name")
    local net0_bridge=$(jq_get_value "$CTID" ".network_config.bridge")
    local net0_ip=$(jq_get_value "$CTID" ".network_config.ip")
    local net0_gw=$(jq_get_value "$CTID" ".network_config.gw")
    local mac_address=$(jq_get_value "$CTID" ".mac_address")
    local net0_string="name=${net0_name},bridge=${net0_bridge},ip=${net0_ip},gw=${net0_gw},hwaddr=${mac_address}"

    # --- BEGIN PHOENIX-20 FIX ---
    # Check if the firewall is enabled for this container in the JSON config.
    # If so, append the firewall=1 flag directly to the network configuration string.
    # This closes the race condition where a container could exist without the flag.
    local firewall_enabled=$(jq_get_value "$CTID" ".firewall.enabled" || echo "false")
    if [ "$firewall_enabled" == "true" ]; then
        log_info "Firewall is enabled for CTID $CTID. Applying firewall=1 to net0."
        net0_string+=",firewall=1"
    fi
    # --- END PHOENIX-20 FIX ---

    run_pct_command set "$CTID" --net0 "$net0_string" || log_fatal "Failed to set network configuration."

    # --- Public Interface Configuration (Macvlan) ---
    local public_enabled=$(jq_get_value "$CTID" ".public_interface.enabled" || echo "false")
    if [ "$public_enabled" == "true" ]; then
        log_info "Public interface configuration detected for CTID $CTID."
        
        local public_bridge=$(get_global_config_value ".network.public_bridge")
        if [ -z "$public_bridge" ]; then
            log_fatal "Public bridge not defined in global config (network.public_bridge)."
        fi

        local pub_ip=$(jq_get_value "$CTID" ".public_interface.ip")
        local pub_gw=$(jq_get_value "$CTID" ".public_interface.gw")
        local pub_mac=$(jq_get_value "$CTID" ".public_interface.mac_address")
        local pub_type=$(jq_get_value "$CTID" ".public_interface.type" || echo "macvlan")
        local pub_mode=$(jq_get_value "$CTID" ".public_interface.mode" || echo "bridge")

        # Validate IP routability
        local ip_addr_only=${pub_ip%/*}
        if ! ip route get "$ip_addr_only" via "$pub_gw" dev "$public_bridge" >/dev/null 2>&1; then
             # Note: This check might be too strict if the host doesn't have an IP in that subnet,
             # but checking against the interface is good.
             # Simplified check: verify interface exists
             if ! ip link show "$public_bridge" >/dev/null 2>&1; then
                 log_fatal "Public bridge '$public_bridge' does not exist on host."
             fi
             # We proceed, assuming the IP is valid for the physical network attached to the bridge.
        fi

        log_info "Applying public interface (net1) to CTID $CTID..."
        # Correct Proxmox syntax: name,macaddr,bridge,type,mode,ip,gw
        local net1_string="name=eth1,macaddr=${pub_mac},bridge=${public_bridge},type=${pub_type}"
        
        if [ "$pub_type" == "macvlan" ]; then
            net1_string+=",mode=${pub_mode}"
        fi
        
        net1_string+=",ip=${pub_ip},gw=${pub_gw}"

        if [ "$firewall_enabled" == "true" ]; then
             net1_string+=",firewall=1"
        fi

        run_pct_command set "$CTID" --net1 "$net1_string" || log_fatal "Failed to set public interface configuration."
    fi

    local nameservers=$(jq_get_value "$CTID" ".network_config.nameservers" || echo "")
    if [ -n "$nameservers" ]; then
        run_pct_command set "$CTID" --nameserver "$nameservers" || log_fatal "Failed to set nameservers."
    fi
}

# Function: apply_proxmox_features
# Description: Applies Proxmox-specific features to a container.
apply_proxmox_features() {
    local CTID="$1"
    log_info "Applying Proxmox features for CTID: $CTID"
    local pct_options=$(jq_get_array "$CTID" ".pct_options // [] | .[]" || echo "")
    if [ -n "$pct_options" ]; then
        local features_to_set=()
        for option in $pct_options; do
            features_to_set+=("$option")
        done
        if [ ${#features_to_set[@]} -gt 0 ]; then
            local features_string=$(IFS=,; echo "${features_to_set[*]}")
            log_info "Applying features: $features_string"
            run_pct_command set "$CTID" --features "$features_string" || log_fatal "Failed to set Proxmox features."
        fi
    fi
}

# Function: apply_lxc_directives
# Description: Applies low-level LXC directives to a container's configuration file.
apply_lxc_directives() {
    local CTID="$1"
    log_info "Applying LXC directives for CTID: $CTID"
    local lxc_options=$(jq_get_array "$CTID" ".lxc_options[]" || echo "")
    if [ -n "$lxc_options" ]; then
        local conf_file="/etc/pve/lxc/${CTID}.conf"
        for option in $lxc_options; do
            if [[ "$option" == "lxc.cap.keep="* ]]; then
                local caps_to_keep=$(echo "$option" | cut -d'=' -f2)
                sed -i '/^lxc.cap.keep/d' "$conf_file"
                for cap in $(echo "$caps_to_keep" | tr ',' ' '); do
                    echo "lxc.cap.keep: $cap" >> "$conf_file" || log_fatal "Failed to add capability."
                done
            elif ! grep -qF "$option" "$conf_file"; then
                echo "$option" >> "$conf_file" || log_fatal "Failed to add LXC directive."
            fi
        done
    fi
}

# Function: apply_gpu_passthrough
# Description: Applies GPU passthrough configurations to a container.
apply_gpu_passthrough() {
    local CTID="$1"
    log_info "Applying GPU passthrough for CTID: $CTID"
    local gpu_assignment=$(jq_get_value "$CTID" ".gpu_assignment" || echo "none")
    if [ -n "$gpu_assignment" ] && [ "$gpu_assignment" != "none" ]; then
        local conf_file="/etc/pve/lxc/${CTID}.conf"
        local cgroup_entries=("lxc.cgroup2.devices.allow: c 195:* rwm" "lxc.cgroup2.devices.allow: c 243:* rwm")
        local mount_entries=("lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file" "lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file" "lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file")
        IFS=',' read -ra gpus <<< "$gpu_assignment"
        for gpu_idx in "${gpus[@]}"; do
            gpu_idx=$(echo "$gpu_idx" | xargs)
            local nvidia_device="/dev/nvidia${gpu_idx}"
            mount_entries+=("lxc.mount.entry: $nvidia_device ${nvidia_device#/} none bind,optional,create=file")
        done
        for entry in "${mount_entries[@]}" "${cgroup_entries[@]}"; do
            if ! grep -qF "$entry" "$conf_file"; then
                echo "$entry" >> "$conf_file" || log_fatal "Failed to add GPU passthrough entry."
            fi
        done
    fi
}

# Function: apply_id_mappings
# Description: Applies ID mappings for unprivileged containers.
apply_id_mappings() {
    local CTID="$1"
    log_info "Applying ID mappings for CTID: $CTID"
    local id_maps=$(jq_get_array "$CTID" "(.id_maps // [])[]" || echo "")
    if [ -n "$id_maps" ]; then
        local conf_file="/etc/pve/lxc/${CTID}.conf"
        sed -i '/^lxc.idmap:/d' "$conf_file"
        echo "lxc.idmap: u 0 100000 65536" >> "$conf_file"
        echo "lxc.idmap: g 0 100000 65536" >> "$conf_file"
    fi
}

# Function: apply_lxc_configurations
# Description: Main function to apply all configurations to a container.
apply_lxc_configurations() {
    local CTID="$1"
    log_info "Applying all configurations for CTID: $CTID"
    apply_resource_configs "$CTID"
    apply_startup_configs "$CTID"
    apply_network_configs "$CTID"
    # apply_apparmor_profile "$CTID"
    apply_proxmox_features "$CTID"
    apply_lxc_directives "$CTID"
    apply_gpu_passthrough "$CTID"
    apply_id_mappings "$CTID"
    log_info "All configurations applied successfully for CTID $CTID."
}


# =====================================================================================
# Function: ensure_container_defined
# Description: This function is a key part of the idempotent state machine. It checks if a
#              container with the specified CTID already exists. If it does, the function
#              does nothing. If it doesn't, it calls the appropriate function to create the
#              container, either from a template or by cloning another container.
#
# Arguments:
#   $1 - The CTID of the container to check.
#
# Returns:
#   0 on success, 1 on failure (if cloning fails and a retry is needed).
# =====================================================================================
ensure_container_defined() {
    local CTID="$1"
    log_info "Ensuring container $CTID is defined..."
    if pct status "$CTID" > /dev/null 2>&1; then
        log_info "Container $CTID already exists. Skipping creation."
        return 0
    fi
    log_info "Container $CTID does not exist. Proceeding with creation..."
    if jq -e ".lxc_configs[\"$CTID\"].clone_from_ctid" "$LXC_CONFIG_FILE" > /dev/null; then
        local clone_source
        clone_source=$(jq -r ".lxc_configs[\"$CTID\"].clone_from_ctid" "$LXC_CONFIG_FILE")
        if ! pct status "$clone_source" > /dev/null 2>&1; then
            ensure_container_defined "$clone_source"
        fi
        
        if ! clone_container "$CTID"; then
            return 1
        fi
    elif jq -e ".lxc_configs[\"$CTID\"].template" "$LXC_CONFIG_FILE" > /dev/null; then
        create_container_from_os_template "$CTID"
    else
        log_fatal "No creation method found for $CTID. It must have either a 'clone_from_ctid' or a 'template' defined."
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
}

# =====================================================================================
# Function: apply_zfs_volumes
# Description: Creates and attaches ZFS volumes to a container. This allows for dedicated
#              storage to be attached to a container, which is useful for applications that
#              require large amounts of storage or specific ZFS features.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if volume creation fails.
# =====================================================================================
apply_zfs_volumes() {
    local CTID="$1"
    log_info "Applying ZFS volumes for CTID: $CTID..."

    local volumes
    volumes=$(jq_get_array "$CTID" "(.zfs_volumes // [])[]" || echo "")
    if [ -z "$volumes" ]; then
        log_info "No ZFS volumes to apply for CTID $CTID."
        return 0
    fi

    local volume_index=0
    # Find the next available mount point index
    while pct config "$CTID" | grep -q "mp${volume_index}:"; do
        volume_index=$((volume_index + 1))
    done

    for volume_config in $(echo "$volumes" | jq -c '.'); do
        local volume_name=$(echo "$volume_config" | jq -r '.name')
        local storage_pool=$(echo "$volume_config" | jq -r '.pool')
        local size_gb=$(echo "$volume_config" | jq -r '.size_gb')
        local mount_point=$(echo "$volume_config" | jq -r '.mount_point')
        local volume_id="mp${volume_index}"

        # Check if the volume is already configured
        if pct config "$CTID" | grep -q "${volume_id}:.*,mp=${mount_point}"; then
            log_info "Volume '${volume_name}' (${volume_id}) already exists for CTID $CTID."
        else
            log_info "Creating and attaching volume '${volume_name}' to CTID $CTID..."
            run_pct_command set "$CTID" --"${volume_id}" "${storage_pool}:${size_gb},mp=${mount_point}" || log_fatal "Failed to create volume '${volume_name}'."
        fi
        volume_index=$((volume_index + 1))
    done
}

# =====================================================================================
# Function: apply_secure_permissions
# Description: Applies secure permissions to the dedicated SSL volumes for containers
#              that require them.
# Arguments:
#   $1 - The CTID of the container.
# Returns:
#   None.
# =====================================================================================
apply_secure_permissions() {
    local CTID="$1"
    log_info "Applying secure permissions for CTID: $CTID..."

    case "$CTID" in
        101|102|103)
            local ssl_volume_path="/mnt/pve/quickOS/lxc-persistent-data/${CTID}/ssl"
            if [ -d "$ssl_volume_path" ]; then
                log_info "Setting secure permissions for SSL volume at $ssl_volume_path..."
                chown -R root:root "$ssl_volume_path" || log_warn "Failed to set ownership on SSL volume for CTID ${CTID}."
                chmod -R 700 "$ssl_volume_path" || log_warn "Failed to set permissions on SSL volume for CTID ${CTID}."
            fi
            ;;
        *)
            log_info "No secure permissions to apply for CTID $CTID."
            ;;
    esac
}

# =====================================================================================
# Function: apply_dedicated_volumes
# Description: Creates and attaches dedicated storage volumes to a container. This is similar
#              to `apply_zfs_volumes` but is intended for more general-purpose storage.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if volume creation fails.
# =====================================================================================
apply_dedicated_volumes() {
    local CTID="$1"
    log_info "Applying dedicated volumes for CTID: $CTID..."

    local volumes
    volumes=$(jq_get_array "$CTID" "(.volumes // [])[]" || echo "")
    if [ -z "$volumes" ]; then
        log_info "No dedicated volumes to apply for CTID $CTID."
        return 0
    fi

    local volume_index=0
    for volume_config in $(echo "$volumes" | jq -c '.'); do
        local volume_name=$(echo "$volume_config" | jq -r '.name')
        local storage_pool=$(echo "$volume_config" | jq -r '.pool')
        local size_gb=$(echo "$volume_config" | jq -r '.size_gb')
        local mount_point=$(echo "$volume_config" | jq -r '.mount_point')
        local volume_id="mp${volume_index}"

        # Check if the volume is already configured
        if pct config "$CTID" | grep -q "${volume_id}:.*,mp=${mount_point}"; then
            log_info "Volume '${volume_name}' (${volume_id}) already exists for CTID $CTID."
        else
            log_info "Creating and attaching volume '${volume_name}' to CTID $CTID..."
            run_pct_command set "$CTID" --"${volume_id}" "${storage_pool}:${size_gb},mp=${mount_point}" || log_fatal "Failed to create volume '${volume_name}'."
        fi
        volume_index=$((volume_index + 1))
    done
}

# =====================================================================================
# Function: apply_mount_points
# Description: Mounts shared host directories into the container as defined in the
#              container's specific configuration.
# =====================================================================================
apply_mount_points() {
    local CTID="$1"
    log_info "Applying host path mount points for CTID: $CTID..."

    local mounts
    mounts=$(jq_get_array "$CTID" "(.mount_points // [])[]" || echo "")
    # Find the next available mount point index
    local volume_index=0
    while pct config "$CTID" | grep -q "mp${volume_index}:"; do
        volume_index=$((volume_index + 1))
    done

    if [ -n "$mounts" ]; then
        for mount_config in $(echo "$mounts" | jq -c '.'); do
            local host_path=$(echo "$mount_config" | jq -r '.host_path')
            local container_path=$(echo "$mount_config" | jq -r '.container_path')
            local mount_id="mp${volume_index}"
            local mount_string="${host_path},mp=${container_path}"

            # Idempotency Check
            if ! pct config "$CTID" | grep -q "mp.*:${mount_string}"; then
                log_info "Verifying host path '$host_path' before applying mount..."
                # --- BEGIN DIAGNOSTIC LOGGING ---
                log_debug "Checking if host path '$host_path' exists."
                if [ ! -e "$host_path" ]; then
                    # Check if the path looks like a file
                    if [[ "$host_path" == *.* ]]; then
                        # It's a file, so ensure the parent directory exists
                        local parent_dir=$(dirname "$host_path")
                        if [ ! -d "$parent_dir" ]; then
                            log_warn "Parent directory '$parent_dir' for file mount does not exist. Creating it now."
                            if ! mkdir -p "$parent_dir"; then
                                log_fatal "Failed to create parent directory '$parent_dir'."
                            fi
                            log_success "Parent directory '$parent_dir' created successfully."
                        fi
                    else
                        # It's a directory, create it
                        log_warn "Host path '$host_path' does not exist. Creating it now."
                        if ! mkdir -p "$host_path"; then
                            log_fatal "Failed to create host path directory '$host_path'."
                        fi
                        log_success "Host path '$host_path' created successfully."
                    fi
                else
                    log_debug "Host path '$host_path' found."
                fi
                # --- END DIAGNOSTIC LOGGING ---

                # NEW: Special handling for Nginx log directory permissions
                if [[ "$host_path" == *"/101/logs" ]]; then
                    log_info "Setting ownership of Nginx log directory on host..."
                    if ! chown -R 33:33 "$host_path"; then
                        log_fatal "Failed to set ownership of Nginx log directory '$host_path'."
                    fi
                    log_success "Ownership of Nginx log directory set to 33:33."
                fi

                log_info "Applying mount: ${host_path} -> ${container_path}"
                run_pct_command set "$CTID" --"${mount_id}" "$mount_string" || log_fatal "Failed to apply mount."
                log_debug "Mount command executed for ${host_path} -> ${container_path} with ID ${mount_id}."
                volume_index=$((volume_index + 1))
            else
                log_info "Mount point ${host_path} -> ${container_path} already configured."
                log_debug "Skipping mount as it's already configured."
            fi
        done
    else
        log_info "No host path mount points to apply for CTID $CTID."
    fi

}

# =====================================================================================
# Function: apply_host_path_permissions
# Description: Sets the correct ownership on host-side directories for bind mounts.
# =====================================================================================
apply_host_path_permissions() {
    local CTID="$1"
    log_info "Applying host path permissions for CTID: $CTID..."

    local mounts
    mounts=$(jq_get_array "$CTID" "(.mount_points // [])[]" || echo "")
    if [ -z "$mounts" ]; then
        log_info "No host path mount points to set permissions for CTID $CTID."
        return 0
    fi

    for mount_config in $(echo "$mounts" | jq -c '.'); do
        local host_path=$(echo "$mount_config" | jq -r '.host_path')
        local owner_uid=$(echo "$mount_config" | jq -r '.owner_uid // ""')
        local owner_gid=$(echo "$mount_config" | jq -r '.owner_gid // ""')

        if [ -n "$owner_uid" ] && [ -n "$owner_gid" ]; then
            local host_uid=$((100000 + owner_uid))
            local host_gid=$((100000 + owner_gid))
            log_info "Setting ownership of '$host_path' to $host_uid:$host_gid..."
            if ! chown -R "$host_uid:$host_gid" "$host_path"; then
                log_fatal "Failed to set ownership of '$host_path'."
            fi
            log_success "Ownership of '$host_path' set successfully."
        fi
    done
}

# =====================================================================================
# Function: ensure_container_disk_size
# Description: Ensures that the container's root disk size matches the size specified in the
#              configuration file. The `pct resize` command is idempotent, so this function
# #              can be run multiple times without causing issues.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if the `pct resize` command fails.
# =====================================================================================
ensure_container_disk_size() {
    local CTID="$1"
    log_info "Ensuring correct disk size for CTID: $CTID"
    local storage_size_gb
    storage_size_gb=$(jq_get_value "$CTID" ".storage_size_gb")

    # The pct resize command is idempotent for our purposes.
    # It sets the disk to the specified size.
    run_pct_command resize "$CTID" rootfs "${storage_size_gb}G"
    log_info "Disk size for CTID $CTID set to ${storage_size_gb}G."
}

# =====================================================================================
# Function: start_container
# Description: Starts the specified LXC container. This function includes retry logic to
#              handle transient startup issues, making the orchestration process more robust.
#              It also checks if the container is already running to maintain idempotency.
#
# Arguments:
#   $1 - The CTID of the container to start.
#
# Returns:
#   0 on successful container start. The function will exit with a fatal error if the
#   container fails to start after all retries.
# =====================================================================================
start_container() {
    local CTID="$1"
    log_info "Attempting to start container CTID: $CTID..."

    # Check if the container is already running
    if pct status "$CTID" | grep -q "status: running"; then
        log_info "Container $CTID is already running. Skipping start attempt."
        return 0
    fi

    log_info "Container $CTID is not running. Proceeding with start..."
    local attempts=0 # Counter for startup attempts
    local max_attempts=3 # Maximum number of startup attempts
    local interval=5 # Delay between retries in seconds

    # Loop to attempt container startup with retries
    while [ "$attempts" -lt "$max_attempts" ]; do
        if run_pct_command start "$CTID"; then
            log_info "Container $CTID started successfully."
            return 0
        else
            attempts=$((attempts + 1))
            log_error "WARNING: 'pct start' command failed for CTID $CTID (Attempt $attempts/$max_attempts)."
            if [ "$attempts" -lt "$max_attempts" ]; then
                log_info "Retrying in $interval seconds..."
                sleep "$interval" # Wait before retrying
            fi
        fi
    done

    log_fatal "Container $CTID failed to start after $max_attempts attempts."
}

# =====================================================================================
# Function: apply_features
# Description: Iterates through the 'features' array in the container's JSON configuration
#              and executes the corresponding feature installation script. Each feature script
#              is expected to be idempotent, meaning it can be run multiple times without
#              changing the result beyond the initial application.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if a feature script is not found or fails.
# =====================================================================================
apply_features() {
    local CTID="$1"
    log_info "Applying features for CTID: $CTID"
    local features
    features=$(jq_get_array "$CTID" ".features[]" || echo "")
    if [ -z "$features" ]; then
        log_info "No features to apply for CTID $CTID."
        return 0
    fi

    log_info "Features to apply for CTID $CTID: $features"

    for feature in $features; do
        local feature_script_path="${PHOENIX_BASE_DIR}/bin/lxc_setup/phoenix_hypervisor_feature_install_${feature}.sh"
        log_info "Executing feature: $feature ($feature_script_path)"

        if [ ! -f "$feature_script_path" ]; then
            log_fatal "Feature script not found at $feature_script_path."
        fi

        local bootstrap_ca_url=$(jq_get_value "$CTID" ".bootstrap_ca_url" || echo "")
        if ! (set +e; "$feature_script_path" "$CTID" "$bootstrap_ca_url"); then
            log_error "Feature script '$feature' failed for CTID $CTID."
            return 1
        fi
    done

    log_info "All features applied successfully for CTID $CTID."
}

# =====================================================================================
# Function: run_portainer_script
# Description: Executes the Portainer feature script for the container if a Portainer role
#              is defined in the configuration. This is a specialized feature that sets up
#              the container as either a Portainer server or agent.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if the script fails.
# =====================================================================================
run_portainer_script() {
    local CTID="$1"
    log_info "Checking for Portainer feature for CTID: $CTID"
    local portainer_role
    portainer_role=$(jq_get_value "$CTID" ".portainer_role" || echo "")

    if [ -z "$portainer_role" ] || [ "$portainer_role" == "none" ]; then
        log_info "No Portainer role to apply for CTID $CTID."
        return 0
    fi

    local portainer_script_path="${PHOENIX_BASE_DIR}/bin/lxc_setup/phoenix_hypervisor_feature_install_portainer.sh"
    log_info "Executing Portainer feature script: $portainer_script_path"

    if [ ! -f "$portainer_script_path" ]; then
        log_fatal "Portainer feature script not found at $portainer_script_path."
    fi

    if ! "$portainer_script_path" "$CTID"; then
        log_fatal "Portainer feature script failed for CTID $CTID."
    fi

    log_info "Portainer feature script applied successfully for CTID $CTID."
}

# =====================================================================================
# Function: gather_and_push_certificates
# Description: Gathers necessary TLS certificates from various locations on the host
#              and pushes them into the container's temporary execution directory.
# Arguments:
#   $1 - The CTID of the container.
#   $2 - The path to the temporary directory inside the container.
# =====================================================================================
gather_and_push_certificates() {
    local CTID="$1"
    local temp_dir_in_container="$2"

    if [ "$CTID" -eq 101 ]; then
        log_info "Gathering and pushing certificates for NGINX container..."
        local nginx_cert_path="/mnt/pve/quickOS/lxc-persistent-data/101/ssl/nginx.internal.thinkheads.ai.crt"
        local nginx_key_path="/mnt/pve/quickOS/lxc-persistent-data/101/ssl/nginx.internal.thinkheads.ai.key"
        local portainer_cert_path="/mnt/pve/quickOS/vm-persistent-data/1001/portainer/certs/portainer.crt"
        local portainer_key_path="/mnt/pve/quickOS/vm-persistent-data/1001/portainer/certs/portainer.key"

        pct push "$CTID" "$nginx_cert_path" "${temp_dir_in_container}/nginx.internal.thinkheads.ai.crt" || log_fatal "Failed to copy NGINX cert"
        pct push "$CTID" "$nginx_key_path" "${temp_dir_in_container}/nginx.internal.thinkheads.ai.key" || log_fatal "Failed to copy NGINX key"
        pct push "$CTID" "$portainer_cert_path" "${temp_dir_in_container}/portainer.internal.thinkheads.ai.crt" || log_fatal "Failed to copy Portainer cert"
        pct push "$CTID" "$portainer_key_path" "${temp_dir_in_container}/portainer.internal.thinkheads.ai.key" || log_fatal "Failed to copy Portainer key"
    fi
}

# =====================================================================================
# Function: run_application_script
# Description: Executes a final application-specific script for the LXC container if one is
#              defined in its JSON configuration. This allows for application-level setup
#              and configuration to be performed after the container and its features have
#              been provisioned. The script is executed inside the container using `pct exec`.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if the application script is not found or fails.
# =====================================================================================
run_application_script() {
    local CTID="$1"
    shift # Shift off the CTID, leaving the rest of the arguments in "$@"
    log_info "Waiting for container to settle before running application script..."
    sleep 10
    log_info "Checking for application script for CTID: $CTID"
    local app_script_name # Variable to store the application script name
    app_script_name=$(jq_get_value "$CTID" ".application_script" || echo "") # Retrieve application script name from config

    # If no application script is defined, log and exit
    if [ -z "$app_script_name" ]; then
        log_info "No application script to run for CTID $CTID."
        return 0
    fi

    local app_script_path="${PHOENIX_BASE_DIR}/bin/${app_script_name}" # Construct full script path from PHOENIX_BASE_DIR
    log_info "Executing application script inside container: $app_script_name ($app_script_path)"

    # Check if the application script exists
    if [ ! -f "$app_script_path" ]; then
        log_fatal "Application script not found at $app_script_path."
    fi

    # --- New Robust Script Execution Model ---
    # This model ensures that the script and its dependencies are available inside the container.
    local temp_dir_in_container="/tmp/phoenix_run"
    local common_utils_source_path="${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"
    local common_utils_dest_path="${temp_dir_in_container}/phoenix_hypervisor_common_utils.sh"
    local app_script_dest_path="${temp_dir_in_container}/${app_script_name}"

    # 1. Create a temporary directory in the container
    log_info "Creating temporary directory in container: $temp_dir_in_container"
    if ! pct exec "$CTID" -- mkdir -p "$temp_dir_in_container"; then
        log_fatal "Failed to create temporary directory in container $CTID."
    fi

    # Verification step
    log_info "Verifying temporary directory creation..."
    if ! pct exec "$CTID" -- test -d "$temp_dir_in_container"; then
        log_fatal "Verification failed: Temporary directory '$temp_dir_in_container' does not exist in container $CTID."
    fi
    log_info "Temporary directory verified successfully."

    # 2. Copy common_utils.sh to the container
    log_info "Copying common utilities to $CTID:$common_utils_dest_path..."
    if ! pct push "$CTID" "$common_utils_source_path" "$common_utils_dest_path"; then
        log_fatal "Failed to copy common_utils.sh to container $CTID."
    fi
 
    # 3. Copy the application script to the container
    log_info "Copying application script to $CTID:$app_script_dest_path..."
    if ! pct push "$CTID" "$app_script_path" "$app_script_dest_path"; then
        log_fatal "Failed to copy application script to container $CTID."
    fi

    # Also copy the Traefik config generator script if it's the Traefik container
    if [ "$app_script_name" == "phoenix_hypervisor_lxc_102.sh" ]; then
        local traefik_generator_script_path="${PHOENIX_BASE_DIR}/bin/generate_traefik_config.sh"
        local traefik_generator_dest_path="${temp_dir_in_container}/generate_traefik_config.sh"
        log_info "Copying Traefik config generator to $CTID:$traefik_generator_dest_path..."
        if ! pct push "$CTID" "$traefik_generator_script_path" "$traefik_generator_dest_path"; then
            log_fatal "Failed to copy Traefik config generator to container $CTID."
        fi
        log_info "Making Traefik config generator executable in container..."
        if ! pct exec "$CTID" -- chmod +x "$traefik_generator_dest_path"; then
            log_fatal "Failed to make Traefik config generator executable in container $CTID."
        fi

        # Also copy the Traefik template file
        local traefik_template_source_path="${PHOENIX_BASE_DIR}/etc/traefik/traefik.yml.template"
        local traefik_template_dest_path="${temp_dir_in_container}/traefik.yml.template"
        log_info "Copying Traefik template to $CTID:$traefik_template_dest_path..."
        if ! pct push "$CTID" "$traefik_template_source_path" "$traefik_template_dest_path"; then
            log_fatal "Failed to copy Traefik template to container $CTID."
        fi
    fi

    # --- START OF MODIFICATIONS FOR NGINX AND TRAEFIK CONFIG PUSH ---
    # If the application script is for the Nginx gateway (101) or Traefik (102), push the necessary configs.
    if [[ "$app_script_name" == "phoenix_hypervisor_lxc_101.sh" ]] || [[ "$app_script_name" == "phoenix_hypervisor_lxc_102.sh" ]]; then
        log_info "Packaging and pushing configuration files for $app_script_name..."
        
        if [[ "$app_script_name" == "phoenix_hypervisor_lxc_101.sh" ]]; then
            # --- BEGIN PUSH ROOT CA TO NGINX CONTAINER ---
            log_info "Pushing Root CA certificate to Nginx container (CTID 101)..."
            local root_ca_on_host="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt"
            local root_ca_dest_in_101="/tmp/root_ca.crt"

            if ! pct push 101 "$root_ca_on_host" "$root_ca_dest_in_101"; then
                log_fatal "Failed to push Root CA from host to CTID 101."
            fi
            log_info "Root CA successfully pushed to CTID 101."
            # --- END PUSH ROOT CA TO NGINX CONTAINER ---

            local nginx_config_path="${PHOENIX_BASE_DIR}/etc/nginx"
            local temp_tarball="/tmp/nginx_configs_${CTID}.tar.gz"

            # --- REMEDIATION: Generate dynamic config on the host before packaging ---
            # This block is being intentionally commented out. The dynamic gateway configuration
            # requires an SSL certificate that does not exist at this stage of the 'create'
            # process. The Nginx container's own application script creates a placeholder
            # configuration to allow Nginx to start. The final configuration will be
            # generated and applied by the 'phoenix sync all' command.
            #
            # log_info "Generating dynamic Nginx gateway configuration on the host..."
            # local nginx_generator_script="${PHOENIX_BASE_DIR}/bin/generate_nginx_gateway_config.sh"
            # if [ ! -f "$nginx_generator_script" ]; then
            #     log_fatal "Nginx config generator script not found at $nginx_generator_script."
            # fi
            # if ! "$nginx_generator_script"; then
            #     log_fatal "Failed to generate dynamic Nginx configuration on the host."
            # fi
            # log_info "Dynamic Nginx configuration generated successfully."
            # --- END REMEDIATION ---

            # --- NEW LOGIC: Push individual Nginx config files ---
            log_info "Pushing individual Nginx configuration files to container..."
            
            # Define source paths on the host
            local nginx_conf_src="${nginx_config_path}/nginx.conf"
            local gateway_conf_src="${nginx_config_path}/sites-available/gateway"
            local stream_conf_src="${nginx_config_path}/stream.d/stream-gateway.conf"

            # Define destination paths in the container
            local nginx_conf_dest="${temp_dir_in_container}/nginx.conf"
            local gateway_conf_dest="${temp_dir_in_container}/sites-available/gateway"
            local stream_conf_dest="${temp_dir_in_container}/stream.d/stream-gateway.conf"

            # Create necessary subdirectories in the container's temp directory
            pct exec "$CTID" -- mkdir -p "${temp_dir_in_container}/sites-available"
            pct exec "$CTID" -- mkdir -p "${temp_dir_in_container}/stream.d"

            # Push the files
            if [ ! -f "$nginx_conf_src" ]; then log_fatal "Nginx config source file not found: $nginx_conf_src"; fi
            pct push "$CTID" "$nginx_conf_src" "$nginx_conf_dest" || log_fatal "Failed to push nginx.conf to CTID $CTID."
            if [ ! -f "$gateway_conf_src" ]; then log_fatal "Nginx gateway config source file not found: $gateway_conf_src"; fi
            pct push "$CTID" "$gateway_conf_src" "$gateway_conf_dest" || log_fatal "Failed to push gateway config to CTID $CTID."
            if [ ! -f "$stream_conf_src" ]; then log_fatal "Nginx stream config source file not found: $stream_conf_src"; fi
            pct push "$CTID" "$stream_conf_src" "$stream_conf_dest" || log_fatal "Failed to push stream gateway config to CTID $CTID."
            
            log_info "All Nginx configuration files pushed successfully."
            # --- END NEW LOGIC ---
        fi

        if [[ "$app_script_name" == "phoenix_hypervisor_lxc_102.sh" ]]; then
            local traefik_config_path="${PHOENIX_BASE_DIR}/etc/traefik/dynamic_conf.yml"
            if [ -f "$traefik_config_path" ]; then
                if ! pct push "$CTID" "$traefik_config_path" "/etc/traefik/dynamic/dynamic_conf.yml"; then
                    log_fatal "Failed to push Traefik dynamic config to container $CTID."
                fi
            else
                log_warn "Traefik dynamic configuration not found at $traefik_config_path. Skipping."
            fi
        fi
    fi
    # --- END OF MODIFICATIONS FOR NGINX AND TRAEFIK CONFIG PUSH ---

    # This block is now redundant and has been removed.

    # 2. Copy common_utils.sh to the container
    log_info "Copying common utilities to $CTID:$common_utils_dest_path..."
    if ! pct push "$CTID" "$common_utils_source_path" "$common_utils_dest_path"; then
        log_fatal "Failed to copy common_utils.sh to container $CTID."
    fi
    
    # 3d. Copy the LXC config file to the container's temp directory
    local lxc_config_dest_path="${temp_dir_in_container}/phoenix_lxc_configs.json"
    log_info "Copying LXC config to $CTID:$lxc_config_dest_path..."
    if ! pct push "$CTID" "$LXC_CONFIG_FILE" "$lxc_config_dest_path"; then
        log_fatal "Failed to copy LXC config file to container $CTID."
    fi

    # Also copy the VM and hypervisor configs
    local vm_config_file="${PHOENIX_BASE_DIR}/etc/phoenix_vm_configs.json"
    local vm_config_dest_path="${temp_dir_in_container}/phoenix_vm_configs.json"
    log_info "Copying VM config to $CTID:$vm_config_dest_path..."
    if ! pct push "$CTID" "$vm_config_file" "$vm_config_dest_path"; then
        log_fatal "Failed to copy VM config file to container $CTID."
    fi

    local hypervisor_config_file="${PHOENIX_BASE_DIR}/etc/phoenix_hypervisor_config.json"
    local hypervisor_config_dest_path="${temp_dir_in_container}/phoenix_hypervisor_config.json"
    log_info "Copying hypervisor config to $CTID:$hypervisor_config_dest_path..."
    if ! pct push "$CTID" "$hypervisor_config_file" "$hypervisor_config_dest_path"; then
        log_fatal "Failed to copy hypervisor config file to container $CTID."
    fi

    # --- Copy Certificates ---
    if [ "$CTID" -eq 101 ]; then
        log_info "Copying certificates to NGINX container..."
        local nginx_cert_path="/mnt/pve/quickOS/lxc-persistent-data/101/ssl/nginx.internal.thinkheads.ai.crt"
        local nginx_key_path="/mnt/pve/quickOS/lxc-persistent-data/101/ssl/nginx.internal.thinkheads.ai.key"
        local portainer_cert_path="/mnt/pve/quickOS/vm-persistent-data/1001/portainer/certs/portainer.crt"
        local portainer_key_path="/mnt/pve/quickOS/vm-persistent-data/1001/portainer/certs/portainer.key"

        pct push "$CTID" "$nginx_cert_path" "${temp_dir_in_container}/nginx.internal.thinkheads.ai.crt" || log_fatal "Failed to copy NGINX cert"
        pct push "$CTID" "$nginx_key_path" "${temp_dir_in_container}/nginx.internal.thinkheads.ai.key" || log_fatal "Failed to copy NGINX key"
        pct push "$CTID" "$portainer_cert_path" "${temp_dir_in_container}/portainer.internal.thinkheads.ai.crt" || log_fatal "Failed to copy Portainer cert"
        pct push "$CTID" "$portainer_key_path" "${temp_dir_in_container}/portainer.internal.thinkheads.ai.key" || log_fatal "Failed to copy Portainer key"
    fi

    # 4. Make the application script executable
    log_info "Making application script executable in container..."
    if ! pct exec "$CTID" -- chmod +x "$app_script_dest_path"; then
        log_fatal "Failed to make application script executable in container $CTID."
    fi

    # 5. Execute the application script
    log_info "Executing application script in container..."
    if ! pct exec "$CTID" -- "$app_script_dest_path" "$CTID" "$@"; then
        log_fatal "Application script '$app_script_name' failed for CTID $CTID."
    fi

    # 6. Clean up the temporary directory
    log_info "Cleaning up temporary directory in container..."
    if ! pct exec "$CTID" -- rm -rf "$temp_dir_in_container"; then
        log_warn "Failed to clean up temporary directory in container $CTID."
    fi

    log_info "Application script executed successfully for CTID $CTID."
}

# =====================================================================================
# Function: run_health_check
# Description: Executes a health check command inside the container if one is defined in
#              the configuration. This allows for application-level health checks to be
#              performed after the container is fully provisioned. The function includes
#              retry logic to handle services that may take some time to start.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if the health check fails after all retries.
# =====================================================================================
run_health_check() {
    local CTID="$1"
    log_info "Checking for health check for CTID: $CTID"
    # --- NVIDIA Health Check ---
    local features
    features=$(jq_get_array "$CTID" ".features[]" || echo "")
    if [[ " ${features[*]} " =~ " nvidia " ]]; then
        log_info "NVIDIA feature detected. Running NVIDIA health check..."
        local nvidia_check_script="${PHOENIX_BASE_DIR}/bin/health_checks/check_nvidia.sh"
        if ! "$nvidia_check_script" "$CTID"; then
            log_fatal "NVIDIA health check failed for CTID $CTID."
        fi
    fi

    # --- Declarative Health Checks ---
    local health_checks_json
    health_checks_json=$(jq_get_value "$CTID" ".health_checks" || echo "")

    if [ -z "$health_checks_json" ] || [ "$health_checks_json" == "null" ] || [ "$health_checks_json" == "[]" ]; then
        log_info "No declarative health checks to run for CTID $CTID."
        return 0
    fi

    echo "$health_checks_json" | jq -c '.[]' | while read -r check_config; do
        local check_name=$(echo "$check_config" | jq -r '.name')
        local check_script=$(echo "$check_config" | jq -r '.script')
        local check_args=$(echo "$check_config" | jq -r '.args // ""')
        local health_check_command="${PHOENIX_BASE_DIR}/bin/health_checks/${check_script} ${check_args}"

        log_info "Running health check: $check_name"
        if ! eval "$health_check_command"; then
            log_fatal "Health check '$check_name' failed for CTID $CTID."
        fi
    done
}


# =====================================================================================
# Function: run_post_deployment_validation
# Description: Executes post-deployment validation tests for a container if they are defined
#              in the configuration. This allows for automated testing to be performed after
#              a container is provisioned, ensuring that it is functioning correctly.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   0 on success, 1 on failure.
# =====================================================================================
run_post_deployment_validation() {
    local CTID="$1"
    log_info "Checking for post-deployment validation for CTID: $CTID"
    local test_suites
    test_suites=$(jq_get_array "$CTID" ".tests | keys[]" || echo "")

    if [ -z "$test_suites" ]; then
        log_info "No test suites found for CTID $CTID. Skipping post-deployment validation."
        return 0
    fi

    for suite in $test_suites; do
        log_info "Running test suite '$suite' for CTID $CTID..."
        local test_runner_script="${PHOENIX_BASE_DIR}/bin/tests/test_runner.sh"
        if [ ! -x "$test_runner_script" ]; then
            log_info "Making test runner script executable..."
            chmod +x "$test_runner_script"
        fi
        if ! "$test_runner_script" "$CTID" "$suite"; then
            log_error "Test suite '$suite' failed for CTID $CTID."
            return 1
        fi
    done

    log_info "Post-deployment validation completed successfully for CTID $CTID."
}

# =====================================================================================
# Function: create_template_snapshot
# Description: Creates a snapshot of an LXC container if it is designated as a template in
#              the configuration file. This is a key part of the container templating
#              strategy, allowing for new containers to be quickly cloned from a pre-configured
#              template. The function is idempotent and will not create a snapshot if one
#              with the same name already exists.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if snapshot creation fails.
# =====================================================================================
create_template_snapshot() {
    local CTID="$1"
    log_info "Checking for template snapshot for CTID: $CTID"
    local is_template
    is_template=$(jq -r ".lxc_configs[\"$CTID\"].is_template // false" "$LXC_CONFIG_FILE")
    if [ "$is_template" == "true" ]; then
        log_info "Container $CTID is a template, skipping all snapshot creation."
        return 0
    fi
    local snapshot_name # Variable to store the template snapshot name
    snapshot_name=$(jq_get_value "$CTID" ".template_snapshot_name" || echo "") # Retrieve snapshot name from config

    # If no template snapshot name is defined, log and exit
    if [ -z "$snapshot_name" ]; then
        log_info "No template snapshot defined for CTID $CTID. Skipping."
        return 0
    fi

    # Check if the snapshot already exists
    if pct listsnapshot "$CTID" | grep -q "$snapshot_name"; then
        log_info "Snapshot '$snapshot_name' already exists for CTID $CTID. Skipping."
        return 0
    fi

    log_info "Creating snapshot '$snapshot_name' for template container $CTID..."
    # Execute the `pct snapshot` command
    local snapshot_output
    if ! snapshot_output=$(run_pct_command snapshot "$CTID" "$snapshot_name" 2>&1); then
        if [[ "$snapshot_output" == *"snapshot feature is not available"* ]]; then
            log_warn "[WARNING] Snapshot feature is not available for CTID $CTID. Skipping snapshot creation."
        else
            log_fatal "Failed to create snapshot '$snapshot_name' for CTID $CTID. Error: $snapshot_output"
        fi
    else
        log_info "Snapshot '$snapshot_name' created successfully."
    fi
}

# =====================================================================================
# Function: create_pre_configured_snapshot
# Description: Creates a standardized 'pre-configured' snapshot of a container. This
#              snapshot is typically taken after initial setup and configuration, but
#              before application-specific scripts are run. It serves as a stable
#              restore point. The function will delete and recreate the snapshot if it
#              already exists to ensure it reflects the latest configuration.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. Exits with a fatal error if snapshot creation or deletion fails.
# =====================================================================================
create_pre_configured_snapshot() {
    local CTID="$1"
    local snapshot_name="pre-configured"
    log_info "Checking for pre-configured snapshot for CTID: $CTID"
    local is_template
    is_template=$(jq -r ".lxc_configs[\"$CTID\"].is_template // false" "$LXC_CONFIG_FILE")
    if [ "$is_template" == "true" ]; then
        log_info "Container $CTID is a template, skipping all snapshot creation."
        return 0
    fi

    if pct listsnapshot "$CTID" | grep -q "$snapshot_name"; then
        log_info "Snapshot '$snapshot_name' already exists for CTID $CTID. Deleting and recreating."
        if ! run_pct_command delsnapshot "$CTID" "$snapshot_name"; then
            log_fatal "Failed to delete existing snapshot '$snapshot_name' for CTID $CTID."
        fi
    fi

    log_info "Creating snapshot '$snapshot_name' for container $CTID..."
    local snapshot_output
    if ! snapshot_output=$(run_pct_command snapshot "$CTID" "$snapshot_name" 2>&1); then
        if [[ "$snapshot_output" == *"snapshot feature is not available"* ]]; then
            log_warn "[WARNING] Snapshot feature is not available for CTID $CTID. Skipping snapshot creation."
        else
            log_fatal "Failed to create snapshot '$snapshot_name' for CTID $CTID. Error: $snapshot_output"
        fi
    else
        log_info "Snapshot '$snapshot_name' created successfully."
    fi
}

# =====================================================================================
# Function: create_final_form_snapshot
# Description: Creates a standardized 'final-form' snapshot of a container. This snapshot
#              is taken after all provisioning steps, including application scripts and
#              health checks, are complete. It represents the fully provisioned and
#              validated state of the container. The function will delete and recreate
#              the snapshot if it already exists.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. Exits with a fatal error if snapshot creation or deletion fails.
# =====================================================================================
create_final_form_snapshot() {
    local CTID="$1"
    local snapshot_name="final-form"
    log_info "Checking for final-form snapshot for CTID: $CTID"
    local is_template
    is_template=$(jq -r ".lxc_configs[\"$CTID\"].is_template // false" "$LXC_CONFIG_FILE")
    if [ "$is_template" == "true" ]; then
        log_info "Container $CTID is a template, skipping all snapshot creation."
        return 0
    fi

    if pct listsnapshot "$CTID" | grep -q "$snapshot_name"; then
        log_info "Snapshot '$snapshot_name' already exists for CTID $CTID. Deleting and recreating."
        if ! run_pct_command delsnapshot "$CTID" "$snapshot_name"; then
            log_fatal "Failed to delete existing snapshot '$snapshot_name' for CTID $CTID."
        fi
    fi

    log_info "Creating snapshot '$snapshot_name' for container $CTID..."
    local snapshot_output
    if ! snapshot_output=$(run_pct_command snapshot "$CTID" "$snapshot_name" 2>&1); then
        if [[ "$snapshot_output" == *"snapshot feature is not available"* ]]; then
            log_warn "[WARNING] Snapshot feature is not available for CTID $CTID. Skipping snapshot creation."
        else
            log_fatal "Failed to create snapshot '$snapshot_name' for CTID $CTID. Error: $snapshot_output"
        fi
    else
        log_info "Snapshot '$snapshot_name' created successfully."
    fi
}

# =====================================================================================
# Function: apply_apparmor_profile
# Description: Applies the specified AppArmor profile to the container's configuration file.
#              This is a critical security function that ensures containers are properly
#              sandboxed. It handles both custom profiles and the 'unconfined' state.
#
# Arguments:
#   $1 - The CTID of the container.
#
# Returns:
#   None. The function will exit with a fatal error if the configuration file is not found
#   or if the AppArmor profile cannot be applied.
# =====================================================================================
apply_apparmor_profile() {
    local CTID="$1"
    log_info "Applying AppArmor profile for CTID: $CTID"

    local apparmor_profile
    apparmor_profile=$(jq_get_value "$CTID" ".apparmor_profile" || echo "unconfined")
    local conf_file="/etc/pve/lxc/${CTID}.conf"

    if [ ! -f "$conf_file" ]; then
        log_fatal "Container configuration file not found at $conf_file."
    fi

    log_info "Setting AppArmor profile to: ${apparmor_profile}"
    if [ "$apparmor_profile" == "unconfined" ]; then
        if grep -q "^lxc.apparmor.profile:" "$conf_file"; then
            log_info "Removing existing AppArmor profile setting."
            sed -i '/^lxc.apparmor.profile:/d' "$conf_file"
        fi
    else
        # Load the AppArmor profile
        local custom_profile_path="${PHOENIX_BASE_DIR}/etc/apparmor/${apparmor_profile}"
        local system_profile_path="/etc/apparmor.d/${apparmor_profile}"

        if [ ! -f "$custom_profile_path" ]; then
            log_fatal "Custom AppArmor profile file not found at $custom_profile_path"
        fi

        log_info "Copying custom AppArmor profile to $system_profile_path"
        if ! cp "$custom_profile_path" "$system_profile_path"; then
            log_fatal "Failed to copy AppArmor profile to system directory."
        fi

        local profile_line="lxc.apparmor.profile: ${apparmor_profile}"
        if grep -q "^lxc.apparmor.profile:" "$conf_file"; then
            sed -i "s|^lxc.apparmor.profile:.*|$profile_line|" "$conf_file"
        else
            echo "$profile_line" >> "$conf_file"
        fi

        # Add nesting support if specified
        local apparmor_manages_nesting
        apparmor_manages_nesting=$(jq_get_value "$CTID" ".apparmor_manages_nesting" || echo "false")
        if [ "$apparmor_manages_nesting" = true ]; then
            log_info "Adding nesting support for CTID $CTID"
            echo "lxc.apparmor.allow_nesting: 1" >> "$conf_file" || log_fatal "Failed to add nesting support"
            echo "lxc.include: /usr/share/lxc/config/nesting.conf" >> "$conf_file" || log_fatal "Failed to add nesting config"
        fi
    fi

    # Reload AppArmor profiles to apply changes
    log_info "Reloading AppArmor profiles..."
    systemctl reload apparmor || log_warn "Failed to reload AppArmor profiles."
}

# =====================================================================================
# Function: sync_lxc_configurations
# Description: Syncs configurations for a specific LXC container.
# =====================================================================================
sync_lxc_configurations() {
    local CTID="$1"
    log_info "Starting 'sync' workflow for CTID $CTID..."

    if [ "$CTID" -eq 102 ]; then
        log_info "Running Traefik certificate sync for CTID 102..."
        local sync_script_path="${PHOENIX_BASE_DIR}/bin/lxc_setup/phoenix_hypervisor_feature_sync_traefik_certs.sh"
        if [ ! -f "$sync_script_path" ]; then
            log_fatal "Traefik sync script not found at $sync_script_path."
        fi
        if ! "$sync_script_path" "$CTID"; then
            log_fatal "Traefik certificate sync failed for CTID $CTID."
        fi
    fi

    log_info "'sync' workflow completed for CTID $CTID."
}
# =====================================================================================
# Function: create_lxc_templates
# Description: Idempotently creates LXC templates based on the `lxc_templates` object
#              in the configuration file.
# =====================================================================================
create_lxc_templates() {
    log_info "Starting LXC template creation process..."
    local templates
    templates=$(jq -c '.lxc_templates | to_entries[]' "$LXC_CONFIG_FILE")

    for template in $templates; do
        local template_name
        template_name=$(echo "$template" | jq -r '.key')
        local source_ctid
        source_ctid=$(echo "$template" | jq -r '.value.source_ctid')
        local mount_point_base
        mount_point_base=$(get_global_config_value ".mount_point_base")
        local iso_dataset_path
        iso_dataset_path=$(get_global_config_value ".zfs.datasets[] | select(.name == \"shared-iso\") | .pool + \"/\" + .name")
        local template_dir="${mount_point_base}/${iso_dataset_path}/template/vztmpl"
        mkdir -p "$template_dir"
        local template_path="${template_dir}/${template_name}"

        if [ -f "$template_path" ]; then
            log_info "Template '$template_name' already exists. Skipping."
            continue
        fi

        log_info "Creating template '$template_name' from source CTID '$source_ctid'..."
        create_container_for_templating "$source_ctid"

        log_info "Stopping container '$source_ctid' before creating template..."
        run_pct_command stop "$source_ctid" || log_fatal "Failed to stop container $source_ctid."

        log_info "Creating template..."
        vzdump "$source_ctid" --mode stop --compress gzip --stdout > "$template_path" || log_fatal "Failed to create template."
        
        log_info "Template '$template_name' created successfully."
    done
}

# =====================================================================================
# Function: create_lxc_template
# Description: Idempotently creates a single LXC template.
# =====================================================================================
create_lxc_template() {
    local template_name="$1"
    log_info "Starting LXC template creation for '$template_name'..."
    local source_ctid
    source_ctid=$(jq -r ".lxc_templates[\"$template_name\"].source_ctid" "$LXC_CONFIG_FILE")
    local mount_point_base
    mount_point_base=$(get_global_config_value ".mount_point_base")
    local iso_dataset_path
    iso_dataset_path=$(get_global_config_value ".zfs.datasets[] | select(.name == \"shared-iso\") | .pool + \"/\" + .name")
    local template_dir="${mount_point_base}/${iso_dataset_path}/template/vztmpl"
    mkdir -p "$template_dir"
    local template_path="${template_dir}/${template_name}"

    if [ -f "$template_path" ]; then
        log_info "Template '$template_name' already exists. Skipping."
        return 0
    fi

    log_info "Creating template '$template_name' from source CTID '$source_ctid'..."
    create_container_for_templating "$source_ctid"

    log_info "Stopping container '$source_ctid' before creating template..."
    run_pct_command stop "$source_ctid" || log_fatal "Failed to stop container $source_ctid."

    log_info "Creating template..."
    vzdump "$source_ctid" --mode stop --compress gzip --stdout > "$template_path" || log_fatal "Failed to create template."
    
    log_info "Template '$template_name' created successfully."
}

# =====================================================================================
# Function: create_container_from_os_template
# Description: Creates a new LXC container from a base OS template file.
# =====================================================================================
create_container_from_os_template() {
    local CTID="$1"
    log_info "Starting creation of container $CTID from OS template."

    # --- Retrieve all necessary parameters from the config file ---
    local hostname=$(jq_get_value "$CTID" ".name")
    local memory_mb=$(jq_get_value "$CTID" ".memory_mb")
    local cores=$(jq_get_value "$CTID" ".cores")
    local template=$(jq_get_value "$CTID" ".template")
    local storage_pool=$(jq_get_value "$CTID" ".storage_pool")
    local storage_size_gb=$(jq_get_value "$CTID" ".storage_size_gb")

    # --- Check for storage pool existence ---
    check_storage_pool_exists "$storage_pool"
    local features=$(jq_get_value "$CTID" ".features | join(\",\")" || echo "") # Features are handled separately
    local mac_address=$(jq_get_value "$CTID" ".mac_address")
    local unprivileged_bool=$(jq_get_value "$CTID" ".unprivileged")
    local unprivileged_val=$([ "$unprivileged_bool" == "true" ] && echo "1" || echo "0") # Convert boolean to 0 or 1

    # --- Check for template existence and download if necessary ---
    local mount_point_base=$(get_global_config_value ".mount_point_base")
    local iso_dataset_path=$(get_global_config_value ".zfs.datasets[] | select(.name == \"shared-iso\") | .pool + \"/\" + .name")
    local template_path="${mount_point_base}/${iso_dataset_path}/template/cache/$(basename "$template")"

    if [ ! -f "$template_path" ]; then
        log_info "Template file not found at $template_path. Attempting to download..."
        local template_filename=$(basename "$template")
        local template_name="$template_filename"
        
         # Determine the storage ID for ISOs from the configuration file
         local storage_id
         storage_id=$(get_global_config_value ".proxmox_storage_ids.fastData_shared_iso")
         if [ -z "$storage_id" ] || [ "$storage_id" == "null" ]; then
            log_fatal "Could not determine ISO storage ID from configuration file."
         fi

        log_info "Downloading template '$template_name' to storage '$storage_id'..."
        if ! pveam download "$storage_id" "$template_name"; then
            log_fatal "Failed to download template '$template_name'."
        fi
        log_info "Template downloaded successfully."
    fi

    # --- Construct network configuration string ---
    local net0_name=$(jq_get_value "$CTID" ".network_config.name")
    local net0_bridge=$(jq_get_value "$CTID" ".network_config.bridge")
    local net0_ip=$(jq_get_value "$CTID" ".network_config.ip")
    local net0_gw=$(jq_get_value "$CTID" ".network_config.gw")
    local mac_address=$(jq_get_value "$CTID" ".mac_address")
    local net0_string="name=${net0_name},bridge=${net0_bridge},ip=${net0_ip},gw=${net0_gw},hwaddr=${mac_address}" # Assemble network string
    local firewall_enabled=$(jq_get_value "$CTID" ".firewall.enabled" || echo "false")
    if [ "$firewall_enabled" == "true" ]; then
        log_info "Firewall is enabled for CTID $CTID. Applying firewall=1 to net0 during creation."
        net0_string+=",firewall=1"
    fi
    local nameservers=$(jq_get_value "$CTID" ".network_config.nameservers" || echo "")
 
     # --- Build the pct create command array ---
    local pct_create_cmd=(
        create "$CTID" "$template"
        --hostname "$hostname"
        --memory "$memory_mb"
        --cores "$cores"
        --storage "$storage_pool"
        --rootfs "${storage_pool}:${storage_size_gb}"
        --net0 "$net0_string"
        --unprivileged "$unprivileged_val"
    )

    if [ -n "$nameservers" ]; then
        pct_create_cmd+=(--nameserver "$nameservers")
    fi

    # --- Execute the command ---
    if ! run_pct_command "${pct_create_cmd[@]}"; then
        log_fatal "'pct create' command failed for CTID $CTID."
    fi
    log_info "Container $CTID created from OS template successfully."
}

# =====================================================================================
# Function: create_container_for_templating
# Description: Creates a container from a base OS image for the purpose of templating.
# =====================================================================================
create_container_for_templating() {
    local CTID="$1"
    log_info "Starting creation of container $CTID for templating..."

    if pct status "$CTID" > /dev/null 2>&1; then
        log_info "Container $CTID already exists. Skipping creation."
        return 0
    fi

    local os_template=$(jq_get_value "$CTID" ".template" || echo "")
    if [ -z "$os_template" ]; then
        log_fatal "Container $CTID has no OS template defined."
    fi

    create_container_from_os_template "$CTID"
    apply_lxc_configurations "$CTID"
    apply_zfs_volumes "$CTID"
    apply_secure_permissions "$CTID"
    apply_dedicated_volumes "$CTID"
    ensure_container_disk_size "$CTID"
    apply_mount_points "$CTID"
    apply_host_path_permissions "$CTID"
    start_container "$CTID"
    apply_features "$CTID"
    run_application_script "$CTID"
}

# =====================================================================================
# Function: main_lxc_orchestrator
# Description: The main entry point for the LXC manager script. It parses the
#              action and CTID, and then executes the appropriate lifecycle
#              operations for the container.
#
# Arguments:
#   $1 - The action to perform (e.g., "create", "start", "stop").
#   $2 - The CTID of the target container.
# =====================================================================================
main_lxc_orchestrator() {
    local action="$1"
    local ctid="$2"

    case "$action" in
        create-templates)
            create_lxc_templates
            ;;
        create)
            validate_inputs "$ctid"
            log_info "Starting 'create' workflow for CTID $ctid..."

            # --- Pre-create persistent directories ---
            ensure_persistent_dirs_exist "$ctid"

            # --- Centralized Certificate Generation ---
            log_info "Ensuring all certificates are generated before container creation..."
            if ! "${PHOENIX_BASE_DIR}/bin/managers/certificate-renewal-manager.sh"; then
                log_fatal "Certificate generation failed. Aborting create workflow."
            fi
            log_success "Certificate warehouse is up to date."

            if ensure_container_defined "$ctid"; then
                run_pct_command stop "$ctid" || log_info "Container $ctid was not running. Proceeding with configuration."
                
                apply_lxc_configurations "$ctid"
                apply_zfs_volumes "$ctid"
                apply_secure_permissions "$ctid"
                apply_dedicated_volumes "$ctid"
                ensure_container_disk_size "$ctid"
                
                apply_mount_points "$ctid"
                apply_host_path_permissions "$ctid"
                start_container "$ctid"

                # --- PHOENIX-20 HOTFIX ---
                # Re-apply the declarative firewall rules after container creation.
                # This overwrites the default firewall config created by 'pct create'
                # and ensures the correct rules are in place before feature installation.
                log_info "Re-applying declarative firewall configuration to fix PHOENIX-20..."
                if ! "${PHOENIX_BASE_DIR}/bin/hypervisor_setup/hypervisor_feature_setup_firewall.sh"; then
                    log_fatal "Failed to re-apply firewall configuration. Halting."
                fi
                # --- END PHOENIX-20 HOTFIX ---

                if [ "$ctid" -eq 103 ]; then
                    log_info "Setting final permissions for shared SSL directory on host..."
                    local shared_ssl_dir="/mnt/pve/quickOS/lxc-persistent-data/103/ssl"
                    if ! chmod -R 777 "$shared_ssl_dir"; then
                        log_fatal "Failed to set permissions on shared SSL directory on host."
                    fi
                    log_success "Host-side password management and permissions set for CTID 103."
                fi

                local enable_lifecycle_snapshots
                enable_lifecycle_snapshots=$(jq_get_value "$ctid" ".enable_lifecycle_snapshots" || echo "false")

                if [ "$enable_lifecycle_snapshots" == "true" ]; then
                    create_pre_configured_snapshot "$ctid"
                fi

                apply_features "$ctid"
                
                run_application_script "$ctid"
                
                local dependents
                dependents=$(jq -r --arg ctid "$ctid" '.lxc_configs | to_entries[] | select(.value.dependencies[]? == ($ctid | tonumber)) | .key' "$LXC_CONFIG_FILE")
                if [ -n "$dependents" ]; then
                    for dependent_ctid in $dependents; do
                        log_info "Restarting dependent container $dependent_ctid to apply changes from $ctid..."
                        run_pct_command restart "$dependent_ctid" || log_warn "Failed to restart dependent container $dependent_ctid."
                    done
                fi
                
                run_health_check "$ctid"
                create_template_snapshot "$ctid"

                if [ "$enable_lifecycle_snapshots" == "true" ]; then
                    create_final_form_snapshot "$ctid"
                fi

                # Convert to template if specified
                local is_template
                is_template=$(jq -r ".lxc_configs[\"$ctid\"].is_template // false" "$LXC_CONFIG_FILE")
                if [ "$is_template" == "true" ]; then
                    log_info "Container $ctid is marked as a template. Stopping before conversion..."
                    run_pct_command stop "$ctid" || log_warn "Container $ctid may have already been stopped."

                    # Wait for container to be fully stopped
                    local max_wait=30
                    local wait_interval=2
                    local waited=0
                    while pct status "$ctid" 2>/dev/null | grep -q "status: running"; do
                        if [ "$waited" -ge "$max_wait" ]; then
                            log_fatal "Container $ctid did not stop within $max_wait seconds."
                        fi
                        sleep "$wait_interval"
                        waited=$((waited + wait_interval))
                        log_info "Waiting for container $ctid to stop... (${waited}s)"
                    done
                    
                    log_info "Container $ctid confirmed stopped. Converting to template..."
                    pct template "$ctid" || log_fatal "Failed to convert container $ctid to a template."
                fi

                log_info "'create' workflow completed for CTID $ctid."
            fi

            if [ "$ctid" -eq 101 ]; then
                log_info "Ensuring NGINX container (101) is correctly configured..."
                run_application_script "$ctid"
            fi
            ;;
        sync)
            validate_inputs "$ctid"
            sync_lxc_configurations "$ctid"
            ;;
        start)
            validate_inputs "$ctid"
            log_info "Starting 'start' workflow for CTID $ctid..."
            start_container "$ctid"
            log_info "'start' workflow completed for CTID $ctid."
            ;;
        stop)
            validate_inputs "$ctid"
            log_info "Starting 'stop' workflow for CTID $ctid..."
            run_pct_command stop "$ctid" || log_fatal "Failed to stop container $ctid."
            log_info "'stop' workflow completed for CTID $ctid."
            ;;
        restart)
            validate_inputs "$ctid"
            log_info "Starting 'restart' workflow for CTID $ctid..."
            run_pct_command stop "$ctid" || log_warn "Failed to stop container $ctid before restart."
            start_container "$ctid"
            log_info "'restart' workflow completed for CTID $ctid."
            ;;
        delete)
            validate_inputs "$ctid"
            log_info "Starting 'delete' workflow for CTID $ctid..."
            run_pct_command stop "$ctid" || log_warn "Container $ctid was not running before deletion."
            run_pct_command destroy "$ctid" || log_fatal "Failed to delete container $ctid."
            log_info "'delete' workflow completed for CTID $ctid."
            ;;
        *)
            log_error "Invalid action '$action' for lxc-manager."
            exit 1
            ;;
    esac
}

# =====================================================================================
# Function: ensure_persistent_dirs_exist
# Description: Parses the configuration for a given CTID and creates any host-side
#              directories required for its mount points before the container is created.
# =====================================================================================
ensure_persistent_dirs_exist() {
    local CTID="$1"
    log_info "Ensuring persistent directories exist for CTID: $CTID..."

    local mounts
    mounts=$(jq_get_array "$CTID" "(.mount_points // [])[]" || echo "")

    if [ -n "$mounts" ]; then
        for mount_config in $(echo "$mounts" | jq -c '.'); do
            local host_path=$(echo "$mount_config" | jq -r '.host_path')
            if [ -n "$host_path" ] && [ ! -d "$host_path" ]; then
                log_info "Creating host path directory for mount point: $host_path"
                mkdir -p "$host_path" || log_fatal "Failed to create host path directory '$host_path'."
            fi
        done
    else
        log_info "No host path mount points to create for CTID $CTID."
    fi
}

# If the script is executed directly, call the main orchestrator
if [[ "${BASH_SOURCE}" == "${0}" ]]; then
    main_lxc_orchestrator "$@"
fi