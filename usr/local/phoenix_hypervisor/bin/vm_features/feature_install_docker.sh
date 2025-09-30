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
#   - The phoenix_hypervisor_common_utils.sh script, which is expected to be available at /tmp/phoenix_feature_run/.
#   - A context file (phoenix_vm_configs.json) at /tmp/phoenix_feature_run/ containing VM-specific details.
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

# Log file for feature script execution. This captures all output for debugging and auditing VM provisioning.
LOG_FILE="/var/log/phoenix_feature_docker.log"
exec &> >(tee -a "$LOG_FILE")

echo "--- Starting Docker Installation ---"

# Source common utilities provided by the orchestrator. This script contains helper functions for tasks like reading configuration.
source "/tmp/phoenix_feature_run/phoenix_hypervisor_common_utils.sh"

# Set the context file path. This JSON file contains the configuration for all VMs managed by the Phoenix Hypervisor.
CONTEXT_FILE="/tmp/phoenix_feature_run/phoenix_vm_configs.json"

# Get the VMID from the script's first argument, passed by the orchestrator during the feature application step.
VMID="$1"

# Get the primary username from the context file to grant Docker permissions.
# This makes the VM user-friendly by avoiding the need for 'sudo' for every Docker command.
USERNAME=$(get_vm_config "$VMID" ".user_config.username")

# 1. Update Package Manager
# Ensures the local package index is up-to-date before installing new software.
apt-get update

# 2. Install Dependencies
# Installs packages required to add and manage APT repositories over HTTPS.
apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# 3. Add Docker's Official GPG Key
# This key is used to verify the authenticity of the Docker packages.
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 4. Add Docker Repository
# Adds the official Docker repository to the system's APT sources, ensuring access to the latest stable releases.
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# 5. Install Docker Engine
# Updates the package index again to include the new Docker repository, then installs the Docker packages.
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# 6. Enable and Start Docker Service
# Configures Docker to start on boot and starts the service immediately.
systemctl enable docker
systemctl start docker

# 7. Add User to Docker Group
# If a username was successfully retrieved, this step adds the user to the 'docker' group.
# This is a crucial post-installation step for security and usability, as it allows the user to run Docker commands without sudo.
if [ -n "$USERNAME" ]; then
    usermod -aG docker "$USERNAME"
    echo "User $USERNAME added to the docker group."
fi

echo "--- Docker Installation Complete ---"