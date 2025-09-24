# Determine the absolute path of the directory containing this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Source the common utilities script using the calculated absolute path
# This ensures the script can be called from any directory
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"
#!/bin/bash

# File: hypervisor_initial_setup.sh
# Description: Initializes a Proxmox VE host with essential configurations.
#              This script configures Proxmox repositories for Trixie, updates the system,
#              installs core utilities (jq, s-tui, Samba), sets timezone and NTP,
#              configures static network interfaces, and establishes UFW firewall rules.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), jq, apt-get,
#               proxmox-boot-tool, update-initramfs, timedatectl, chrony,
#               systemctl, hostnamectl, ufw, grep, mv, cat, echo.
# Inputs:
#   Configuration values from HYPERVISOR_CONFIG_FILE: .network.hostname,
#   .network.interfaces.name, .network.interfaces.address, .network.interfaces.gateway,
#   .network.interfaces.dns_nameservers.
# Outputs:
#   System updates, package installations, configuration file modifications
#   (`/etc/logrotate.d/phoenix_hypervisor`, `/etc/apt/sources.list`,
#   `/etc/network/interfaces.d/50-<interface>.cfg`, `/etc/hosts`, UFW rules),
#   log messages to stdout and MAIN_LOG_FILE, exit codes indicating success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- Determine script's absolute directory ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling, etc.
source "${SCRIPT_DIR}/../phoenix_hypervisor_common_utils.sh"

# Ensure script is run as root
check_root # Ensure the script is run with root privileges

# Get the configuration file path from the first argument
if [ -z "$1" ]; then
    log_fatal "Configuration file path not provided."
fi
HYPERVISOR_CONFIG_FILE="$1"
 

# Configure log rotation
# =====================================================================================
# Function: configure_log_rotation
# Description: Sets up log rotation for the main orchestrator log file.
# Arguments:
#   None (uses global MAIN_LOG_FILE).
# Returns:
#   None.
# =====================================================================================
configure_log_rotation() {
    log_info "Configuring log rotation for $MAIN_LOG_FILE..."
    cat << EOF > /etc/logrotate.d/phoenix_hypervisor # Create logrotate configuration file
$MAIN_LOG_FILE {
    daily # Rotate logs daily
    rotate 7 # Keep 7 rotated log files
    compress # Compress old log files
    delaycompress # Delay compression until the next rotation cycle
    missingok # Do not report an error if the log file is missing
    notifempty # Do not rotate the log if it is empty
    create 644 root root # Create new log file with specified permissions and ownership
}
EOF
    log_info "Configured log rotation for $MAIN_LOG_FILE"
}

# --- BEGIN MODIFIED REPOSITORY CONFIGURATION (FOR PROXMOX 9 - TRIXIE) ---
# =====================================================================================
# Function: configure_proxmox_repositories
# Description: Configures Proxmox VE repositories for the Trixie distribution.
#              It downloads the Proxmox GPG key, disables enterprise repositories,
#              and enables no-subscription repositories for PVE and Ceph.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if file operations or GPG key installation fail.
# =====================================================================================
configure_proxmox_repositories() {
    log_info "Configuring Proxmox repositories for Trixie..."

    # Define GPG key path
    local proxmox_keyring="/usr/share/keyrings/proxmox-archive-keyring.gpg"

    # Install Proxmox GPG key
    log_info "Installing Proxmox GPG key to ${proxmox_keyring}..."
    if ! curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg -o "${proxmox_keyring}"; then
        log_fatal "Failed to download and install Proxmox GPG key."
    fi
    log_info "Proxmox GPG key installed."

    # Disable Enterprise Repositories by renaming them if it exists
    if [ -f /etc/apt/sources.list.d/pve-enterprise.sources ]; then
        mv /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/pve-enterprise.sources.disabled
        log_info "Disabled Proxmox VE enterprise repository."
    fi

    # Create the PVE no-subscription repository file
    log_info "Creating Proxmox VE no-subscription source file..."
    cat << EOF > /etc/apt/sources.list.d/proxmox.sources
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: ${proxmox_keyring}
EOF

    # Create the Ceph no-subscription repository file
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
# --- END MODIFIED REPOSITORY CONFIGURATION ---

# Configure NodeSource repository
# =====================================================================================
# Function: configure_nodesource_repository
# Description: Configures the NodeSource repository for Node.js 20.x using the
#              "nodistro" distribution.
# Arguments:
#   None.
# Returns:
#   None.
# =====================================================================================
configure_nodesource_repository() {
    log_info "Configuring NodeSource repository..."
    
    # Create the keyring directory if it doesn't exist
    mkdir -p /etc/apt/keyrings
    
    # Download the NodeSource GPG key
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
    
    # Set the correct permissions for the GPG key
    chmod 644 /etc/apt/keyrings/nodesource.gpg
    
    # Create the repository source file with "nodistro"
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
    
    log_info "NodeSource repository configured for nodistro."
}

# Update and upgrade system
# =====================================================================================
# Function: update_and_upgrade_system
# Description: Updates package lists, performs a full system upgrade, and refreshes
#              Proxmox boot configuration and initramfs.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if any update/upgrade command fails.
# =====================================================================================
update_and_upgrade_system() {
    log_info "Updating and upgrading system (this may take a while)..."
    retry_command "apt-get update" || log_fatal "Failed to update package lists" # Update package lists
    
    # --- Check and install jq ---
    if ! command -v jq &> /dev/null; then
        log_info "jq is not installed. Installing..."
        if apt-get install -y jq; then
            log_info "jq installed successfully."
        else
            log_fatal "Failed to install jq. Please install it manually and rerun the script."
        fi
    else
        log_info "jq is already installed."
    fi
    retry_command "apt-get dist-upgrade -y" || log_fatal "Failed to upgrade system" # Perform full system upgrade
    retry_command "proxmox-boot-tool refresh" || log_fatal "Failed to refresh proxmox-boot-tool" # Refresh Proxmox boot configuration
    retry_command "update-initramfs -u" || log_fatal "Failed to update initramfs" # Update initramfs
    log_info "System updated, upgraded, and initramfs refreshed"
}


# Install s-tui
# =====================================================================================
# Function: install_s_tui
# Description: Installs the `s-tui` system monitoring tool.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if `s-tui` installation fails.
# =====================================================================================
install_s_tui() {
    log_info "Installing s-tui..."
    retry_command "apt-get install -y s-tui" || log_fatal "Failed to install s-tui" # Install s-tui
    log_info "Installed s-tui"
}

# Install Samba packages
# =====================================================================================
# Function: install_samba_packages
# Description: Installs Samba server and client packages if they are not already present.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if Samba installation fails.
# =====================================================================================
install_samba_packages() {
    # Check if Samba is already installed
    if ! command -v smbd >/dev/null 2>&1; then
        log_info "Installing Samba..."
        retry_command "apt-get install -y samba samba-common-bin smbclient" || log_fatal "Failed to install Samba" # Install Samba packages
        log_info "Installed Samba"
    else
        log_info "Samba already installed, skipping installation"
    fi
}

# Set timezone
# =====================================================================================
# Function: set_system_timezone
# Description: Sets the system timezone to "America/New_York".
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if setting the timezone fails.
# =====================================================================================
set_system_timezone() {
    local timezone
    timezone=$(jq -r '.timezone // "America/New_York"' "$HYPERVISOR_CONFIG_FILE")
    log_info "Setting timezone to ${timezone}..."
    if ! timedatectl set-timezone "${timezone}"; then
        log_fatal "Failed to set timezone to ${timezone}"
    fi
    log_info "Timezone set to ${timezone}"
}

# Configure NTP
# =====================================================================================
# Function: configure_ntp
# Description: Configures Network Time Protocol (NTP) using `chrony`.
#              It installs `chrony` and enables/starts its systemd service.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if `chrony` installation or service management fails.
# =====================================================================================
configure_ntp() {
    log_info "Configuring NTP with chrony..."
    retry_command "apt-get install -y chrony" || log_fatal "Failed to install chrony" # Install chrony
    retry_command "systemctl enable --now chrony.service" || log_fatal "Failed to enable chrony" # Enable and start chrony service
    log_info "NTP configured with chrony"
}

# Read network configuration from hypervisor_config.json
# =====================================================================================
# Function: read_network_config
# Description: Reads network configuration parameters from `hypervisor_config.json`.
# Arguments:
#   None (uses global HYPERVISOR_CONFIG_FILE).
# Returns:
#   None. Exits with a fatal error if essential network configuration values are missing.
# =====================================================================================
read_network_config() {
    log_info "Reading network configuration from $HYPERVISOR_CONFIG_FILE..."
    HOSTNAME=$(jq -r '.network.hostname // "phoenix"' "$HYPERVISOR_CONFIG_FILE") # Hostname
    INTERFACE=$(jq -r '.network.interfaces.name // "vmbr0"' "$HYPERVISOR_CONFIG_FILE") # Network interface name
    IP_ADDRESS=$(jq -r '.network.interfaces.address // "10.0.0.13/24"' "$HYPERVISOR_CONFIG_FILE") # Static IP address with CIDR
    GATEWAY=$(jq -r '.network.interfaces.gateway // "10.0.0.1"' "$HYPERVISOR_CONFIG_FILE") # Network gateway
    DNS_SERVER=$(jq -r '.network.interfaces.dns_nameservers // "8.8.8.8"' "$HYPERVISOR_CONFIG_FILE") # DNS nameservers

    # Validate that all essential network configuration values are present
    if [[ -z "$HOSTNAME" || -z "$INTERFACE" || -z "$IP_ADDRESS" || -z "$GATEWAY" || -z "$DNS_SERVER" ]]; then
        log_fatal "Missing network configuration in $HYPERVISOR_CONFIG_FILE. Please ensure hostname, interface, address, gateway, and dns_nameservers are defined."
    fi

log_info "Using network configuration: Hostname=$HOSTNAME, Interface=$INTERFACE, IP=$IP_ADDRESS, Gateway=$GATEWAY, DNS=$DNS_SERVER"
}
 
 # =====================================================================================
# Function: set_system_hostname
# Description: Sets the system hostname.
# Arguments:
#   None (uses global HOSTNAME).
# Returns:
#   None. Exits with a fatal error if setting the hostname fails.
# =====================================================================================
set_system_hostname() {
    # Set the system hostname
    retry_command "hostnamectl set-hostname $HOSTNAME" || log_fatal "Failed to set hostname"
    log_info "Set hostname to $HOSTNAME"
}

# =====================================================================================
# Function: configure_network_interface
# Description: Configures a static IP address for the specified network interface
#              by creating a configuration file in `/etc/network/interfaces.d/`
#              and restarting the networking service.
# Arguments:
#   None (uses global INTERFACE, IP_ADDRESS, GATEWAY, DNS_SERVER).
# Returns:
#   None. Exits with a fatal error if writing the configuration file or restarting
#   networking fails.
# =====================================================================================
configure_network_interface() {
    log_info "Configuring static IP for interface $INTERFACE..."
    cat << EOF > /etc/network/interfaces.d/50-$INTERFACE.cfg # Create network interface configuration file
auto $INTERFACE
iface $INTERFACE inet static
    address $IP_ADDRESS
    gateway $GATEWAY
    dns-nameservers $DNS_SERVER
EOF
    retry_command "systemctl restart networking" || log_fatal "Failed to restart networking" # Restart networking service
    log_info "Configured static IP for interface $INTERFACE with address $IP_ADDRESS, gateway $GATEWAY, and DNS $DNS_SERVER"
}

# =====================================================================================
# Function: update_etc_hosts
# Description: Adds the system hostname to `/etc/hosts` if it's not already present.
# Arguments:
#   None (uses global HOSTNAME).
# Returns:
#   None.
# =====================================================================================
update_etc_hosts() {
    # Update /etc/hosts with the system hostname
    if ! grep -q "$HOSTNAME" /etc/hosts; then
        echo "127.0.1.1 $HOSTNAME" >> /etc/hosts # Add hostname entry
        log_info "Added $HOSTNAME to /etc/hosts"
    else
        log_info "Hostname $HOSTNAME already in /etc/hosts, skipping"
    fi
}

# =====================================================================================
# Function: install_ufw
# Description: Installs the Uncomplicated Firewall (UFW) if it is not already present.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if UFW installation fails.
# =====================================================================================
install_ufw() {
    # Install ufw if not present
    if ! command -v ufw >/dev/null 2>&1; then
        log_info "Installing ufw..."
        retry_command "apt-get install -y ufw" || log_fatal "Failed to install ufw" # Install ufw
        log_info "Installed ufw"
    fi
}

# =====================================================================================
# Function: configure_firewall_rules
# Description: Configures essential UFW firewall rules for Proxmox VE, including
#              allowing OpenSSH, Proxmox UI port, NFS, RPC, and Samba traffic,
#              then enables the firewall.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if any firewall rule application or UFW
#   enablement fails.
# =====================================================================================
configure_firewall_rules() {
    log_info "Configuring firewall rules..."
    retry_command "ufw allow OpenSSH" || log_fatal "Failed to allow OpenSSH in firewall" # Allow SSH
    retry_command "ufw allow 8006/tcp" || log_fatal "Failed to allow Proxmox UI port in firewall" # Allow Proxmox Web UI
    retry_command "ufw allow 2049/tcp" || log_fatal "Failed to allow NFS port in firewall" # Allow NFS
    retry_command "ufw allow 111/tcp" || log_fatal "Failed to allow RPC port in firewall" # Allow RPC (for NFS)
    retry_command "ufw allow Samba" || log_fatal "Failed to allow Samba in firewall" # Allow Samba
    # Enable and start UFW firewall
    log_info "Enabling and starting UFW firewall..."
    if ufw status | grep -q "Status: active"; then
        log_info "UFW firewall is already active."
    else
        yes | ufw enable
        if ! ufw status | grep -q "Status: active"; then
            log_fatal "Failed to enable UFW firewall."
        fi
    fi
    retry_command "systemctl start ufw" || log_fatal "Failed to start UFW service."
    retry_command "systemctl enable ufw" || log_fatal "Failed to enable UFW service on boot."
    log_info "Firewall rules configured and UFW service enabled and started."
}


# =====================================================================================
# Function: main
# Description: Main execution flow for the initial hypervisor setup script.
#              It orchestrates the entire setup process, including repository
#              configuration, system updates, package installations, timezone/NTP
#              setup, network configuration, and firewall rules.
# Arguments:
#   None.
# Returns:
#   Exits with status 0 on successful completion.
# =====================================================================================
main() {
    log_info "Starting initial Proxmox VE setup."
    
    configure_log_rotation # Configure log rotation for the main log file
    configure_proxmox_repositories # Configure Proxmox repositories
    configure_nodesource_repository # Configure NodeSource repository
    update_and_upgrade_system # Update and upgrade the system
    install_s_tui # Install s-tui
    install_samba_packages # Install Samba packages
    set_system_timezone # Set system timezone
    configure_ntp # Configure NTP with chrony
    read_network_config # Read network configuration from JSON
    set_system_hostname # Set system hostname
    configure_network_interface # Configure static IP for network interface
    update_etc_hosts # Update /etc/hosts

    # Initialize NVIDIA GPUs
    if [ -f "${SCRIPT_DIR}/hypervisor_feature_initialize_nvidia_gpus.sh" ]; then
        log_info "Running NVIDIA GPU initialization script..."
        source "${SCRIPT_DIR}/hypervisor_feature_initialize_nvidia_gpus.sh"
    else
        log_warning "NVIDIA GPU initialization script not found. Skipping."
    fi

    install_ufw # Install ufw if not present
    configure_firewall_rules # Configure firewall rules

    # Deploy custom AppArmor profiles
    if [ -f "${SCRIPT_DIR}/hypervisor_feature_setup_apparmor.sh" ]; then
        log_info "Running AppArmor setup script..."
        source "${SCRIPT_DIR}/hypervisor_feature_setup_apparmor.sh"
    else
        log_warning "AppArmor setup script not found. Skipping."
    fi
    
    log_info "Successfully completed hypervisor_initial_setup.sh"
    exit 0
}

main "$@" # Call the main function to execute the script