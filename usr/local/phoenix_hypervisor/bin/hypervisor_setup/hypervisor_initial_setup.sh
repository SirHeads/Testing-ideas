#!/bin/bash

# File: hypervisor_initial_setup.sh
# Description: This script performs the foundational, one-time setup for a new Proxmox VE host, preparing it
#              to be managed by the Phoenix Hypervisor orchestration system. It handles a wide range of initial
#              configurations in a declarative and idempotent manner. Key responsibilities include configuring APT
#              repositories for Proxmox and Node.js, performing a full system upgrade, installing essential utilities,
#              setting the system timezone and NTP, configuring static networking, and establishing baseline firewall rules.
#              This script is the first step in the `--setup-hypervisor` workflow, laying the groundwork for all
#              subsequent feature scripts (ZFS, users, NVIDIA, etc.).
#
# Dependencies:
#   - /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh: For shared logging and utility functions.
#   - `jq`: For parsing the JSON configuration file.
#   - `curl`, `gpg`: For managing APT keys.
#   - `proxmox-boot-tool`: For refreshing the boot configuration after an upgrade.
#   - `timedatectl`, `chrony`: For time and date synchronization.
#   - `ufw`: The Uncomplicated Firewall.
#   - Standard system utilities: `apt-get`, `hostnamectl`, `systemctl`, `mv`, `cat`, `echo`.
#
# Inputs:
#   - A path to a JSON configuration file (e.g., `phoenix_hypervisor_config.json`) passed as the first command-line argument.
#   - The JSON file is expected to contain:
#     - `.timezone`: The desired system timezone (e.g., "America/New_York").
#     - `.network.hostname`: The desired hostname for the hypervisor.
#     - `.network.interfaces`: An object defining the primary network interface, including `name`, `address`, `gateway`, and `dns_nameservers`.
#
# Outputs:
#   - A fully updated and configured Proxmox VE host.
#   - Modified system configuration files (e.g., `/etc/apt/sources.list.d/`, `/etc/network/interfaces.d/`, `/etc/hosts`).
#   - Installed packages and enabled services.
#   - Logs all operations to standard output.
#   - Exit Code: 0 on success, non-zero on failure.

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# Ensure script is run as root
check_root

# Get the configuration file path from the first argument
if [ -z "$1" ]; then
    log_fatal "Configuration file path not provided."
fi
HYPERVISOR_CONFIG_FILE="$1"

# =====================================================================================
# Function: configure_log_rotation
# Description: Sets up a logrotate configuration for the main orchestrator log file to
#              prevent it from growing indefinitely.
# =====================================================================================
configure_log_rotation() {
    log_info "Configuring log rotation for $MAIN_LOG_FILE..."
    cat << EOF > /etc/logrotate.d/phoenix_hypervisor
$MAIN_LOG_FILE {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
    log_info "Configured log rotation for $MAIN_LOG_FILE"
}

# =====================================================================================
# Function: configure_proxmox_repositories
# Description: Configures the system's APT repositories to use the Proxmox "no-subscription"
#              repositories. This is a standard step for Proxmox installations that do not
#              have a commercial subscription, allowing access to stable updates.
# =====================================================================================
configure_proxmox_repositories() {
    log_info "Configuring Proxmox repositories for Trixie..."
    local proxmox_keyring="/usr/share/keyrings/proxmox-archive-keyring.gpg"

    log_info "Installing Proxmox GPG key to ${proxmox_keyring}..."
    if ! curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg -o "${proxmox_keyring}"; then
        log_fatal "Failed to download and install Proxmox GPG key."
    fi
    log_info "Proxmox GPG key installed."

    # Disable the enterprise repository to avoid warnings about missing subscriptions.
    if [ -f /etc/apt/sources.list.d/pve-enterprise.sources ]; then
        mv /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/pve-enterprise.sources.disabled
        log_info "Disabled Proxmox VE enterprise repository."
    fi

    # Add the PVE no-subscription repository.
    log_info "Creating Proxmox VE no-subscription source file..."
    cat << EOF > /etc/apt/sources.list.d/proxmox.sources
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: ${proxmox_keyring}
EOF

    # Add the Ceph no-subscription repository.
    log_info "Creating Ceph no-subscription source file..."
    cat << EOF > /etc/apt/sources.list.d/ceph.sources
Types: deb
URIs: http://download.proxmox.com/debian/ceph-squid
Suites: trixie
Components: no-subscription
Signed-By: ${proxmox_keyring}
EOF

    log_info "Successfully configured Proxmox and Ceph repositories."
}

# =====================================================================================
# Function: configure_nodesource_repository
# Description: Configures the NodeSource repository to allow for the installation of a
#              specific version of Node.js, which may be required by guest applications.
# =====================================================================================
configure_nodesource_repository() {
    log_info "Configuring NodeSource repository..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
    chmod 644 /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
    log_info "NodeSource repository configured for nodistro."
}

# =====================================================================================
# Function: update_and_upgrade_system
# Description: Performs a full system update and upgrade to ensure all packages are at
#              their latest versions. It also refreshes the Proxmox boot configuration
#              and the initramfs, which is crucial after kernel updates.
# =====================================================================================
update_and_upgrade_system() {
    log_info "Temporarily setting nameserver to 8.8.8.8 for initial setup..."
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    
    log_info "Updating and upgrading system (this may take a while)..."
    retry_command "apt-get update" || log_fatal "Failed to update package lists"
    
    # Ensure jq is installed, as it's a critical dependency for the rest of the orchestration.
    if ! command -v jq &> /dev/null; then
        log_info "jq is not installed. Installing..."
        if ! apt-get install -y jq; then
            log_fatal "Failed to install jq. Please install it manually and rerun the script."
        fi
    fi
    retry_command "apt-get dist-upgrade -y" || log_fatal "Failed to upgrade system"
    retry_command "proxmox-boot-tool refresh" || log_fatal "Failed to refresh proxmox-boot-tool"
    retry_command "update-initramfs -u" || log_fatal "Failed to update initramfs"
    log_info "System updated, upgraded, and initramfs refreshed"
}

# =====================================================================================
# Function: install_core_utilities
# Description: Installs a set of core utilities that are useful for system administration
#              and are dependencies for other features.
# =====================================================================================
install_core_utilities() {
    log_info "Installing core utilities (s-tui, samba)..."
    retry_command "apt-get install -y s-tui samba samba-common-bin smbclient libguestfs-tools" || log_fatal "Failed to install core utilities"
    log_info "Installed core utilities."
}

# =====================================================================================
# Function: set_system_timezone
# Description: Sets the system timezone based on the value in the configuration file.
# =====================================================================================
set_system_timezone() {
    local timezone=$(jq -r '.timezone // "America/New_York"' "$HYPERVISOR_CONFIG_FILE")
    log_info "Setting timezone to ${timezone}..."
    if ! timedatectl set-timezone "${timezone}"; then
        log_fatal "Failed to set timezone to ${timezone}"
    fi
    log_info "Timezone set to ${timezone}"
}

# =====================================================================================
# Function: configure_ntp
# Description: Installs and enables `chrony` to ensure the system's time is always
#              synchronized with Network Time Protocol (NTP) servers.
# =====================================================================================
configure_ntp() {
    log_info "Configuring NTP with chrony..."
    retry_command "apt-get install -y chrony" || log_fatal "Failed to install chrony"
    retry_command "systemctl enable --now chrony.service" || log_fatal "Failed to enable chrony"
    log_info "NTP configured with chrony"
}

# =====================================================================================
# Function: configure_networking
# Description: Applies the declarative network configuration from the JSON file. It sets
#              the system hostname, configures a static IP on the specified interface,
#              and updates the `/etc/hosts` file.
# =====================================================================================
configure_networking() {
    log_info "Reading and applying network configuration..."
    local HOSTNAME=$(jq -r '.network.hostname // "phoenix"' "$HYPERVISOR_CONFIG_FILE")
    local INTERFACE=$(jq -r '.network.interfaces.name // "vmbr0"' "$HYPERVISOR_CONFIG_FILE")
    local IP_ADDRESS=$(jq -r '.network.interfaces.address // "10.0.0.13/24"' "$HYPERVISOR_CONFIG_FILE")
    local GATEWAY=$(jq -r '.network.interfaces.gateway // "10.0.0.1"' "$HYPERVISOR_CONFIG_FILE")
    local DNS_SERVERS_JSON=$(jq -r '.network.interfaces.dns_nameservers | if type == "array" then .[] else . end' "$HYPERVISOR_CONFIG_FILE")
    local DNS_SERVERS=$(echo "$DNS_SERVERS_JSON" | tr '\n' ' ')

    if [[ -z "$HOSTNAME" || -z "$INTERFACE" || -z "$IP_ADDRESS" || -z "$GATEWAY" || -z "$DNS_SERVERS" ]]; then
        log_fatal "Missing network configuration in $HYPERVISOR_CONFIG_FILE."
    fi
    log_info "Network config: Hostname=$HOSTNAME, Interface=$INTERFACE, IP=$IP_ADDRESS, Gateway=$GATEWAY, DNS=$DNS_SERVERS"

    # Set the system hostname.
    retry_command "hostnamectl set-hostname $HOSTNAME" || log_fatal "Failed to set hostname"
    log_info "Set hostname to $HOSTNAME"

    # Create the network interface configuration file for a static IP.
    log_info "Configuring static IP for interface $INTERFACE..."
    cat << EOF > /etc/network/interfaces.d/50-$INTERFACE.cfg
auto $INTERFACE
iface $INTERFACE inet static
    address $IP_ADDRESS
    gateway $GATEWAY
    dns-nameservers 127.0.0.1 $DNS_SERVERS
EOF
    retry_command "systemctl restart networking" || log_fatal "Failed to restart networking"
    log_info "Configured static IP for interface $INTERFACE"

    # Temporarily set a public DNS for initial setup steps
    log_info "Temporarily setting nameserver to 8.8.8.8 for initial setup..."
    echo "nameserver 8.8.8.8" > /etc/resolv.conf

    # Update /etc/hosts to ensure the new hostname resolves locally.
    if ! grep -q "$HOSTNAME" /etc/hosts; then
        echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
        log_info "Added $HOSTNAME to /etc/hosts"
    fi
}


# =====================================================================================
# Function: main
# Description: Main execution flow for the initial hypervisor setup script. It orchestrates
#              the entire setup process in a logical sequence.
# =====================================================================================
main() {
    log_info "Starting initial Proxmox VE setup."
    
    configure_log_rotation
    configure_proxmox_repositories
    configure_nodesource_repository
    update_and_upgrade_system
    install_core_utilities
    set_system_timezone
    configure_ntp
    configure_networking

    if [ -f "${SCRIPT_DIR}/hypervisor_feature_setup_dns_server.sh" ]; then
        log_info "Running DNS Server setup script..."
        source "${SCRIPT_DIR}/hypervisor_feature_setup_dns_server.sh"
    else
        log_warning "DNS Server setup script not found. Skipping."
    fi

    # The initial setup also triggers other feature scripts to ensure a complete configuration.
    if [ -f "${SCRIPT_DIR}/hypervisor_feature_initialize_nvidia_gpus.sh" ]; then
        log_info "Running NVIDIA GPU initialization script..."
        source "${SCRIPT_DIR}/hypervisor_feature_initialize_nvidia_gpus.sh"
    else
        log_warning "NVIDIA GPU initialization script not found. Skipping."
    fi

    if [ -f "${SCRIPT_DIR}/hypervisor_feature_setup_apparmor.sh" ]; then
        log_info "Running AppArmor setup script..."
        source "${SCRIPT_DIR}/hypervisor_feature_setup_apparmor.sh"
    else
        log_warning "AppArmor setup script not found. Skipping."
    fi
    
    log_info "Successfully completed hypervisor_initial_setup.sh"
    exit 0
}

main "$@"