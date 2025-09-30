#!/bin/bash

# File: hypervisor_feature_initialize_nvidia_gpus.sh
# Description: This script ensures that the NVIDIA GPU drivers on the Proxmox host are fully initialized
#              before any LXC containers or VMs are started. It achieves this by creating and enabling a
#              systemd service that executes `nvidia-smi`. This simple command is sufficient to trigger
#              the initialization of the GPU hardware and the loading of the kernel driver.
#              The service is critically ordered to run *before* the `pve-guests.service`, which manages
#              the startup of guest environments. This prevents race conditions where a container with GPU
#              passthrough might start before the host's NVIDIA driver is ready, leading to instability or errors.
#              The script is idempotent and will not make changes if the service is already configured.
#
# Dependencies:
#   - `systemd`: The system and service manager.
#   - `nvidia-smi`: The NVIDIA System Management Interface utility. The script will warn if this is not found,
#     as the service depends on it.
#
# Inputs:
#   - None. The script is self-contained.
#
# Outputs:
#   - Creates a systemd service file at `/etc/systemd/system/nvidia-gpu-init.service`.
#   - Enables the created service to ensure it runs on boot.
#   - Logs its progress to standard output.
#   - Exit Code: 0 on success or if the service already exists.

set -e # Exit immediately if a command exits with a non-zero status.

# Ensure the script is run as root, as it modifies systemd configuration.
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Exiting."
    exit 1
fi

SERVICE_NAME="nvidia-gpu-init.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

# Idempotency Check: If the service file already exists, no action is needed.
if [ -f "${SERVICE_FILE}" ]; then
    echo "NVIDIA GPU initialization service '${SERVICE_NAME}' already configured. Skipping."
    exit 0
fi

# Pre-flight check to see if the NVIDIA drivers are likely installed.
# The service will be created regardless, but this provides a useful warning to the user.
if [ ! -f "/usr/bin/nvidia-smi" ]; then
    echo "Warning: nvidia-smi not found at /usr/bin/nvidia-smi. The service will be created, but will not function until the NVIDIA drivers are installed."
fi

echo "Creating systemd service for NVIDIA GPU initialization..."

# Create the systemd service file using a heredoc for clarity.
cat <<EOF > "${SERVICE_FILE}"
[Unit]
Description=NVIDIA GPU Initialization
# This service should run after basic system logging is available.
Wants=syslog.target
After=syslog.target
# CRITICAL: This service must run *before* Proxmox starts any guest containers or VMs.
# This prevents race conditions related to GPU passthrough.
Before=pve-guests.service

[Service]
# 'oneshot' means the service does a single job and then exits.
Type=oneshot
# The command itself is simple: running nvidia-smi is enough to initialize the GPUs.
ExecStart=/usr/bin/nvidia-smi
# 'RemainAfterExit' ensures that systemd considers the service "active" even after the command finishes.
RemainAfterExit=true
StandardOutput=journal

[Install]
# This target ensures the service is started during the normal multi-user boot process.
WantedBy=multi-user.target
EOF

# Set standard, secure permissions for the systemd service file.
chmod 644 "${SERVICE_FILE}"

echo "Reloading systemd daemon and enabling the service..."
# Inform systemd of the new service file.
systemctl daemon-reload
# Enable the service to make it start automatically on subsequent boots.
systemctl enable "${SERVICE_NAME}"

echo "NVIDIA GPU initialization service '${SERVICE_NAME}' has been created and enabled successfully."

exit 0