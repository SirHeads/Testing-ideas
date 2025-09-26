#!/bin/bash

# /usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_initialize_nvidia_gpus.sh
# Description: Ensures NVIDIA GPUs are initialized on boot before LXC containers start.
# This script creates and enables a systemd service that runs nvidia-smi.

# --- Script Header ---
set -e
# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Exiting."
    exit 1
fi
# --- End Script Header ---

SERVICE_NAME="nvidia-gpu-init.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

# Idempotency Check: Exit if the service file already exists
if [ -f "${SERVICE_FILE}" ]; then
    echo "NVIDIA GPU initialization service '${SERVICE_NAME}' already configured. Skipping."
    exit 0
fi

# Check if nvidia-smi is available
if [ ! -f "/usr/bin/nvidia-smi" ]; then
    echo "Warning: nvidia-smi not found at /usr/bin/nvidia-smi. The service will be created, but will not function until the NVIDIA drivers are installed."
fi

echo "Creating systemd service for NVIDIA GPU initialization..."

# Create the systemd service file
cat <<EOF > "${SERVICE_FILE}"
[Unit]
Description=NVIDIA GPU Initialization
Wants=syslog.target
After=syslog.target
Before=pve-guests.service

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi
RemainAfterExit=true
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF

# Set correct permissions for the service file
chmod 644 "${SERVICE_FILE}"

echo "Reloading systemd daemon and enabling the service..."
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"

echo "NVIDIA GPU initialization service '${SERVICE_NAME}' has been created and enabled successfully."

exit 0