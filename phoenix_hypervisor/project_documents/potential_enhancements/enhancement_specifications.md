---
title: "Phoenix Hypervisor Enhancement Specifications"
tags: ["Phoenix Hypervisor", "Enhancements", "Specifications", "Dynamic IP Address Management", "Secret Management", "Advanced Configuration Validation", "Expanded Feature Library", "Proxmox SDN", "AWS Secrets Manager", "Bash Scripting"]
summary: "This document outlines the specifications for proposed enhancements to the Phoenix Hypervisor project, including dynamic IP address management, secret management, advanced configuration validation, and an expanded feature library."
version: "1.0.0"
author: "Phoenix Hypervisor Team"
---

This document outlines the specifications for proposed enhancements to the Phoenix Hypervisor project, based on recent investigation reports.

---

## 1. Dynamic IP Address Management

### Summary
This enhancement proposes leveraging Proxmox VE's built-in Software-Defined Networking (SDN) capabilities to manage IP addresses for LXC containers dynamically. This approach eliminates the need for manual static IP assignment, streamlining container provisioning and reducing configuration overhead.

### Recommended Solution
Utilize Proxmox VE's integrated SDN with IPAM (IP Address Management) and DHCP services. This is a native solution that minimizes complexity and avoids reliance on external tools.

### High-Level Requirements
- Configure a dedicated SDN Zone, VNet, and Subnet within Proxmox VE.
- Enable the Proxmox DHCP server on the configured subnet.
- Modify the container creation logic to allow the DHCP service to assign IP addresses automatically.
- Ensure that container hostnames are correctly registered and resolvable.

### Implementation Specifications
- **File to Modify:** `phoenix_orchestrator.sh`
- **Change:** The `pct create` command within the script must be updated to remove the static IP address assignment (`--net0`). The network interface should be configured to use the VNet created in Proxmox, which will have an active DHCP server.
- **Proxmox Configuration:**
    1.  Create an SDN Zone (e.g., `phoenix-zone`).
    2.  Create a VNet (e.g., `phoenix-vnet`) linked to the zone and a physical bridge (e.g., `vmbr0`).
    3.  Create a Subnet within the VNet, defining the IP range and gateway.
    4.  Enable the DHCP server for the created subnet.

---

## 2. Secret Management

### Summary
This enhancement proposes integrating a dedicated secrets management solution to securely store and retrieve sensitive information, such as API keys, database credentials, and certificates.

### Recommended Solution
Use **AWS Secrets Manager**. As a fully managed service, it reduces the operational overhead associated with self-hosted solutions like HashiCorp Vault and is well-suited for projects that may leverage other AWS services.

### High-Level Requirements
- Establish a secure method for the Phoenix Hypervisor environment to authenticate with AWS.
- Create a centralized location for storing secrets in AWS Secrets Manager.
- Implement a mechanism within the orchestration scripts to fetch secrets at runtime.
- Ensure that access to secrets is governed by the principle of least privilege.

### Implementation Specifications
- **File to Modify:** `phoenix_orchestrator.sh` (and potentially a new utility script).
- **Change:**
    1.  Incorporate the AWS CLI or SDK to provide a function for retrieving secrets.
    2.  Replace hardcoded secrets or insecure variables with calls to this new function.
    3.  Authentication should be handled via IAM roles or instance profiles for security.
- **AWS Configuration:**
    1.  Create secrets within AWS Secrets Manager, organized with a consistent naming convention (e.g., `phoenix/prod/db_password`).
    2.  Define an IAM policy that grants read-only access to the specific secrets required by the hypervisor.
    3.  Attach this policy to the IAM role or user that the hypervisor will use to authenticate.

---

## 3. Advanced Configuration Validation

### Summary
This enhancement proposes adding a robust validation layer to check for logical errors in the LXC configuration files (`phoenix_lxc_configs.json`) before provisioning begins. This will prevent common misconfigurations and provide immediate, actionable feedback.

### Recommended Solution
Implement a new Bash function, `validate_lxc_config_logic`, within the existing `phoenix_orchestrator.sh` script. This leverages the current infrastructure (Bash, `jq`, logging) and avoids introducing new dependencies.

### High-Level Requirements
- The validation function must be executed before any container creation (`pct create`) commands.
- It must check for logical inconsistencies (e.g., requesting GPU resources on a non-GPU node).
- Error messages must be clear, logged, and cause the script to exit gracefully.
- The function should be easily extensible to accommodate future validation checks.

### Implementation Specifications
- **File to Modify:** `phoenix_orchestrator.sh`
- **Change:**
    1.  Create a new Bash function named `validate_lxc_config_logic`.
    2.  This function will use `jq` to parse `phoenix_lxc_configs.json` and perform checks.
    3.  Initial checks should include:
        - Verifying that `memory` and `swap` values are numeric and reasonable.
        - Ensuring that `storage` requests do not exceed available pool capacity.
        - Cross-referencing feature requests with a list of available features.
    4.  Integrate this function into the main execution flow of the script, immediately after the configuration file is read.

---

## 4. Expanded Feature Library

### Summary
This enhancement proposes creating a formal, extensible feature library to standardize the process of adding new capabilities (e.g., databases, web servers) to LXC containers.

### Recommended Solution
Adopt a phased approach, starting with the creation of a dedicated directory structure and migrating existing features. This will be followed by the gradual addition of new, high-value features, supported by a documented contribution workflow.

### High-Level Requirements
- Create a standardized directory structure for housing feature installation scripts.
- Migrate all existing feature installation logic into this new structure.
- Develop a clear and documented process for contributing new features.
- Implement CI/CD checks to validate new feature submissions.
- Gradually expand the library with new features like Nginx, PostgreSQL, and Redis.

### Implementation Specifications
- **New Directory Structure:**
    - `phoenix_hypervisor/features/`
        - `nginx/`
            - `install.sh`
            - `README.md`
        - `postgresql/`
            - `install.sh`
            - `README.md`
        - `redis/`
            - `install.sh`
            - `README.md`
- **File to Modify:** `phoenix_orchestrator.sh`
- **Change:**
    1.  Refactor the script to dynamically source and execute the `install.sh` script for each feature requested in the LXC configuration.
    2.  The script should iterate through the `features` array in the JSON config and call the corresponding script from the `phoenix_hypervisor/features/` directory.
- **Documentation:**
    - Create a `CONTRIBUTING.md` file within the `features` directory that outlines the standards for new feature scripts, including required variables, logging standards, and testing procedures.