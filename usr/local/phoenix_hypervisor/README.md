# Phoenix Hypervisor

The Phoenix Hypervisor is a sophisticated, automated system for provisioning Proxmox LXC containers and Virtual Machines (VMs). It leverages a combination of shell scripts and JSON configuration files to create a stateless, idempotent, and highly customizable deployment pipeline.

## Core Architecture

The Phoenix Hypervisor project is built on a foundation of modern infrastructure-as-code (IaC) principles. It is designed to be a resilient, predictable, and auditable platform for all future development.

### Key Features

*   **Stateless Orchestration**: The `phoenix_orchestrator.sh` script is designed to be stateless and idempotent, ensuring resilient and repeatable deployments.
*   **Hierarchical Templates and Cloning**: A multi-layered templating strategy minimizes duplication and ensures a consistent foundation for all virtualized environments.
*   **Modular Feature Installation**: A modular design allows for easy addition and modification of features like Docker, NVIDIA drivers, and vLLM.
*   **Centralized Configuration**: All container definitions and global settings are managed in well-structured JSON files, providing a single source of truth.
*   **Container-Native Execution**: Application scripts are executed using container-native commands, enhancing portability and reducing host dependencies.
*   **Dynamic NGINX Configuration**: The NGINX gateway configuration is generated dynamically, ensuring it remains in sync with container configurations.

## Getting Started

To get started with the Phoenix Hypervisor, you will need to have a Proxmox VE environment set up and configured. Once you have a Proxmox host up and running, you can clone this repository and begin using the `phoenix_orchestrator.sh` script to provision and manage your containers and VMs.

### Prerequisites

*   Proxmox VE 7.x or later
*   A user with sudo privileges on the Proxmox host
*   Access to the Proxmox API

### Installation

1.  Clone this repository to your Proxmox host:

    ```bash
    git clone https://github.com/your-username/phoenix_hypervisor.git
    ```

2.  Navigate to the `bin` directory:

    ```bash
    cd phoenix_hypervisor/bin
    ```

3.  Run the `phoenix_orchestrator.sh` script with the `--setup-hypervisor` flag to configure the Proxmox host:

    ```bash
    ./phoenix_orchestrator.sh --setup-hypervisor
    ```

### Usage

Once the hypervisor is set up, you can use the `phoenix_orchestrator.sh` script to provision and manage your containers and VMs. For example, to create a new container, you would run the following command:

```bash
./phoenix_orchestrator.sh CTID
```

Where `CTID` is the ID of the container you want to create.

## Documentation

For more detailed information about the Phoenix Hypervisor, please refer to the following documents:

*   [Phoenix Hypervisor Unified Architecture](project_documents/phoenix-hypervisor-architecture.md)
*   [Unified Phoenix Hypervisor Strategy v2.0](project_documents/unified_phoenix_hypervisor_strategy_v2.md)
*   [LXC Container Environment: An Overview](project_documents/lxc-container-environment-overview.md)
*   [Phoenix Orchestrator: A Deep Dive](project_documents/orchestrator-deep-dive.md)

## Contributing

Contributions to the Phoenix Hypervisor project are welcome. If you would like to contribute, please fork the repository and submit a pull request.

## License

The Phoenix Hypervisor project is licensed under the MIT License.
