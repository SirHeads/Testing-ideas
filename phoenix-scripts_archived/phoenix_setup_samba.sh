# Metadata: {"chunk_id": "phoenix_setup_samba-1.0", "keywords": ["samba", "proxmox", "shares"], "comment_type": "block"}
#!/bin/bash
# phoenix_setup_samba.sh
# Configures Samba file server on Proxmox VE with shares for ZFS datasets and user authentication
# Version: 1.2.3 (Enhanced Share Configuration)
# Author: Heads, Grok, Devstral

# Main: Configures Samba shares for specified datasets
# Args: -p <password> (Samba user password), -n <network_name> (Samba workgroup, optional)
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_samba-1.1", "keywords": ["samba", "proxmox"], "comment_type": "block"}
# Algorithm: Samba setup
# Installs Samba, configures user, sets up shares, restarts services
# Keywords: [samba, proxmox, shares]
# TODO: Validate Samba options and enhance share name derivation

# Source common functions and configuration
source /usr/local/bin/common.sh || { echo "[$(date)] Error: Failed to source common.sh" | tee -a /dev/stderr; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "[$(date)] Error: Failed to source phoenix_config.sh" | tee -a /dev/stderr; exit 1; }

# Load configuration
load_config

# Parse command-line arguments
# Metadata: {"chunk_id": "phoenix_setup_samba-1.2", "keywords": ["args"], "comment_type": "block"}
PASSWORD=""
NETWORK_NAME=""
while getopts "p:n:" opt; do
  case $opt in
    p) PASSWORD="$OPTARG" ;;
    n) NETWORK_NAME="$OPTARG" ;;
    \?) echo "[$(date)] Invalid option: -$OPTARG" | tee -a "${LOGFILE:-/dev/stderr}" >&2; exit 1 ;;
    :) echo "[$(date)] Option -$OPTARG requires an argument." | tee -a "${LOGFILE:-/dev/stderr}" >&2; exit 1 ;;
  esac
done

# Set defaults and validate inputs
# Metadata: {"chunk_id": "phoenix_setup_samba-1.3", "keywords": ["defaults", "validation"], "comment_type": "block"}
SMB_USER="${SMB_USER:-heads}"
SMB_PASSWORD="${SMB_PASSWORD:-Kick@$$2025}"
NETWORK_NAME="${NETWORK_NAME:-WORKGROUP}"
MOUNT_POINT_BASE="${MOUNT_POINT_BASE:-/mnt/pve}"

# Validate Samba user
if ! id "$SMB_USER" >/dev/null 2>&1; then
  echo "[$(date)] Error: System user $SMB_USER does not exist." | tee -a "${LOGFILE:-/dev/stderr}"
  exit 1
fi
echo "[$(date)] Verified that Samba user $SMB_USER exists" >> "${LOGFILE:-/dev/stderr}"

# Validate Samba password
if [[ ! "$SMB_PASSWORD" =~ ^.{8,}$ ]]; then
  echo "[$(date)] Error: Samba password must be at least 8 characters." | tee -a "${LOGFILE:-/dev/stderr}"
  exit 1
fi
if [[ ! "$SMB_PASSWORD" =~ [!@#$%^\&*] ]]; then
  echo "[$(date)] Error: Samba password must contain at least one special character (!@#$%^&*)." | tee -a "${LOGFILE:-/dev/stderr}"
  exit 1
fi
echo "[$(date)] Validated Samba password for user $SMB_USER" >> "${LOGFILE:-/dev/stderr}"

# Validate network name
if [[ ! "$NETWORK_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "[$(date)] Error: Network name must contain only letters, numbers, hyphens, or underscores." | tee -a "${LOGFILE:-/dev/stderr}"
  exit 1
fi
echo "[$(date)] Set Samba workgroup to $NETWORK_NAME" >> "${LOGFILE:-/dev/stderr}"

# install_samba: Installs Samba packages if not present
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_samba-1.4", "keywords": ["samba", "packages"], "comment_type": "block"}
# Algorithm: Samba package installation
# Checks and installs Samba if not present
# Keywords: [samba, packages]
# TODO: Add support for Samba version selection
install_samba() {
  if ! check_package samba; then
    retry_command "apt-get update" || {
      echo "[$(date)] Error: Failed to update package lists" | tee -a "${LOGFILE:-/dev/stderr}"
      exit 1
    }
    retry_command "apt-get install -y samba samba-common-bin smbclient" || {
      echo "[$(date)] Error: Failed to install Samba" | tee -a "${LOGFILE:-/dev/stderr}"
      exit 1
    }
    echo "[$(date)] Installed Samba" >> "${LOGFILE:-/dev/stderr}"
  else
    echo "[$(date)] Samba already installed, skipping installation" >> "${LOGFILE:-/dev/stderr}"
  fi
}

# configure_samba_user: Sets Samba password
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_samba-1.5", "keywords": ["samba", "user"], "comment_type": "block"}
# Algorithm: Samba user configuration
# Checks for existing Samba user, sets password
# Keywords: [samba, user]
configure_samba_user() {
  echo "[$(date)] Configuring Samba user: $SMB_USER" >> "${LOGFILE:-/dev/stderr}"
  if ! pdbedit -L | grep -q "^$SMB_USER:"; then
    echo -e "$SMB_PASSWORD\n$SMB_PASSWORD" | smbpasswd -s -a "$SMB_USER" || {
      echo "[$(date)] Error: Failed to set Samba password for $SMB_USER" | tee -a "${LOGFILE:-/dev/stderr}"
      exit 1
    }
    echo "[$(date)] Set Samba password for $SMB_USER" >> "${LOGFILE:-/dev/stderr}"
  else
    echo "[$(date)] Samba user $SMB_USER already exists, skipping password setup" >> "${LOGFILE:-/dev/stderr}"
  fi
}

# configure_samba_shares: Creates mount points for Samba shares
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_samba-1.6", "keywords": ["samba", "mount"], "comment_type": "block"}
# Algorithm: Samba mount point configuration
# Creates mount points for ZFS datasets, sets ownership and permissions
# Keywords: [samba, mount]
# TODO: Add validation for ZFS dataset existence
configure_samba_shares() {
  mkdir -p "$MOUNT_POINT_BASE" || {
    echo "[$(date)] Error: Failed to create $MOUNT_POINT_BASE" | tee -a "${LOGFILE:-/dev/stderr}"
    exit 1
  }
  local datasets=(
    "quickOS/shared-prod-data"
    "quickOS/shared-prod-data-sync"
    "fastData/shared-backups"
    "fastData/shared-test-data"
    "fastData/shared-iso"
    "fastData/shared-bulk-data"
    "fastData/shared-test-data-sync"
  )
  for dataset in "${datasets[@]}"; do
    local mountpoint="$MOUNT_POINT_BASE/$(basename "$dataset")"
    mkdir -p "$mountpoint" || {
      echo "[$(date)] Error: Failed to create $mountpoint" | tee -a "${LOGFILE:-/dev/stderr}"
      exit 1
    }
    if ! zfs list "$dataset" >/dev/null 2>&1; then
      echo "[$(date)] Error: ZFS dataset $dataset does not exist. Run phoenix_setup_zfs_datasets.sh to create it" | tee -a "${LOGFILE:-/dev/stderr}"
      zfs list -r "$(dirname "$dataset")" 2>&1 | tee -a "${LOGFILE:-/dev/stderr}"
      exit 1
    fi
    if ! mount | grep -q "$mountpoint"; then
      zfs set mountpoint="$mountpoint" "$dataset" || {
        echo "[$(date)] Error: Failed to set mountpoint for $dataset to $mountpoint" | tee -a "${LOGFILE:-/dev/stderr}"
        exit 1
      }
    fi
    chown "$SMB_USER:$SMB_USER" "$mountpoint" || {
      echo "[$(date)] Error: Failed to set ownership for $mountpoint" | tee -a "${LOGFILE:-/dev/stderr}"
      exit 1
    }
    chmod 770 "$mountpoint" || {
      echo "[$(date)] Error: Failed to set permissions for $mountpoint" | tee -a "${LOGFILE:-/dev/stderr}"
      exit 1
    }
    echo "[$(date)] Created and configured mountpoint $mountpoint for dataset $dataset" >> "${LOGFILE:-/dev/stderr}"
  done
}

# configure_samba_config: Configures Samba shares in smb.conf
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_samba-1.7", "keywords": ["samba", "config"], "comment_type": "block"}
# Algorithm: Samba configuration
# Backs up smb.conf, generates global section, configures shares for datasets
# Keywords: [samba, config]
configure_samba_config() {
  if [[ -f /etc/samba/smb.conf ]]; then
    cp /etc/samba/smb.conf "/etc/samba/smb.conf.bak.$(date +%F_%H-%M-%S)" || {
      echo "[$(date)] Error: Failed to back up /etc/samba/smb.conf" | tee -a "${LOGFILE:-/dev/stderr}"
      exit 1
    }
    echo "[$(date)] Backed up /etc/samba/smb.conf" >> "${LOGFILE:-/dev/stderr}"
  fi
  cat << EOF > /etc/samba/smb.conf
[global]
   workgroup = $NETWORK_NAME
   server string = %h Proxmox Samba Server
   security = user
   log file = /var/log/samba/log.%m
   max log size = 1000
   syslog = 0
   panic action = /usr/share/samba/panic-action %d
   server role = standalone server
   passdb backend = tdbsam
   obey pam restrictions = yes
   unix password sync = yes
   passwd program = /usr/bin/passwd %u
   passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
   pam password change = yes
   map to guest = bad user
   dns proxy = no

[shared-prod-data]
   path = $MOUNT_POINT_BASE/shared-prod-data
   writable = yes
   browsable = yes
   guest ok = no
   valid users = $SMB_USER
   create mask = 0770
   directory mask = 0770
   force create mode = 0770
   force directory mode = 0770

[shared-prod-data-sync]
   path = $MOUNT_POINT_BASE/shared-prod-data-sync
   writable = yes
   browsable = yes
   guest ok = no
   valid users = $SMB_USER
   create mask = 0770
   directory mask = 0770
   force create mode = 0770
   force directory mode = 0770

[shared-backups]
   path = $MOUNT_POINT_BASE/shared-backups
   writable = no
   browsable = yes
   guest ok = no
   valid users = $SMB_USER
   create mask = 0440
   directory mask = 0550

[shared-test-data]
   path = $MOUNT_POINT_BASE/shared-test-data
   writable = yes
   browsable = yes
   guest ok = no
   valid users = $SMB_USER
   create mask = 0770
   directory mask = 0770
   force create mode = 0770
   force directory mode = 0770

[shared-iso]
   path = $MOUNT_POINT_BASE/shared-iso
   writable = no
   browsable = yes
   guest ok = no
   valid users = $SMB_USER
   create mask = 0440
   directory mask = 0550

[shared-bulk-data]
   path = $MOUNT_POINT_BASE/shared-bulk-data
   writable = yes
   browsable = yes
   guest ok = no
   valid users = $SMB_USER
   create mask = 0770
   directory mask = 0770
   force create mode = 0770
   force directory mode = 0770

[shared-test-data-sync]
   path = $MOUNT_POINT_BASE/shared-test-data-sync
   writable = yes
   browsable = yes
   guest ok = no
   valid users = $SMB_USER
   create mask = 0770
   directory mask = 0770
   force create mode = 0770
   force directory mode = 0770
EOF
  echo "[$(date)] Configured Samba shares" >> "${LOGFILE:-/dev/stderr}"
}

# configure_samba_firewall: Configures firewall for Samba
# Args: None
# Returns: 0 on success, 1 on failure
# Metadata: {"chunk_id": "phoenix_setup_samba-1.8", "keywords": ["firewall", "samba"], "comment_type": "block"}
# Algorithm: Samba firewall configuration
# Configures ufw to allow Samba traffic
# Keywords: [firewall, samba]
configure_samba_firewall() {
  echo "[$(date)] Configuring firewall for Samba..." >> "${LOGFILE:-/dev/stderr}"
  local ports=("137/udp" "138/udp" "139/tcp" "445/tcp")
  local rules_needed=false
  for port in "${ports[@]}"; do
    if ! ufw status | grep -q "$port.*ALLOW"; then
      rules_needed=true
      break
    fi
  done
  if [[ "$rules_needed" == true ]]; then
    retry_command "ufw allow Samba" || {
      echo "[$(date)] Error: Failed to configure firewall for Samba" | tee -a "${LOGFILE:-/dev/stderr}"
      exit 1
    }
    for port in "${ports[@]}"; do
      retry_command "ufw allow $port" || {
        echo "[$(date)] Error: Failed to allow $port for Samba" | tee -a "${LOGFILE:-/dev/stderr}"
        exit 1
      }
    done
    echo "[$(date)] Updated firewall to allow Samba traffic" >> "${LOGFILE:-/dev/stderr}"
  else
    echo "[$(date)] Samba firewall rules already set, skipping" >> "${LOGFILE:-/dev/stderr}"
  fi
}

# Main execution
# Metadata: {"chunk_id": "phoenix_setup_samba-1.9", "keywords": ["execution"], "comment_type": "block"}
main() {
  setup_logging
  check_root
  install_samba
  configure_samba_user
  configure_samba_shares
  configure_samba_config
  retry_command "systemctl restart smbd nmbd" || {
    echo "[$(date)] Error: Failed to restart Samba services" | tee -a "${LOGFILE:-/dev/stderr}"
    exit 1
  }
  if ! systemctl is-active --quiet smbd || ! systemctl is-active --quiet nmbd; then
    echo "[$(date)] Error: Samba services are not active" | tee -a "${LOGFILE:-/dev/stderr}"
    exit 1
  fi
  echo "[$(date)] Restarted Samba services (smbd, nmbd)" >> "${LOGFILE:-/dev/stderr}"
  configure_samba_firewall
  echo "[$(date)] Successfully completed Samba setup" >> "${LOGFILE:-/dev/stderr}"
}

main
exit 0