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

if is_feature_present_on_container "$CTID" "ollama"; then
    log_info "Ollama feature is already installed. Skipping."
    exit_script 0
fi

log_info "Installing Ollama in CTID $CTID..."
pct_exec "$CTID" bash -c "curl -fsSL https://ollama.com/install.sh | sh"
log_info "Ollama installation complete."

exit_script 0