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
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/.." > /dev/null && pwd)

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

    if [ ! -f "$cert_path" ]; then
        log_info "Certificate not found at '${cert_path}'. Renewal is required."
        return 0
    fi

    if ! openssl x509 -in "$cert_path" -checkend "$RENEWAL_THRESHOLD_SECONDS" > /dev/null 2>&1; then
        log_info "Certificate at '${cert_path}' is expiring within the threshold. Renewal is required."
        return 0
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

    log_info "Attempting to renew certificate for '${common_name}'..."

    # Ensure the target directory exists
    mkdir -p "$(dirname "$cert_path")" || { log_error "Failed to create directory $(dirname "$cert_path")"; return 1; }

    local provisioner_password_file="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/provisioner_password.txt"
    if [ ! -f "$provisioner_password_file" ]; then
        log_error "Provisioner password file not found at: $provisioner_password_file"
        return 1
    fi

    local step_command="step ca certificate \"${common_name}\" \"${cert_path}\" \"${key_path}\" \
        --provisioner admin@thinkheads.ai \
        --provisioner-password-file \"${provisioner_password_file}\" \
        --not-after ${CERT_VALIDITY} --force"

    if ! eval "$step_command"; then
        log_error "Failed to generate new certificate for '${common_name}'."
        return 1
    fi

    chown "$owner" "$cert_path" "$key_path" || log_warn "Failed to set ownership for new certificate files."
    chmod "$permissions" "$cert_path" "$key_path" || log_warn "Failed to set permissions for new certificate files."

    log_success "Successfully renewed certificate for '${common_name}'."
    return 0
}

# =====================================================================================
# Function: main
# Description: Main entry point for the script.
# =====================================================================================
main() {
    log_info "--- Starting Certificate Renewal Manager ---"

    # Ensure the Step CLI is bootstrapped before trying to use it
    source "${PHOENIX_BASE_DIR}/bin/hypervisor_setup/hypervisor_feature_bootstrap_step_cli.sh"

    if [ ! -f "$CERT_MANIFEST_FILE" ]; then
        log_fatal "Certificate manifest file not found at: ${CERT_MANIFEST_FILE}"
    fi

    jq -c '.[]' "$CERT_MANIFEST_FILE" | while read -r cert_config; do
        local common_name=$(echo "$cert_config" | jq -r '.common_name')
        local cert_path=$(echo "$cert_config" | jq -r '.cert_path')
        local key_path=$(echo "$cert_config" | jq -r '.key_path')
        local owner=$(echo "$cert_config" | jq -r '.owner')
        local permissions=$(echo "$cert_config" | jq -r '.permissions')
        local post_renewal_command=$(echo "$cert_config" | jq -r '.post_renewal_command')

        log_info "Processing certificate for: ${common_name}"

        if check_renewal_needed "$cert_path"; then
            if renew_certificate "$common_name" "$cert_path" "$key_path" "$owner" "$permissions"; then
                log_info "Executing post-renewal command: ${post_renewal_command}"
                if ! eval "$post_renewal_command"; then
                    log_error "Post-renewal command failed for '${common_name}'."
                else
                    log_success "Post-renewal command executed successfully."
                fi
            fi
        fi
        echo # Add a newline for cleaner log output
    done

    log_info "--- Certificate Renewal Manager Finished ---"
}

# --- Script execution ---
main