#!/bin/bash
#
# File: certificate-renewal-manager.sh
# Description: This script provides centralized, automated management for internal TLS certificates.
#              It reads a manifest file, checks the expiration of each certificate, renews
#              them if necessary using Step-CA, and executes post-renewal commands.
#
# Version: 1.0.0
# Author: Roo

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" > /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." > /dev/null && pwd)

# --- Source common utilities ---
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

# --- Configuration ---
CERT_MANIFEST_FILE="${PHOENIX_BASE_DIR}/etc/certificate-manifest.json"
RENEWAL_THRESHOLD_SECONDS=43200 # 12 hours
CERT_VALIDITY="24h" # 24 hours

# =====================================================================================
# Function: check_renewal_needed
# Description: Checks if a certificate needs to be renewed.
# Arguments:
#   $1 - Path to the certificate file.
# Returns:
#   0 if renewal is needed (file doesn't exist, is invalid, or expires soon).
#   1 if renewal is not needed.
# =====================================================================================
check_renewal_needed() {
    local cert_path="$1"
    shift
    local required_sans=("$@")

    if [ ! -f "$cert_path" ]; then
        log_info "Certificate not found at '${cert_path}'. Renewal is required."
        return 0
    fi

    if ! openssl x509 -in "$cert_path" -checkend "$RENEWAL_THRESHOLD_SECONDS" > /dev/null 2>&1; then
        log_info "Certificate at '${cert_path}' is expiring within the threshold. Renewal is required."
        return 0
    fi

    # Check SANs if required SANs are provided
    # If the manifest specifies no SANs, we don't enforce a match.
    # An empty required_sans array after cleaning up will have a length of 1
    # because of how readarray works with empty results.
    if [ ${#required_sans[@]} -gt 1 ] || [ -n "${required_sans[0]}" ]; then
        local existing_sans
        existing_sans=$(openssl x509 -in "$cert_path" -noout -text | grep "DNS:" | sed 's/DNS://g' | tr -d ' ' | tr ',' '\n' | sort)
        local required_sans_sorted
        required_sans_sorted=$(printf "%s\n" "${required_sans[@]}" | sort)

        if [ "$existing_sans" != "$required_sans_sorted" ]; then
            log_info "Certificate SANs do not match manifest. Renewal is required."
            log_debug "Existing SANs: $existing_sans"
            log_debug "Required SANs: $required_sans_sorted"
            return 0
        fi
    fi

    log_info "Certificate at '${cert_path}' is valid and does not need renewal."
    return 1
}

# =====================================================================================
# Function: renew_certificate
# Description: Renews a single TLS certificate using Step-CA.
# Arguments:
#   $1 - Common Name for the certificate.
#   $2 - Path to store the new certificate.
#   $3 - Path to store the new private key.
#   $4 - Owner for the new files (e.g., "user:group").
#   $5 - Permissions for the new files (e.g., "644").
# Returns:
#   0 on success, 1 on failure.
# =====================================================================================
renew_certificate() {
    local common_name="$1"
    local cert_path="$2"
    local key_path="$3"
    local owner="$4"
    local permissions="$5"
    local cert_type="$6"
    shift 6
    local sans=("$@")

    log_info "Attempting to renew certificate for '${common_name}' (Type: ${cert_type})..."

    # Ensure the target directory exists
    if ! mkdir -p "$(dirname "$cert_path")"; then
        log_error "Failed to create directory $(dirname "$cert_path")"
        return 1
    fi

    local provisioner_password_file="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/provisioner_password.txt"
    if [ ! -f "$provisioner_password_file" ]; then
        log_error "Provisioner password file not found at: $provisioner_password_file"
        return 1
    fi

    local step_command=(
        step ca certificate
        "$common_name"
        "$cert_path"
        "$key_path"
        --provisioner "admin@thinkheads.ai"
        --provisioner-password-file "$provisioner_password_file"
        --not-after "$CERT_VALIDITY"
        --force
    )

    # If the sans array is empty or contains only an empty string, do not add any --san flags.
    # The common name is automatically included as a SAN by Step-CA.
    if [ ${#sans[@]} -gt 0 ] && [ -n "${sans[0]}" ]; then
        for san in "${sans[@]}"; do
            if [ -n "$san" ]; then
                step_command+=(--san "$san")
            fi
        done
    fi

    # The --profile flag is not a valid flag for `step ca certificate` in the installed version.
    # The cert_type is handled by other logic if needed, but this flag is incorrect.
    # if [ "$cert_type" == "client" ]; then
    #     step_command+=(--profile "tls-client")
    # fi

    if ! "${step_command[@]}"; then
        log_error "Failed to generate new certificate for '${common_name}'."
        return 1
    fi

    # Set directory permissions first
    local cert_dir
    cert_dir=$(dirname "$cert_path")
    if [ "$common_name" == "nginx.internal.thinkheads.ai" ]; then
        log_info "Setting special directory permissions for Nginx..."
        chmod 755 "$cert_dir" || log_warn "Failed to set directory permissions for Nginx."
    fi

    chown "$owner" "$cert_path" "$key_path" || log_warn "Failed to set ownership for new certificate files."
    
    # Special handling for Nginx key permissions
    if [ "$common_name" == "nginx.internal.thinkheads.ai" ]; then
        chmod 644 "$key_path" || log_warn "Failed to set permissions for Nginx private key."
        chmod 644 "$cert_path" || log_warn "Failed to set permissions for Nginx public cert."
    else
        chmod "$permissions" "$cert_path" "$key_path" || log_warn "Failed to set permissions for new certificate files."
    fi

    log_success "Successfully renewed certificate for '${common_name}'."
    return 0
}

# =====================================================================================
# Function: push_certificate_to_guest
# Description: Pushes a certificate and key to a guest (VM or LXC).
# =====================================================================================
push_certificate_to_guest() {
    local guest_id="$1"
    local guest_type="$2"
    local common_name="$3"
    local source_cert_path="$4"
    local source_key_path="$5"
    local dest_cert_name="cert.pem"
    local dest_key_name="key.pem"

    log_info "Pushing certificate for '${common_name}' to ${guest_type} ${guest_id}..."

    case "$guest_type" in
        vm)
            local cert_content=$(cat "$source_cert_path")
            local key_content=$(cat "$source_key_path")
            qm guest exec "$guest_id" -- /bin/bash -c "echo '${cert_content}' > /tmp/${dest_cert_name}" || log_fatal "Failed to write cert to VM ${guest_id}"
            qm guest exec "$guest_id" -- /bin/bash -c "echo '${key_content}' > /tmp/${dest_key_name}" || log_fatal "Failed to write key to VM ${guest_id}"
            ;;
        lxc)
            pct push "$guest_id" "$source_cert_path" "/tmp/${dest_cert_name}" || log_fatal "Failed to push cert to LXC ${guest_id}"
            pct push "$guest_id" "$source_key_path" "/tmp/${dest_key_name}" || log_fatal "Failed to push key to LXC ${guest_id}"
            ;;
        *)
            log_error "Unknown guest type: ${guest_type}"
            return 1
            ;;
    esac
    log_success "Successfully pushed certificate and key to ${guest_type} ${guest_id}."
}

# =====================================================================================
# Function: execute_post_renewal_command
# Description: Executes the post-renewal command, intelligently handling the JSON
#              output from `qm guest exec` to determine the true success or failure
#              of the command inside the guest.
# Arguments:
#   $1 - The command string to execute.
#   $2 - The common name of the certificate (for logging).
# Returns:
#   0 on success, 1 on failure.
# =====================================================================================
execute_post_renewal_command() {
    local command_string="$1"
    local common_name="$2"
    local output
    local host_exit_code=0

    log_info "Executing post-renewal command for '${common_name}'..."

    # Check if the command is a `qm guest exec` command
    if [[ "$command_string" == "qm guest exec"* ]]; then
        output=$(eval "$command_string" 2>&1)
        host_exit_code=$?

        # A non-zero host exit code is a definite failure of the qm command itself.
        if [ "$host_exit_code" -ne 0 ]; then
            log_error "The 'qm guest exec' command itself failed with exit code ${host_exit_code}."
            log_error "Output: ${output}"
            return 1
        fi

        # If the command produced valid JSON, parse it for the guest's exit code.
        if echo "$output" | jq -e . > /dev/null 2>&1; then
            local guest_exitcode=$(echo "$output" | jq -r '.exitcode // 0')
            local err_data=$(echo "$output" | jq -r '."err-data" // ""')

            if [ "$guest_exitcode" -ne 0 ]; then
                log_error "Post-renewal command inside guest for '${common_name}' failed with exit code ${guest_exitcode}."
                if [ -n "$err_data" ]; then
                    log_error "Guest stderr: ${err_data}"
                fi
                return 1
            fi
            
            # Log stderr as a warning even if the command succeeds.
            if [ -n "$err_data" ]; then
                log_warn "Post-renewal command for '${common_name}' produced stderr, but exited successfully: ${err_data}"
            fi
        else
            # If output is not JSON, we can only trust the host exit code.
            log_warn "Command for '${common_name}' did not produce JSON. Assuming success based on host exit code."
            log_debug "Output: ${output}"
        fi
    else
        # For other commands (like pct exec), a simple eval is sufficient.
        if ! eval "$command_string"; then
            log_error "Post-renewal command failed for '${common_name}'."
            return 1
        fi
    fi

    log_success "Post-renewal command executed successfully for '${common_name}'."
    return 0
}

# =====================================================================================
# Function: main
# Description: Main entry point for the script.
# =====================================================================================
main() {
    local force_renewal=false
    local generate_only=false
    for arg in "$@"; do
        case "$arg" in
            --force)
                force_renewal=true
                log_info "Forcing renewal of all certificates."
                ;;
            --generate-only)
                generate_only=true
                log_info "Generate-only mode enabled. Post-renewal commands will be skipped."
                ;;
        esac
    done

    log_info "--- Starting Certificate Renewal Manager ---"

    local step_ca_ctid="103"
    if ! pct status "$step_ca_ctid" > /dev/null 2>&1; then
        log_warn "Step CA container (${step_ca_ctid}) is not running. Skipping certificate renewal."
        log_info "--- Certificate Renewal Manager Finished (Skipped) ---"
        exit 0
    fi

    source "${PHOENIX_BASE_DIR}/bin/hypervisor_setup/hypervisor_feature_bootstrap_step_cli.sh"

    if [ ! -f "$CERT_MANIFEST_FILE" ]; then
        log_fatal "Certificate manifest file not found at: ${CERT_MANIFEST_FILE}"
    fi

    local renewal_failed=false
    jq -c '.[]' "$CERT_MANIFEST_FILE" | while read -r cert_config; do
        local common_name=$(echo "$cert_config" | jq -r '.common_name')
        local guest_id=$(echo "$cert_config" | jq -r '.guest_id')
        local guest_type=$(echo "$cert_config" | jq -r '.guest_type')
        local cert_path=$(echo "$cert_config" | jq -r '.cert_path')
        local key_path=$(echo "$cert_config" | jq -r '.key_path')
        local post_renewal_command=$(echo "$cert_config" | jq -r '.post_renewal_command')
        local include_ca=$(echo "$cert_config" | jq -r '.include_ca // false')
        local sans_array
        readarray -t sans_array < <(echo "$cert_config" | jq -r '.sans[]? // ""')
        local cert_type=$(echo "$cert_config" | jq -r '.cert_type // "server"')

        log_info "Processing certificate for: ${common_name}"

        if [ "$force_renewal" = true ] || check_renewal_needed "$cert_path" "${sans_array[@]}"; then
            if ! renew_certificate "$common_name" "$cert_path" "$key_path" "root:root" "640" "$cert_type" "${sans_array[@]}"; then
                log_warn "Failed to renew certificate for '${common_name}'. Skipping post-renewal steps."
                renewal_failed=true
                continue
            fi

            if [ "$generate_only" = false ]; then
                local guest_running=false
                if [ "$guest_type" == "vm" ] && qm status "$guest_id" > /dev/null 2>&1; then
                    guest_running=true
                elif [ "$guest_type" == "lxc" ] && pct status "$guest_id" > /dev/null 2>&1; then
                    guest_running=true
                fi

                if [ "$guest_running" = true ]; then
                    push_certificate_to_guest "$guest_id" "$guest_type" "$common_name" "$cert_path" "$key_path"
                    
                    if [ "$include_ca" = true ]; then
                        log_info "Pushing root CA for ${common_name} as requested by manifest..."
                        local root_ca_path="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt"
                        if [ -f "$root_ca_path" ]; then
                            local ca_content=$(cat "$root_ca_path")
                            case "$guest_type" in
                                vm) qm guest exec "$guest_id" -- /bin/bash -c "echo '${ca_content}' > /tmp/ca.pem" || log_warn "Failed to write CA to VM" ;;
                                lxc) pct push "$guest_id" "$root_ca_path" "/tmp/ca.pem" || log_warn "Failed to push CA to LXC" ;;
                            esac
                        else
                            log_warn "Root CA certificate not found at ${root_ca_path}. Skipping push."
                        fi
                    fi

                    if ! execute_post_renewal_command "$post_renewal_command" "$common_name"; then
                        renewal_failed=true
                        # The function handles its own detailed error logging.
                    fi
                else
                    log_warn "Guest ${guest_id} is not running. Skipping certificate push and post-renewal command for '${common_name}'."
                fi
            else
                log_info "Skipping certificate push and post-renewal command due to --generate-only flag."
            fi
        fi
        echo
    done

    if [ "$renewal_failed" = true ]; then
        log_fatal "One or more certificates failed to renew. Please check the logs above for details."
    fi

    log_info "--- Certificate Renewal Manager Finished ---"
}

# --- Script execution ---
main "$@"