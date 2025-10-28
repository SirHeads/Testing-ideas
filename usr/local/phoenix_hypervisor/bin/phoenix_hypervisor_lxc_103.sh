#!/bin/bash
#
# File: phoenix_hypervisor_lxc_103.sh
# Description: This script configures and starts the Smallstep CA service within LXC 103.
#              It initializes the CA, adds an ACME provisioner, and sets up a systemd service.
#
# Arguments:
#   $1 - The CTID of the container (expected to be 103).
#
# Dependencies:
#   - phoenix_hypervisor_common_utils.sh: For logging and utility functions.
#   - step-cli and step-ca binaries (installed by feature_install_step_ca.sh).
#
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- SCRIPT INITIALIZATION ---
exec &> /etc/step-ca/ssl/phoenix_hypervisor_lxc_103.log
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)

source "/tmp/phoenix_run/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID="$1"
CA_NAME="ThinkHeads Internal CA"
CA_DNS="ca.internal.thinkheads.ai" # Reverted to intended external DNS name
CA_ADDRESS=":9000" # Changed to a non-privileged port to avoid conflict with Nginx
CA_PROVISIONER_EMAIL="admin@thinkheads.ai"
CA_CONFIG_DIR="/root/.step/config"
CA_CONFIG_FILE="${CA_CONFIG_DIR}/ca.json"
CA_SERVICE_FILE="/etc/systemd/system/step-ca.service"
CA_PASSWORD_FILE="/etc/step-ca/ssl/ca_password.txt" # Path to the mounted password file
# CA_INIT_PASSWORD=$(openssl rand -base64 32) # Removed: Password is now managed on the host
CA_PROVISIONER_PASSWORD_FILE="/etc/step-ca/ssl/provisioner_password.txt"

# =====================================================================================
# Function: initialize_step_ca
# Description: Initializes the Smallstep CA.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if initialization fails.
# =====================================================================================
initialize_step_ca() {
    log_info "Initializing Smallstep CA..."

    # Check if CA is already initialized
    if test -f "$CA_CONFIG_FILE"; then
        log_info "Smallstep CA already initialized. Skipping."
        return 0
    fi
 
    # Initialize the CA with a password from the mounted file
    log_info "Initializing Smallstep CA using the mounted password file: $CA_PASSWORD_FILE..."
    
    # Verify the password file exists and its permissions
    log_debug "Checking for existence of CA password file inside container: $CA_PASSWORD_FILE"
    if [ ! -f "$CA_PASSWORD_FILE" ]; then
        log_fatal "CA password file not found at $CA_PASSWORD_FILE inside container. Cannot initialize CA."
    fi
    log_debug "CA password file found at $CA_PASSWORD_FILE inside container."

    log_debug "Permissions for password files are now managed on the host. Skipping in-container check."

    # Add a check for the provisioner password file
    log_debug "Checking for existence of provisioner password file inside container: $CA_PROVISIONER_PASSWORD_FILE"
    if [ ! -f "$CA_PROVISIONER_PASSWORD_FILE" ]; then
        log_fatal "Provisioner password file not found at $CA_PROVISIONER_PASSWORD_FILE inside container. Cannot initialize CA."
    fi
    log_debug "Provisioner password file found at $CA_PROVISIONER_PASSWORD_FILE inside container."

    if ! /usr/bin/step ca init --name "$CA_NAME" --dns "$CA_DNS" --dns "phoenix.thinkheads.ai" --dns "*.phoenix.thinkheads.ai" --dns "*.internal.thinkheads.ai" --address "$CA_ADDRESS" --provisioner "$CA_PROVISIONER_EMAIL" --deployment-type standalone --password-file "$CA_PASSWORD_FILE" --provisioner-password-file "$CA_PROVISIONER_PASSWORD_FILE"; then
        log_fatal "Failed to initialize Smallstep CA in container $CTID."
    fi
    log_success "Smallstep CA initialized successfully."
 
    # Add ca.internal.thinkheads.ai to /etc/hosts for internal resolution
    log_info "Adding '127.0.0.1 ca.internal.thinkheads.ai' to /etc/hosts..."
    if ! grep -q "ca.internal.thinkheads.ai" /etc/hosts; then
        echo "127.0.0.1 ca.internal.thinkheads.ai" >> /etc/hosts || log_fatal "Failed to add entry to /etc/hosts."
    fi
    log_success "Entry added to /etc/hosts successfully."


   log_info "Dumping content of $CA_CONFIG_FILE after initialization for debugging:"
   cat "$CA_CONFIG_FILE" || log_warn "Could not read $CA_CONFIG_FILE"
   log_info "End of $CA_CONFIG_FILE dump."
}

# =====================================================================================
# Function: add_acme_provisioner
# Description: Adds an ACME provisioner to the Smallstep CA.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if adding provisioner fails.
# =====================================================================================
add_acme_provisioner() {
    log_info "Adding ACME provisioner to Smallstep CA..."

    # Check if ACME provisioner already exists
    local provisioner_list_output
    provisioner_list_output=$(/usr/bin/step ca provisioner list --ca-url "https://$CA_DNS$CA_ADDRESS" --root /root/.step/certs/root_ca.crt 2>&1)
    if [ $? -ne 0 ]; then
        log_warn "step ca provisioner list failed or returned empty output. Assuming no ACME provisioner exists. Output: $provisioner_list_output"
        provisioner_list_output="[]" # Ensure the variable is a valid empty JSON array
    fi

    if echo "$provisioner_list_output" | jq -e '.[] | select(.type == "ACME")' > /dev/null; then
        log_info "ACME provisioner already exists. Skipping."
        return 0
    fi

    log_info "Attempting to add ACME provisioner with http-01 challenge enabled..."
    local add_provisioner_output
    log_info "Attempting to add ACME provisioner with http-01 and tls-alpn-01 challenges enabled..."
    if ! add_provisioner_output=$(/bin/bash -c "STEPDEBUG=1 /usr/bin/step ca provisioner add acme --type ACME --challenge http-01 --challenge tls-alpn-01 --ca-url https://$CA_DNS$CA_ADDRESS --root /root/.step/certs/root_ca.crt" 2>&1); then
        log_fatal "Failed to add ACME provisioner to Smallstep CA in container $CTID. Output: $add_provisioner_output"
    fi
    log_success "ACME provisioner added successfully. Output: $add_provisioner_output"

    log_info "Restarting step-ca service to apply provisioner changes..."
    if ! systemctl restart step-ca; then
        log_fatal "Failed to restart step-ca service."
    fi
    log_success "step-ca service restarted successfully."
}

# =====================================================================================
# Function: configure_acme_provisioner_claims
# Description: Configures the ACME provisioner to allow specific domain wildcards.
#              This is a critical security and functionality step to ensure that
#              the ACME provisioner can issue certificates for the intended domains.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if configuration fails.
# =====================================================================================
configure_acme_provisioner_claims() {
    log_info "Configuring ACME provisioner claims in $CA_CONFIG_FILE..."

    # Use jq to add the 'sans' claim to the ACME provisioner.
    # This is idempotent; running it multiple times won't create duplicate entries.
    local jq_filter='(.authority.provisioners[] | select(.name == "acme").claims.x509.sans) |= [
        "*.phoenix.thinkheads.ai",
        "*.internal.thinkheads.ai"
    ]'

    if ! jq "$jq_filter" "$CA_CONFIG_FILE" > "${CA_CONFIG_FILE}.tmp"; then
        log_fatal "jq command failed to update ACME provisioner claims."
    fi

    # Replace the original file with the modified one
    mv "${CA_CONFIG_FILE}.tmp" "$CA_CONFIG_FILE"
    log_success "Successfully added 'sans' claim to ACME provisioner."

    log_info "Restarting step-ca service to apply the new claims..."
    if ! systemctl restart step-ca; then
        log_fatal "Failed to restart step-ca service after updating claims."
    fi
    log_success "step-ca service restarted successfully."
}
 
 # =====================================================================================
 # Function: verify_ca_status
# Description: Verifies the status of the Step CA service and its ACME provisioner.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if verification fails.
# =====================================================================================
verify_ca_status() {
    log_info "Verifying Step CA service status..."
    if ! systemctl is-active --quiet step-ca; then
        log_fatal "Step CA service is not running."
    fi
    log_info "Step CA service is running."

    log_info "Verifying Step CA is listening on ${CA_ADDRESS} with retries..."
    local retries=10
    local delay=2
    local attempt=1
    while [ "$attempt" -le "$retries" ]; do
        local ss_output
        ss_output=$(ss -tuln 2>&1)
        if echo "$ss_output" | awk '($5 ~ /:9000$/)' | grep -q LISTEN; then
            log_info "Step CA is now listening on ${CA_ADDRESS}."
            break # Exit loop on success
        fi
        log_warn "Attempt $attempt/$retries: Step CA is not yet listening on ${CA_ADDRESS}. Retrying in $delay seconds..."
        sleep "$delay"
        attempt=$((attempt + 1))
    done

    if [ "$attempt" -gt "$retries" ]; then
        local final_ss_output
        final_ss_output=$(ss -tuln 2>&1)
        log_debug "Final 'ss -tuln' output: $final_ss_output"
        log_fatal "Step CA failed to start listening on ${CA_ADDRESS} after $retries attempts."
    fi

    # Now that we know it's listening, proceed with the original ACME check
    log_info "Verifying ACME provisioner status with retries..."
    local acme_retries=5
    local acme_delay=5
    local acme_attempt=1
    while [ "$acme_attempt" -le "$acme_retries" ]; do
        local provisioner_list_output
        provisioner_list_output=$(/usr/bin/step ca provisioner list --ca-url "https://$CA_DNS$CA_ADDRESS" --root /root/.step/certs/root_ca.crt 2>&1)
        if echo "$provisioner_list_output" | jq -e '.[] | select(.type == "ACME")' > /dev/null; then
            log_info "ACME provisioner is active."
            return 0
        else
            log_warn "ACME provisioner not found or not active on attempt $acme_attempt/$acme_retries. Output: $provisioner_list_output"
            if [ "$acme_attempt" -lt "$acme_retries" ]; then
                log_info "Retrying in $acme_delay seconds..."
                sleep "$acme_delay"
            fi
            acme_attempt=$((acme_attempt + 1))
        fi
    done
    log_fatal "ACME provisioner failed to become active after $acme_retries attempts."
}

# =====================================================================================
# Function: export_root_ca_certificate
# Description: Exports the root CA certificate to a shared location.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if export fails.
# =====================================================================================
export_root_ca_certificate() {
    log_info "Exporting root CA certificate to shared SSL directory..."
    local shared_ssl_dir="/etc/step-ca/ssl"
    local root_ca_cert_path="/root/.step/certs/root_ca.crt"

    if [ ! -f "$root_ca_cert_path" ]; then
        log_fatal "Root CA certificate not found at $root_ca_cert_path. Cannot export."
    fi

    # Create the full-chain bundle for clients like curl
    cat "/root/.step/certs/intermediate_ca.crt" > "${shared_ssl_dir}/phoenix_ca.crt"
    echo "" >> "${shared_ssl_dir}/phoenix_ca.crt"
    cat "$root_ca_cert_path" >> "${shared_ssl_dir}/phoenix_ca.crt"
    log_success "Full-chain CA bundle exported to ${shared_ssl_dir}/phoenix_ca.crt."

    # Also export the root certificate by itself for trust store installation
    cat "$root_ca_cert_path" > "${shared_ssl_dir}/phoenix_root_ca.crt" || log_fatal "Failed to export root CA certificate."
    log_success "Root CA certificate exported to ${shared_ssl_dir}/phoenix_root_ca.crt."

    # Generate and export the root CA fingerprint
    log_info "Generating and exporting root CA fingerprint..."
    local fingerprint
    fingerprint=$(/usr/bin/step certificate fingerprint "$root_ca_cert_path")
    if [ -z "$fingerprint" ]; then
        log_fatal "Failed to generate root CA fingerprint."
    fi
    echo "$fingerprint" > "${shared_ssl_dir}/root_ca.fingerprint" || log_fatal "Failed to export root CA fingerprint."
    log_success "Root CA fingerprint exported to ${shared_ssl_dir}/root_ca.fingerprint."
}

# =====================================================================================
# Function: setup_ca_service
# Description: Sets up and starts the systemd service for Smallstep CA.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if service setup fails.
# =====================================================================================
setup_ca_service() {
    log_info "Setting up systemd service for Smallstep CA..."
 
    # Create the wrapper script
    local WRAPPER_SCRIPT_PATH="/usr/local/bin/run-step-ca.sh"
    log_info "Creating wrapper script: ${WRAPPER_SCRIPT_PATH}"
    cat <<EOF > "${WRAPPER_SCRIPT_PATH}"
#!/bin/bash
/usr/bin/step-ca "${CA_CONFIG_FILE}" --password-file "${CA_PASSWORD_FILE}"
EOF
    chmod +x "${WRAPPER_SCRIPT_PATH}" || log_fatal "Failed to make wrapper script executable."
 
    # Create the systemd service file content
    local SERVICE_CONTENT="[Unit]
Description=Step CA Service
After=network.target
 
[Service]
ExecStart=${WRAPPER_SCRIPT_PATH}
StandardOutput=append:/var/log/step-ca-startup.log
StandardError=append:/var/log/step-ca-startup.log
Restart=always
User=root
 
[Install]
WantedBy=multi-user.target"
 
     # Push the service file to the container
    if ! /bin/bash -c "echo \"$SERVICE_CONTENT\" > \"$CA_SERVICE_FILE\""; then
        log_fatal "Failed to create systemd service file in container $CTID."
    fi

    # Reload systemd, enable and start the service
    if ! systemctl daemon-reload; then
        log_fatal "Failed to reload systemd daemon in container $CTID."
    fi
    if ! systemctl enable step-ca; then
        log_fatal "Failed to enable step-ca service in container $CTID."
    fi
    if ! systemctl start step-ca; then
        log_fatal "Failed to start step-ca service in container $CTID."
    fi

    # Health check loop to wait for the service to be ready
    log_info "Waiting for Step CA service to become healthy..."
    local retries=10
    local delay=3
    for ((i=0; i<retries; i++)); do
        if /usr/bin/step ca health --ca-url "https://$CA_DNS$CA_ADDRESS" --root /root/.step/certs/root_ca.crt &> /dev/null; then
            log_info "Step CA service is healthy."
            break
        fi
        log_info "Service not ready yet, waiting ${delay}s... ($((i+1))/${retries})"
        sleep $delay
    done

    if ! /usr/bin/step ca health --ca-url "https://$CA_DNS$CA_ADDRESS" --root /root/.step/certs/root_ca.crt &> /dev/null; then
        log_error "Step CA service failed to become healthy after $((retries * delay)) seconds."
        log_info "Displaying /var/log/step-ca-startup.log for more details:"
        cat /var/log/step-ca-startup.log || log_warn "Could not read /var/log/step-ca-startup.log"
        log_fatal "Step CA service failed to become healthy."
    fi
 
     # Add detailed logging for systemd status and journalctl
    log_info "Gathering detailed systemd status for step-ca..."
    systemctl status step-ca > /tmp/step-ca_systemctl_status.log 2>&1
    log_info "Systemd status logged to /tmp/step-ca_systemctl_status.log"
 
    log_info "Gathering detailed journalctl logs for step-ca..."
    journalctl -u step-ca --no-pager > /tmp/step-ca_journalctl.log 2>&1
    log_info "Journalctl logs logged to /tmp/step-ca_journalctl.log"

    # Add process and network inspection for step-ca
    log_info "Inspecting step-ca process details..."
    local step_ca_pid
    step_ca_pid=$(systemctl show --value --property MainPID step-ca)
    if [ -n "$step_ca_pid" ] && [ "$step_ca_pid" -ne 0 ]; then
        log_info "step-ca process (PID: $step_ca_pid) found. Checking open files and network connections..."
        lsof -p "$step_ca_pid" > /tmp/step-ca_lsof.log 2>&1 || log_warn "Failed to run lsof for step-ca process."
        log_info "lsof output for step-ca logged to /tmp/step-ca_lsof.log"
        
        # Check network connections specifically for the process
        netstat -tulnp | grep "$step_ca_pid" > /tmp/step-ca_netstat.log 2>&1 || log_warn "Failed to run netstat for step-ca process."
        log_info "netstat output for step-ca logged to /tmp/step-ca_netstat.log"
    else
        log_warn "step-ca process not found or PID is 0. Cannot perform lsof/netstat."
    fi

    log_info "ufw has been deprecated in favor of pve-firewall. Skipping internal firewall check."

    log_success "Smallstep CA service set up and started successfully with extended diagnostics."

    # Install net-tools for future debugging
    log_info "Installing net-tools (for netstat) in container..."
    if ! apt-get update > /dev/null 2>&1 || ! apt-get install -y net-tools > /dev/null 2>&1; then
        log_warn "Failed to install net-tools in container. netstat command may not be available."
    else
        log_info "net-tools installed successfully."
    fi
}

# =====================================================================================
# Function: main
# Description: Main entry point for the script.
# Arguments:
#   $1 - The CTID of the container.
# Returns:
#   None.
# =====================================================================================
main() {
    if [ -z "$CTID" ]; then
        log_fatal "Usage: $0 <CTID>"
    fi

    log_info "Starting Step CA application script for CTID $CTID."
 
    initialize_step_ca
    export_root_ca_certificate
    setup_ca_service
    add_acme_provisioner
    configure_acme_provisioner_claims
    verify_ca_status

    # Create a ready file to signal completion
    touch "/etc/step-ca/ssl/ca.ready" || log_warn "Failed to create CA ready file."
 
    log_info "Step CA application script completed for CTID $CTID."
}

# --- SCRIPT EXECUTION ---
main "$@"