# Initial Analysis of Phoenix Scripts

This document provides an initial analysis of the shell scripts located in the `phoenix-scripts` directory. The purpose of this analysis is to understand the current architecture and workflow of these scripts to inform a future refactoring effort.

## Script-by-Script Analysis

### `create_phoenix.sh`

*   **Purpose:** This is the main orchestration script. It is responsible for executing all other scripts in the correct order to set up the Proxmox server.
*   **Functionality:**
    *   Sources `common.sh` and `phoenix_config.sh`.
    *   Prompts the user for credentials and drive selections.
    *   Executes the setup scripts in a predefined order.
    *   Maintains a state file to track completed scripts and allow for re-running failed setups.
    *   Runs the `phoenix_fly.sh` animation upon successful completion.
    *   Initiates a reboot after the setup is complete.

### `phoenix_fly.sh`

*   **Purpose:** This script displays a Phoenix animation in the terminal.
*   **Functionality:**
    *   Displays a text-based animation of a phoenix flying across the screen.
    *   Can display an optional message after the animation.

### `common.sh`

*   **Purpose:** This script contains shared functions used by the other setup scripts.
*   **Functionality:**
    *   Provides functions for logging, checking for root privileges, checking for installed packages, and network connectivity.
    *   Includes helper functions for creating ZFS datasets, setting ZFS properties, and configuring NFS exports.
    *   Contains a `retry_command` function to execute a command with retries on failure.

### `phoenix_config.sh`

*   **Purpose:** This script contains all the configuration variables for the Proxmox setup.
*   **Functionality:**
    *   Defines variables for ZFS pools, datasets, storage, network settings, and Samba configuration.
    *   The `load_config` function is called by other scripts to load these variables into the environment.

### `phoenix_proxmox_initial_setup.sh`

*   **Purpose:** This script performs the initial setup of the Proxmox VE environment.
*   **Functionality:**
    *   Configures APT repositories.
    *   Updates and upgrades the system.
    *   Installs essential packages like `jq` and `s-tui`.
    *   Sets the timezone and configures NTP.
    *   Prompts for and configures network settings.
    *   Configures the firewall with `ufw`.

### `phoenix_install_nvidia_driver.sh`

*   **Purpose:** This script installs the NVIDIA drivers on the Proxmox host.
*   **Functionality:**
    *   Detects if an NVIDIA GPU is present.
    *   Blacklists the nouveau driver.
    *   Downloads and installs the specified NVIDIA driver.
    *   Verifies the installation using `nvidia-smi`.
    *   Installs `nvtop`.
    *   Prompts for a reboot after installation.

### `phoenix_create_admin_user.sh`

*   **Purpose:** This script creates a system and Proxmox VE admin user.
*   **Functionality:**
    *   Creates a new system user with sudo privileges.
    *   Creates a corresponding Proxmox VE user with the Administrator role.
    *   Optionally configures an SSH key for the new user.

### `phoenix_setup_zfs_pools.sh`

*   **Purpose:** This script creates the ZFS pools.
*   **Functionality:**
    *   Wipes the selected drives.
    *   Creates a mirrored ZFS pool named `quickOS`.
    *   Creates a single-drive ZFS pool named `fastData`.
    *   Monitors NVMe drive wear.
    *   Sets the ZFS ARC max size.

### `phoenix_setup_zfs_datasets.sh`

*   **Purpose:** This script creates the ZFS datasets within the pools.
*   **Functionality:**
    *   Creates the datasets for the `quickOS` and `fastData` pools as defined in `phoenix_config.sh`.
    *   Sets the properties for each dataset.
    *   Adds the datasets as Proxmox storage.

### `phoenix_create_storage.sh`

*   **Purpose:** This script creates the Proxmox VE storage definitions for the ZFS datasets.
*   **Functionality:**
    *   Iterates through the configured datasets.
    *   Creates either ZFS or directory-based storage in Proxmox based on the configuration.

### `phoenix_setup_nfs.sh`

*   **Purpose:** This script configures the NFS server.
*   **Functionality:**
    *   Installs NFS packages.
    *   Configures NFS exports for the specified ZFS datasets.
    *   Configures the firewall for NFS.
    *   Adds the NFS shares as storage in Proxmox.

### `phoenix_setup_samba.sh`

*   **Purpose:** This script configures the Samba server.
*   **Functionality:**
    *   Installs Samba packages.
    *   Configures a Samba user.
    *   Creates Samba shares for the specified ZFS datasets.
    *   Configures the firewall for Samba.

## End-to-End Workflow

The scripts are designed to be run in a specific sequence, orchestrated by `create_phoenix.sh`. The high-level workflow is as follows:

1.  **Execution Start:** The process begins by running `create_phoenix.sh`.
2.  **Configuration and Initialization:**
    *   The script sources `common.sh` for shared functions and `phoenix_config.sh` for all configuration variables.
    *   It prompts the user for necessary credentials (admin user, SMB password) and for the selection of NVMe drives for the ZFS pools.
3.  **System Setup:**
    *   `phoenix_proxmox_initial_setup.sh`: Performs the base setup of the Proxmox host, including repository configuration, system updates, network configuration, and basic firewall rules.
    *   `phoenix_install_nvidia_driver.sh`: Installs the NVIDIA drivers if a compatible GPU is detected.
    *   `phoenix_create_admin_user.sh`: Creates a new administrative user on the system and in Proxmox.
4.  **Storage Configuration:**
    *   `phoenix_setup_zfs_pools.sh`: Creates the `quickOS` (mirrored) and `fastData` (single drive) ZFS pools from the user-selected drives.
    *   `phoenix_setup_zfs_datasets.sh`: Creates the various ZFS datasets on the newly created pools, setting properties like record size, compression, and quotas.
    *   `phoenix_create_storage.sh`: Registers the ZFS datasets as storage resources within Proxmox, making them available for VMs and containers.
5.  **Network Services:**
    *   `phoenix_setup_nfs.sh`: Configures and starts an NFS server, exporting specific datasets for network access.
    *   `phoenix_setup_samba.sh`: Configures and starts a Samba server, creating shares for the specified datasets.
6.  **Finalization:**
    *   `phoenix_fly.sh`: After all scripts have executed successfully, this script is run to display a completion animation.
    *   **Reboot:** The system is rebooted to ensure all changes are applied correctly.

The entire process is designed to be idempotent, meaning it can be re-run without causing issues if it was interrupted. This is managed through a state file that tracks which scripts have been completed successfully.

### Mermaid Diagram of the Workflow

```mermaid
graph TD
    A[Start: Run create_phoenix.sh] --> B{Prompt for Credentials & Drives};
    B --> C[phoenix_proxmox_initial_setup.sh];
    C --> D[phoenix_install_nvidia_driver.sh];
    D --> E[phoenix_create_admin_user.sh];
    E --> F[phoenix_setup_zfs_pools.sh];
    F --> G[phoenix_setup_zfs_datasets.sh];
    G --> H[phoenix_create_storage.sh];
    H --> I[phoenix_setup_nfs.sh];
    I --> J[phoenix_setup_samba.sh];
    J --> K[phoenix_fly.sh];
    K --> L[Reboot];