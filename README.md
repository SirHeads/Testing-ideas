# Phoenix Hypervisor

The Phoenix Hypervisor is a sophisticated Infrastructure-as-Code (IaC) solution that orchestrates both LXC containers and QEMU VMs on a local Proxmox server. It provides a declarative, idempotent, and automated infrastructure that enables the rapid and repeatable deployment of complex AI/ML/DL environments.

## Table of Contents

- [Phoenix Hypervisor](#phoenix-hypervisor)
  - [Table of Contents](#table-of-contents)
  - [Architectural Principles](#architectural-principles)
  - [High-Level System Architecture](#high-level-system-architecture)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Configuration](#configuration)
  - [Usage](#usage)
    - [The `phoenix` CLI](#the-phoenix-cli)
    - [Examples](#examples)
  - [Contributing](#contributing)
  - [Support](#support)
  - [License](#license)

## Architectural Principles

The architectural principles guiding the Phoenix Hypervisor ensure a robust, efficient, and maintainable platform:

*   **Modularity and Reusability**: Components are designed as independent, interchangeable modules that can be easily integrated and reused across different parts of the system.
*   **Idempotency**: Operations and deployments are designed to produce the same result regardless of how many times they are executed, ensuring consistency and reliability.
*   **Declarative Configuration**: The desired state of the system is defined in a declarative manner, and the system is responsible for achieving that state.
*   **Configuration as Code**: Infrastructure and application configurations are managed as version-controlled code, enabling automated provisioning, consistent environments, and clear audit trails.
*   **Security by Design**: Security is integrated into the architecture from the ground up, rather than being an afterthought.
*   **Open-Source First**: Prioritize the adoption and integration of free and open-source software solutions to minimize costs and foster community collaboration.

## High-Level System Architecture

This diagram provides a comprehensive overview of the Phoenix Hypervisor ecosystem, including user interaction, orchestration, configuration management, and the virtualized resources.

```mermaid
graph TD
    subgraph "User"
        A[Developer/Admin]
    end

    subgraph "Phoenix Hypervisor (Proxmox Host)"
        B[phoenix CLI]
        C[Configuration Files]
        D[LXC Containers]
        E[Virtual Machines]
        F[Storage Pools]
        G[Networking]
    end

    subgraph "Configuration Files"
        C1[/etc/phoenix_hypervisor_config.json]
        C2[/etc/phoenix_lxc_configs.json]
        C3[/etc/phoenix_vm_configs.json]
    end

    A -- Manages --> B
    B -- Reads --> C1
    B -- Reads --> C2
    B -- Reads --> C3
    B -- Provisions/Manages --> D
    B -- Provisions/Manages --> E
    B -- Manages --> F
    B -- Configures --> G
```

## Prerequisites

Before you begin, ensure you have the following:

*   A Proxmox VE host.
*   Root access to the Proxmox host.
*   `git` installed on the Proxmox host.

## Installation

1.  **Clone the repository:**

    Log in to your Proxmox host as the `root` user and clone the repository into the `/usr/local` directory.

    ```bash
    git clone https://github.com/SirHeads/Testing-ideas.git /usr/local/phoenix_hypervisor
    ```

2.  **Set permissions:**

    Make the `phoenix` CLI executable.

    ```bash
    chmod +x /usr/local/phoenix_hypervisor/bin/phoenix
    ```

3.  **Initial Setup:**

    Run the `setup` command to initialize the hypervisor environment.

    ```bash
    /usr/local/phoenix_hypervisor/bin/phoenix setup
    ```

## Configuration

The Phoenix Hypervisor is configured through a set of JSON files located in `/usr/local/phoenix_hypervisor/etc`:

*   `phoenix_hypervisor_config.json`: The main configuration file for the hypervisor, including network settings, storage pools, and user accounts.
*   `phoenix_lxc_configs.json`: Defines the configuration for all LXC containers, including their resources, features, and dependencies.
*   `phoenix_vm_configs.json`: Defines the configuration for all QEMU virtual machines.

## Usage

### The `phoenix` CLI

The `phoenix` CLI is the primary tool for managing the Phoenix Hypervisor. It provides a simple, verb-first interface for all operations.

| Command | Description |
| :--- | :--- |
| `phoenix LetsGo` | **Master Command:** Creates and starts all defined guests. |
| `phoenix create <ID...>` | Creates one or more guests, automatically resolving dependencies. |
| `phoenix delete <ID...>` | Deletes the specified guest(s). |
| `phoenix start <ID...>` | Starts the specified guest(s), respecting boot order. |
| `phoenix stop <ID...>` | Stops the specified guest(s). |
| `phoenix test <ID> [--suite <name>]` | Runs a test suite against a specific guest. |
| `phoenix setup` | **Special Case:** Initializes or configures the hypervisor. |

### Examples

*   **Create a single container:**

    ```bash
    /usr/local/phoenix_hypervisor/bin/phoenix create 950
    ```

*   **Start multiple containers:**

    ```bash
    /usr/local/phoenix_hypervisor/bin/phoenix start 950 953
    ```

*   **Bring the entire environment online:**

    ```bash
    /usr/local/phoenix_hypervisor/bin/phoenix LetsGo
    ```

## Contributing

Contributions are welcome! Please refer to the contributing guidelines for more information.

## Support

If you encounter any issues or have any questions, please open an issue on the GitHub repository.

## License

This project is licensed under the MIT License.