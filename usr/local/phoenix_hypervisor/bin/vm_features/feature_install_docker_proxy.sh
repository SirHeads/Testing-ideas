#!/bin/bash
#
# File: feature_install_docker_proxy.sh
# Description: This script configures the Docker daemon to listen on a TCP socket,
#              allowing Traefik to connect to it from outside the Swarm.
#
# Version: 2.0.0
# Author: Roo

set -e

# --- SCRIPT INITIALIZATION ---
source "/mnt/persistent/.phoenix_scripts/phoenix_hypervisor_common_utils.sh"

# --- MAIN LOGIC ---
main() {
    log_info "--- Configuring Docker to listen on TCP socket using daemon.json ---"

    local docker_config_dir="/etc/docker"
    local daemon_json_file="${docker_config_dir}/daemon.json"
    local old_drop_in_file="/etc/systemd/system/docker.service.d/override.conf"

    # Clean up the old override file to prevent conflicts
    if [ -f "$old_drop_in_file" ]; then
        log_info "Removing old systemd drop-in file..."
        rm -f "$old_drop_in_file"
    fi

    if [ ! -d "$docker_config_dir" ]; then
        log_info "Creating Docker config directory..."
        mkdir -p "$docker_config_dir"
    fi

    log_info "Creating/Updating ${daemon_json_file} to expose Docker on TCP..."
    cat <<EOF > "$daemon_json_file"
{
  "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"]
}
EOF

    log_info "Reloading systemd daemon and restarting Docker service..."
    systemctl daemon-reload
    systemctl restart docker

    log_success "Docker service configured to listen on TCP socket successfully."
}

main "$@"