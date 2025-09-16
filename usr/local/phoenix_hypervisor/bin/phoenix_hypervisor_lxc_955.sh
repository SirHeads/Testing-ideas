#!/bin/bash
#
# File: phoenix_hypervisor_lxc_955.sh
# Description: Configures and enables the Ollama systemd service inside the container.

set -e
set -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/phoenix_hypervisor_common_utils.sh"

if [ "$#" -ne 1 ]; then
    log_error "Usage: $0 <CTID>"
    exit_script 2
fi
CTID="$1"

log_info "Starting Ollama application setup for CTID: $CTID"

# 1. Configure PATH environment
log_info "Configuring PATH for Ollama..."
echo 'export PATH="$PATH:/usr/local/bin"' > /etc/profile.d/ollama.sh

# 2. Create and enable systemd service
log_info "Creating and enabling Ollama systemd service..."
cat <<EOF > /etc/systemd/system/ollama.service
[Unit]
Description=Ollama API Service
After=network-online.target

[Service]
ExecStart=/usr/bin/ollama serve
User=root
Group=root
Restart=always
RestartSec=3
Environment="OLLAMA_HOST=0.0.0.0:11434"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ollama.service
systemctl restart ollama.service

log_info "Ollama application setup complete for CTID $CTID."
exit_script 0