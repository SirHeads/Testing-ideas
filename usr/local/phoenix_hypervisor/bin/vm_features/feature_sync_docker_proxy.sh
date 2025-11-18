#!/bin/bash
#
# File: feature_sync_docker_proxy.sh
# Description: This script configures the Docker daemon to listen on a secure TCP socket,
#              allowing Traefik to connect to it from outside the Swarm. This script
#              is intended to be run during the 'sync' phase, after the certificates
#              have been generated.
#
# Version: 1.0.0
# Author: Roo

set -e

# --- SCRIPT INITIALIZATION ---
source "/mnt/persistent/.phoenix_scripts/phoenix_hypervisor_common_utils.sh"

# --- MAIN LOGIC ---
main() {
    log_info "--- Configuring Docker to listen on secure TCP socket (2376) ---"

    local docker_config_dir="/etc/docker"
    local daemon_json_file="${docker_config_dir}/daemon.json"
    local cert_dir="${docker_config_dir}/tls"
    
    mkdir -p "$cert_dir"

    log_info "Creating/Updating ${daemon_json_file} to expose Docker on secure TCP..."
    cat <<EOF > "$daemon_json_file"
{
  "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2376"],
  "tls": true,
  "tlscacert": "${cert_dir}/ca.pem",
  "tlscert": "${cert_dir}/server-cert.pem",
  "tlskey": "${cert_dir}/server-key.pem",
  "tlsverify": true
}
EOF

    log_info "Reloading systemd daemon and restarting Docker service..."
    systemctl daemon-reload
    systemctl restart docker

    log_success "Docker service configured to listen on secure TCP socket successfully."
}

main "$@"