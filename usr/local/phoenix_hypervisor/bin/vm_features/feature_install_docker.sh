#!/bin/bash
# File: feature_install_docker.sh
# Description: This script automates the installation and configuration of Docker Engine within a Phoenix Hypervisor VM.
#              It is designed to be executed by the phoenix_orchestrator.sh during the VM provisioning process.
#              The script handles package updates, dependency installation, GPG key addition, repository setup,
#              and adds the primary VM user to the 'docker' group for non-root access. This entire process
#              is a core component of the VM feature installation framework, enabling containerization
#              capabilities in newly created virtual machines.
#
# Dependencies:
#   - An Ubuntu-based VM environment.
#   - Access to the internet for downloading packages.
#   - The phoenix_hypervisor_common_utils.sh script, which is expected to be available at /persistent-storage/.phoenix_scripts/.
#   - A context file (vm_context.json) at /persistent-storage/.phoenix_scripts/ containing VM-specific details.
#
# Inputs:
#   - $1: The VMID of the target virtual machine. This is used to retrieve configuration details from the context file.
#
# Outputs:
#   - Installs Docker Engine on the VM.
#   - Starts and enables the Docker service.
#   - Adds the configured user to the 'docker' group.
#   - Logs all execution output to /var/log/phoenix_feature_docker.log.
#

set -e
export PHOENIX_DEBUG="true" # Temporarily force debug mode for this script

# Source common utilities provided by the orchestrator. This script contains helper functions for tasks like reading configuration.
source "$(dirname "$0")/phoenix_hypervisor_common_utils.sh"

# Enable verbose logging if PHOENIX_DEBUG is set to "true"
if [ "$PHOENIX_DEBUG" == "true" ]; then
    set -x
fi

# Log file for feature script execution. This captures all output for debugging and auditing VM provisioning.
LOG_FILE="/var/log/phoenix_feature_docker.log"
exec &> >(tee -a "$LOG_FILE")

log_info "--- Starting Docker Installation ---"
wait_for_apt_lock
log_info "Sourcing common utilities..." # This log_info will now work

log_info "Setting context file path..."
# Set the context file path. This JSON file contains the configuration for the VM.
CONTEXT_FILE="$(dirname "$0")/vm_context.json"
if [ ! -f "$CONTEXT_FILE" ]; then
    log_fatal "VM context file not found at $CONTEXT_FILE. Cannot proceed with Docker installation."
fi
log_info "Context file set to $CONTEXT_FILE."


# Idempotency Check: Check if Docker is already installed and running.
log_info "Checking for existing Docker installation..."
if command -v docker &> /dev/null && systemctl is-active --quiet docker; then
    log_info "Docker is already installed and running. Skipping installation."
    exit 0
fi
log_info "No existing Docker installation found. Proceeding with installation."

# Get the primary username from the context file to grant Docker permissions.
log_info "Retrieving primary username from VM context..."
USERNAME=$(jq -r '.user_config.username // ""' "$CONTEXT_FILE")
if [ -z "$USERNAME" ] || [ "$USERNAME" == "null" ]; then
    log_fatal "Could not find a valid 'username' in the VM context file. This is required to configure Docker permissions."
fi
log_info "Primary username is '$USERNAME'."

# 1. Update Package Manager
log_info "Step 1: Updating package manager (apt-get update)..."
wait_for_apt_lock
if ! apt-get update; then
    log_fatal "Failed to update package manager. Please check network connectivity and repository configuration."
fi
log_info "Package manager updated successfully."

# 2. Install Dependencies
log_info "Step 2: Installing dependencies for Docker (apt-get install apt-transport-https ca-certificates curl software-properties-common)..."
wait_for_apt_lock
if ! apt-get install -y apt-transport-https ca-certificates curl software-properties-common; then
    log_fatal "Failed to install Docker dependencies."
fi
log_info "Dependencies installed successfully."

# 3. Add Docker's Official GPG Key
log_info "Step 3: Adding Docker's official GPG key (curl | gpg --dearmor)..."
if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg; then
    log_fatal "Failed to add Docker's GPG key. Command: curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"
fi
log_info "Docker GPG key added successfully."

# 4. Add Docker Repository
log_info "Step 4: Adding Docker repository (echo deb | tee /etc/apt/sources.list.d/docker.list)..."
if ! echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null; then
    log_fatal "Failed to add Docker repository. Command: echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null"
fi
log_info "Docker repository added successfully."

# 5. Install Docker Engine
log_info "Step 5: Installing Docker Engine (apt-get update && apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)..."
wait_for_apt_lock
if ! apt-get update || ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    log_fatal "Failed to install Docker Engine. Command: apt-get update || apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
fi
log_info "Docker Engine installed successfully."

# Step 5.5: Configure Docker Daemon with Internal DNS
log_info "Step 5.5: Configuring Docker daemon with internal DNS..."
INTERNAL_DNS_SERVER="10.0.0.1" # Use the network gateway for DNS

log_info "Setting Docker DNS to '$INTERNAL_DNS_SERVER'."
mkdir -p /etc/docker
echo "{\"dns\": [\"$INTERNAL_DNS_SERVER\"]}" > /etc/docker/daemon.json

# 6. Enable and Start Docker Service
log_info "Step 6: Enabling and starting Docker service (systemctl enable docker && systemctl start docker)..."
if ! systemctl enable docker || ! systemctl start docker; then
    log_fatal "Failed to enable or start Docker service."
fi
log_info "Docker service enabled and started successfully."

# 7. Add User to Docker Group
log_info "Step 7: Adding user '$USERNAME' to the docker group (getent group docker || groupadd docker; usermod -aG docker)..."
if ! getent group docker >/dev/null; then
    log_info "Docker group does not exist. Creating it..."
    if ! groupadd docker; then
        log_fatal "Failed to create docker group."
    fi
fi
if ! usermod -aG docker "$USERNAME"; then
    log_fatal "Failed to add user '$USERNAME' to the docker group."
fi
log_info "User '$USERNAME' added to the docker group successfully."

# Step 8 is now obsolete as docker-compose-plugin is installed with the main packages.
log_info "Step 8: Docker Compose plugin is installed as part of Docker Engine."

# Steps 9, 10, and 11 are now obsolete.
# - Step 9 (Manual CA Trust) is handled by the 'trusted_ca' feature script, which runs before this one.
# - Step 10 (Manual Certificate Generation) is no longer needed as Traefik will manage TLS.
# - Step 11 (Service Startup) is now handled by the 'portainer-manager.sh' during a 'sync' operation.
log_info "Steps 9, 10, and 11 are obsolete and have been removed."

log_info "--- Docker Installation Complete ---"