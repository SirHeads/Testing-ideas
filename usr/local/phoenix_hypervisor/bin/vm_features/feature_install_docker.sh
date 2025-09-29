#!/bin/bash
set -e

# Log file for feature script execution
LOG_FILE="/var/log/phoenix_feature_docker.log"
exec &> >(tee -a "$LOG_FILE")

echo "--- Starting Docker Installation ---"

# Source common utilities
source "/tmp/phoenix_feature_run/phoenix_hypervisor_common_utils.sh"

# Set the context file path
CONTEXT_FILE="/tmp/phoenix_feature_run/phoenix_vm_configs.json"

# Get the VMID from the script's argument
VMID="$1"

# Get the username from the context file
USERNAME=$(get_vm_config "$VMID" ".user_config.username")

# 1. Update Package Manager
apt-get update

# 2. Install Dependencies
apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# 3. Add Docker's GPG Key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 4. Add Docker Repository
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# 5. Install Docker Engine
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# 6. Enable and Start Docker Service
systemctl enable docker
systemctl start docker

# 7. Add User to Docker Group
if [ -n "$USERNAME" ]; then
    usermod -aG docker "$USERNAME"
    echo "User $USERNAME added to the docker group."
fi

echo "--- Docker Installation Complete ---"