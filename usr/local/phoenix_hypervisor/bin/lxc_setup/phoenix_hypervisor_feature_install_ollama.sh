#!/bin/bash
#
# File: phoenix_hypervisor_feature_install_ollama.sh
# Description: Installs Ollama within the specified LXC container.

set -e
set -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

if [ "$#" -ne 1 ]; then
    log_error "Usage: $0 <CTID>"
    exit_script 2
fi
CTID="$1"

log_info "Starting Ollama feature installation for CTID: $CTID"

# Check if ollama is already installed
if pct_exec "$CTID" command -v ollama &> /dev/null; then
    log_info "Ollama is already installed in CTID $CTID. Skipping installation."
else
    log_info "Installing Ollama in CTID $CTID..."
    pct_exec "$CTID" bash -c "curl -fsSL https://ollama.com/install.sh | sh"
    log_info "Ollama installation complete."
fi

exit_script 0