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
CA_PASSWORD_FILE="/root/.step/secrets/ca_password.txt"
CA_INIT_PASSWORD=$(openssl rand -base64 32) # Generate a strong, random password

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
 
    # Initialize the CA with a password and store it in a file
    log_info "Initializing Smallstep CA with a password and storing it in a file..."
    mkdir -p "$(dirname "$CA_PASSWORD_FILE")" || log_fatal "Failed to create directory for CA password file."
    echo "$CA_INIT_PASSWORD" > "$CA_PASSWORD_FILE" || log_fatal "Failed to write CA password to file."
    chmod 600 "$CA_PASSWORD_FILE" || log_fatal "Failed to set permissions for CA password file."

    if ! /bin/bash -c "echo \"$CA_INIT_PASSWORD\" | /usr/bin/step ca init --name \"$CA_NAME\" --dns \"$CA_DNS\" --address \"$CA_ADDRESS\" --provisioner \"$CA_PROVISIONER_EMAIL\" --deployment-type standalone --password-file \"$CA_PASSWORD_FILE\""; then
        log_fatal "Failed to initialize Smallstep CA in container $CTID."
    fi
    log_success "Smallstep CA initialized successfully."
 
    # Add ca.internal.thinkheads.ai to /etc/hosts for internal resolution
    log_info "Adding '127.0.0.1 ca.internal.thinkheads.ai' to /etc/hosts..."
    if ! grep -q "ca.internal.thinkheads.ai" /etc/hosts; then
        echo "127.0.0.1 ca.internal.thinkheads.ai" >> /etc/hosts || log_fatal "Failed to add entry to /etc/hosts."
    fi
    log_success "Entry added to /etc/hosts successfully."
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
    provisioner_list_output=$(/usr/bin/step ca provisioner list --ca-url "https://$CA_DNS$CA_ADDRESS" --root /root/.step/certs/root_ca.crt)
    if [ $? -ne 0 ]; then
        log_info "step ca provisioner list failed or returned empty output. Assuming no ACME provisioner exists."
        provisioner_list_output="[]" # Ensure the variable is a valid empty JSON array
    fi

    if echo "$provisioner_list_output" | jq -e '.[] | select(.type == "ACME")' > /dev/null; then
        log_info "ACME provisioner already exists. Skipping."
        return 0
    fi

    if ! /bin/bash -c "/usr/bin/step ca provisioner add acme --type ACME --ca-url https://$CA_DNS$CA_ADDRESS --root /root/.step/certs/root_ca.crt"; then
        log_fatal "Failed to add ACME provisioner to Smallstep CA in container $CTID."
    fi
    log_success "ACME provisioner added successfully."
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
/usr/bin/step-ca ${CA_CONFIG_FILE} --password-file "${CA_PASSWORD_FILE}"
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
    log_success "Smallstep CA service set up and started successfully."
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
    setup_ca_service
    add_acme_provisioner
 
    log_info "Step CA application script completed for CTID $CTID."
}

# --- SCRIPT EXECUTION ---
main "$@"