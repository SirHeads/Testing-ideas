# Phoenix Hypervisor Documentation Update Plan

This document outlines the plan for updating the Phoenix Hypervisor documentation. The goal is to address outdated information, resolve inconsistencies, fill in missing documentation, and enhance the overall structure and accessibility of the documentation.

## 1. Outdated Information

The following files have been identified as containing outdated information. They will be updated to reflect the current state of the Phoenix Hypervisor project.

*   **File:** `usr/local/phoenix_hypervisor/README.md`
    *   **Required Changes:** The README needs to be updated to include the latest features, installation instructions, and usage examples. The current version is missing details about the vLLM integration and the new health check scripts.
*   **File:** `Thinkheads.AI_docs/03_phoenix_hypervisor_implementation/00_guides/00_getting_started.md`
    *   **Required Changes:** This guide needs to be updated to reflect the new declarative architecture and the refactored LXC container management scripts.
*   **File:** `Thinkheads.AI_docs/02_technical_strategy_and_architecture/03_phoenix_hypervisor_strategy.md`
    *   **Required Changes:** This document should be updated to align with the latest implementation details, particularly regarding the unified AppArmor nesting strategy and Docker-LXC integration.

## 2. Inconsistencies

The following inconsistencies have been identified across the documentation. These will be corrected to ensure a single source of truth.

*   **Conflict:** The `phoenix_lxc_configs.json` and the documentation in `Thinkheads.AI_docs/03_phoenix_hypervisor_implementation/00_guides/02_lxc_container_implementation_guide.md` have conflicting information about the default container configurations.
    *   **Resolution:** The guide will be updated to match the schema and default values defined in `phoenix_lxc_configs.json`.
*   **Conflict:** Naming conventions for scripts and configuration files are inconsistent between the `bin` directory and the documentation.
    *   **Resolution:** A consistent naming convention will be established and applied across all documentation and code examples.

## 3. Missing Documentation

The following documentation is missing and will be created.

*   **New Document:** `Thinkheads.AI_docs/03_phoenix_hypervisor_implementation/00_guides/12_monitoring_and_logging_guide.md`
    *   **Outline:**
        *   Introduction to monitoring in the Phoenix Hypervisor.
        *   How to use the `health_check` scripts.
        *   Configuration of logging for containers and services.
        *   Integration with external monitoring tools.
*   **New Document:** `Thinkheads.AI_docs/03_phoenix_hypervisor_implementation/02_api_reference/00_rest_api.md`
    *   **Outline:**
        *   Overview of the Phoenix Hypervisor API.
        *   Endpoint documentation for managing containers, VMs, and services.
        *   Authentication and authorization.
        *   Example API requests and responses.

## 4. Enhancements

The following enhancements will be made to improve the documentation's structure and accessibility.

*   **Improvement:** Create a central landing page for all Phoenix Hypervisor documentation within `Thinkheads.AI_docs`.
    *   **Description:** This page will provide a clear overview of the documentation structure and links to all major sections, guides, and references.
*   **Improvement:** Add Mermaid diagrams to illustrate complex workflows and architectures.
    *   **Description:** Diagrams will be added to documents like `00_system_architecture_guide.md` and `01_declarative_architecture_guide.md` to visually represent the system's components and their interactions.
*   **Improvement:** Implement a versioning strategy for the documentation.
    *   **Description:** This will ensure that users can access documentation that corresponds to specific releases of the Phoenix Hypervisor.