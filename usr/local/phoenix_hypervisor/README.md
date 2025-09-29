# Phoenix Hypervisor

The Phoenix Hypervisor is a sophisticated, automated system for provisioning Proxmox LXC containers and Virtual Machines (VMs). It leverages a combination of shell scripts and JSON configuration files to create a stateless, idempotent, and highly customizable deployment pipeline.

## Core Architecture

The Phoenix Hypervisor project is built on a foundation of modern infrastructure-as-code (IaC) principles. It is designed to be a resilient, predictable, and auditable platform for all future development.

### Key Features

*   **Unified Orchestration**: The `phoenix_orchestrator.sh` script provides a single, unified interface for managing the complete lifecycle of both LXC containers and QEMU/KVM virtual machines.
*   **Stateless and Idempotent**: The orchestrator is designed to be stateless, ensuring resilient and repeatable deployments. It can be run multiple times without causing unintended side effects.
*   **Hierarchical Templating**: A multi-layered, snapshot-based templating strategy for both VMs and LXCs minimizes duplication and ensures a consistent foundation for all virtualized environments.
*   **Modular Feature Installation**: A modular design allows for the easy addition and modification of features like Docker, NVIDIA drivers, and vLLM to both containers and VMs.
*   **Centralized Configuration**: All hypervisor, VM, and LXC definitions are managed in well-structured JSON files (`phoenix_hypervisor_config.json`, `phoenix_vm_configs.json`, `phoenix_lxc_configs.json`), providing a single source of truth.
*   **Cloud-Init Integration**: VMs are provisioned using cloud-init for robust, automated configuration on first boot.
*   **Health Checks**: The framework includes scripts to monitor the status of containers, VMs, and their services.

## Getting Started

To get started with the Phoenix Hypervisor, you will need to have a Proxmox VE environment set up and configured. Once you have a Proxmox host up and running, you can clone this repository and begin using the `phoenix_orchestrator.sh` script to provision and manage your virtualized infrastructure.

### Prerequisites

*   Proxmox VE 7.x or later
*   A user with sudo privileges on the Proxmox host
*   Git and `jq` installed on the Proxmox host

### Installation

1.  Clone this repository to your Proxmox host:

    ```bash
    git clone https://github.com/thinkheads-ai/phoenix_hypervisor.git /usr/local/phoenix_hypervisor
    ```

2.  Navigate to the `bin` directory:

    ```bash
    cd /usr/local/phoenix_hypervisor/bin
    ```

3.  Run the `phoenix_orchestrator.sh` script with the `--setup-hypervisor` flag to configure the Proxmox host:

    ```bash
    ./phoenix_orchestrator.sh --setup-hypervisor
    ```

### Usage

Once the hypervisor is set up, you can use the `phoenix_orchestrator.sh` script to provision and manage your containers and VMs using a single, unified command.

*   **Create or Update a VM or LXC Container:**

    ```bash
    ./phoenix_orchestrator.sh <ID>
    ```
    Where `<ID>` is the `vmid` from `phoenix_vm_configs.json` or the `ctid` from `phoenix_lxc_configs.json`.

*   **Run Health Checks for a Container:**

    ```bash
    ./phoenix_orchestrator.sh --health-check <CTID>
    ```

## Documentation

For more detailed information about the Phoenix Hypervisor, please refer to the documentation in the `Thinkheads.AI_docs` directory.

## Contributing

Contributions to the Phoenix Hypervisor project are welcome. If you would like to contribute, please fork the repository and submit a pull request.

## License

The Phoenix Hypervisor project is licensed under the MIT License.
