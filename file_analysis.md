# Phoenix Hypervisor File Analysis

This document provides a comprehensive analysis of the files within the `usr/local/phoenix_hypervisor/` directory. The purpose of this analysis is to categorize all files, provide a clear description of their function, and identify any files that are no longer in use and can be safely removed.

## 1. Core Orchestration

This category includes the primary scripts responsible for orchestrating the entire Phoenix Hypervisor ecosystem.

*   **`bin/phoenix-cli`**: The main entry point for the Phoenix Hypervisor CLI. This script parses user commands and dispatches them to the appropriate manager scripts.
*   **`bin/phoenix-global`**: A wrapper script that allows the `phoenix-cli` command to be called from any directory.
*   **`bin/managers/hypervisor-manager.sh`**: Manages all hypervisor-level operations, including initial setup, ZFS configuration, and network setup.
*   **`bin/managers/lxc-manager.sh`**: Manages the entire lifecycle of LXC containers, from creation and configuration to feature application and snapshotting.
*   **`bin/managers/vm-manager.sh`**: Manages the lifecycle of virtual machines, including creation, configuration, and feature application.
*   **`bin/managers/portainer-manager.sh`**: Manages all Portainer-related operations, including the deployment of Portainer server and agents, and the synchronization of Docker stacks.
*   **`bin/phoenix_hypervisor_common_utils.sh`**: A library of shared shell functions used by all other scripts for logging, error handling, and configuration management.

## 2. Configuration Files

These files define the declarative state of the entire system.

*   **`etc/phoenix_hypervisor_config.json`**: Defines global settings for the Proxmox environment, including networking, storage, users, and hypervisor-level features.
*   **`etc/phoenix_lxc_configs.json`**: Provides detailed configurations for each LXC container, specifying resources, features, and security policies.
*   **`etc/phoenix_vm_configs.json`**: Defines the configurations for virtual machines, including resources, features, and Docker stack assignments.
*   **`etc/phoenix_stacks_config.json`**: Defines reusable, declarative Docker stacks for use with Portainer.
*   **`etc/phoenix_hypervisor_config.schema.json`**: JSON schema for `phoenix_hypervisor_config.json`.
*   **`etc/phoenix_lxc_configs.schema.json`**: JSON schema for `phoenix_lxc_configs.json`.
*   **`etc/phoenix_vm_configs.schema.json`**: JSON schema for `phoenix_vm_configs.json`.
*   **`etc/phoenix_stacks_config.schema.json`**: JSON schema for `phoenix_stacks_config.json`.

## 3. Hypervisor Setup Scripts

These scripts are executed by the `hypervisor-manager.sh` to configure the Proxmox host.

*   **`bin/hypervisor_setup/hypervisor_initial_setup.sh`**: Performs initial system setup, including package installation and user creation.
*   **`bin/hypervisor_setup/hypervisor_feature_setup_zfs.sh`**: Configures ZFS storage pools and datasets.
*   **`bin/hypervisor_setup/hypervisor_feature_configure_vfio.sh`**: Configures VFIO for GPU passthrough.
*   **`bin/hypervisor_setup/hypervisor_feature_install_nvidia.sh`**: Installs NVIDIA drivers on the hypervisor.
*   **`bin/hypervisor_setup/hypervisor_feature_initialize_nvidia_gpus.sh`**: Initializes NVIDIA GPUs for use with VMs and containers.
*   **`bin/hypervisor_setup/hypervisor_feature_setup_firewall.sh`**: Configures the Proxmox firewall.
*   **`bin/hypervisor_setup/hypervisor_feature_setup_nfs.sh`**: Configures NFS shares for use with VMs and containers.
*   **`bin/hypervisor_setup/hypervisor_feature_create_heads_user.sh`**: Creates the 'heads' user account.
*   **`bin/hypervisor_setup/hypervisor_feature_setup_samba.sh`**: Configures Samba shares.
*   **`bin/hypervisor_setup/hypervisor_feature_create_admin_user.sh`**: Creates the 'phoenix_admin' user account.
*   **`bin/hypervisor_setup/hypervisor_feature_provision_shared_resources.sh`**: Provisions shared resources, such as storage directories.
*   **`bin/hypervisor_setup/hypervisor_feature_setup_apparmor.sh`**: Sets up AppArmor profiles for LXC containers.
*   **`bin/hypervisor_setup/hypervisor_feature_fix_apparmor_tunables.sh`**: Applies fixes to AppArmor tunables.
*   **`bin/hypervisor_setup/provision_cloud_template.sh`**: Provisions a cloud template for use with VMs.

## 4. LXC Feature Scripts

These scripts are executed by the `lxc-manager.sh` to install and configure features within LXC containers.

*   **`bin/lxc_setup/phoenix_hypervisor_feature_install_base_setup.sh`**: Performs basic setup within an LXC container.
*   **`bin/lxc_setup/phoenix_hypervisor_feature_install_dns_server.sh`**: Installs and configures a DNS server (dnsmasq).
*   **`bin/lxc_setup/phoenix_hypervisor_feature_install_docker.sh`**: Installs Docker within an LXC container (deprecated).
*   **`bin/lxc_setup/phoenix_hypervisor_feature_install_nat_gateway.sh`**: Configures the container as a NAT gateway.
*   **`bin/lxc_setup/phoenix_hypervisor_feature_install_nvidia.sh`**: Installs NVIDIA drivers within an LXC container.
*   **`bin/lxc_setup/phoenix_hypervisor_feature_install_ollama.sh`**: Installs Ollama within an LXC container.
*   **`bin/lxc_setup/phoenix_hypervisor_feature_install_portainer.sh`**: Installs the Portainer agent within an LXC container.
*   **`bin/lxc_setup/phoenix_hypervisor_feature_install_python_api_service.sh`**: Installs a Python API service.
*   **`bin/lxc_setup/phoenix_hypervisor_feature_install_step_ca.sh`**: Installs the Smallstep Step-CA.
*   **`bin/lxc_setup/phoenix_hypervisor_feature_install_traefik.sh`**: Installs Traefik.
*   **`bin/lxc_setup/phoenix_hypervisor_feature_install_trusted_ca.sh`**: Installs the root CA certificate into the container's trust store.
*   **`bin/lxc_setup/phoenix_hypervisor_feature_install_vllm.sh`**: Installs vLLM.

## 5. VM Feature Scripts

These scripts are executed by the `vm-manager.sh` to install and configure features within virtual machines.

*   **`bin/vm_features/feature_install_base_setup.sh`**: Performs basic setup within a VM.
*   **`bin/vm_features/feature_install_docker.sh`**: Installs Docker within a VM.
*   **`bin/vm_features/feature_install_trusted_ca.sh`**: Installs the root CA certificate into the VM's trust store.
*   **`bin/vm_features/feature_template.sh`**: A template for creating new VM feature scripts.

## 6. Application Scripts

These scripts are executed within containers to perform application-specific setup.

*   **`bin/phoenix_hypervisor_lxc_101.sh`**: Configures the Nginx gateway in container 101.
*   **`bin/phoenix_hypervisor_lxc_102.sh`**: Configures the Traefik internal proxy in container 102.
*   **`bin/phoenix_hypervisor_lxc_103.sh`**: Configures the Smallstep Step-CA in container 103.
*   **`bin/phoenix_hypervisor_lxc_vllm.sh`**: Configures and starts the vLLM service.

## 7. Health Checks

These scripts are used to verify the health of various services.

*   **`bin/health_checks/check_n8n.sh`**: Checks the health of the n8n service.
*   **`bin/health_checks/check_nvidia.sh`**: Checks the health of the NVIDIA drivers.
*   **`bin/health_checks/check_ollama.sh`**: Checks the health of the Ollama service.
*   **`bin/health_checks/check_portainer_api.sh`**: Checks the health of the Portainer API.
*   **`bin/health_checks/check_portainer.sh`**: Checks the health of the Portainer service.
*   **`bin/health_checks/check_qdrant.sh`**: Checks the health of the Qdrant service.
*   **`bin/health_checks/check_service_status.sh`**: A generic script to check the status of a systemd service.
*   **`bin/health_checks/check_vllm.sh`**: Checks the health of the vLLM service.

## 8. Testing Scripts

These scripts are used for testing various components of the Phoenix Hypervisor system.

*   **`bin/tests/test_runner.sh`**: The main test runner script.
*   **`bin/tests/hypervisor_manager_test_runner.sh`**: Test runner for the hypervisor manager.
*   **`bin/tests/lxc_manager_test_runner.sh`**: Test runner for the LXC manager.
*   **`bin/tests/vm_manager_test_runner.sh`**: Test runner for the VM manager.
*   **`bin/tests/docker/*`**: A collection of tests for Docker functionality.
*   **`bin/tests/health_checks/*`**: Dummy health checks for testing purposes.
*   **`bin/tests/hypervisor/*`**: Tests for the hypervisor itself.
*   **`bin/tests/hypervisor_manager/*`**: Tests for the hypervisor manager.
*   **`bin/tests/lxc_manager/*`**: Tests for the LXC manager.
*   **`bin/tests/vllm/*`**: Tests for vLLM functionality.
*   **`bin/tests/vm_manager/*`**: Tests for the VM manager.

## 9. Obsolete and Unused Files

This section lists files that appear to be obsolete or unused and are recommended for removal.

*   **`bin/phoenix_orchestrator.sh`**: This script appears to be an older version of the `phoenix-cli` dispatcher. Its functionality has been superseded by `phoenix-cli`.
*   **`bin/update_lxc_features.py`**: This Python script appears to be an older, imperative method for updating LXC features. The current declarative model managed by `lxc-manager.sh` makes this script obsolete.
*   **`bin/verify_container_health.sh`**: This script's functionality is now handled by the more specific health check scripts in the `bin/health_checks/` directory.
*   **`bin/health_check_952.sh`**: This appears to be a container-specific health check that has been replaced by the generic health check system.
*   **`bin/phoenix_hypervisor_lxc_952.sh`**: This and the other `phoenix_hypervisor_lxc_9xx.sh` scripts appear to be older, container-specific application scripts that have been replaced by the more modular feature and application script system.
*   **`bin/phoenix_hypervisor_lxc_954.sh`**
*   **`bin/phoenix_hypervisor_lxc_955.sh`**
*   **`bin/phoenix_hypervisor_lxc_956.sh`**
*   **`bin/phoenix_hypervisor_lxc_957.sh`**
*   **`bin/phoenix_hypervisor_lxc_960.sh`**
*   **`bin/health_checks/health_check_950.sh`**
*   **`etc/hypervisor_config.schema.json`**: This appears to be an older version of the `phoenix_hypervisor_config.schema.json` file.
*   **`src/rag-api-service/*`**: These files appear to be related to a RAG API service that is not currently integrated into the main Phoenix Hypervisor system. They may be part of a future feature, but for now, they are unused.
