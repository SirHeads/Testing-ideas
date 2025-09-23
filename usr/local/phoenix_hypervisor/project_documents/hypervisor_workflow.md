---
title: Phoenix Hypervisor Orchestration Workflow
summary: This document outlines the orchestration workflow for the Phoenix Hypervisor, detailing hypervisor setup, LXC orchestration, and VM management flows.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- Orchestration
- Workflow
- LXC
- VM Management
- Hypervisor Setup
review_cadence: Annual
last_reviewed: 2025-09-23
---
This document outlines the orchestration workflow for the Phoenix Hypervisor, detailing hypervisor setup, LXC orchestration, and VM management flows.

```mermaid
graph TD
    A[Start: phoenix_orchestrator.sh] --> B{Parse Arguments};
    B -- --setup-hypervisor --> C{Call handle_hypervisor_setup_state};
    B -- CTID --> D{Call LXC Orchestration Flow};

    subgraph "Hypervisor Setup Flow (handle_hypervisor_setup_state)"
        C --> C1[Read & Validate hypervisor_config.json];
        C1 --> C2[Execute hypervisor_initial_setup.sh];
        C2 --> C3[Execute hypervisor_feature_install_nvidia.sh];
        C3 --> C4[Execute hypervisor_feature_create_admin_user.sh];
        C4 --> C5[Execute hypervisor_feature_setup_zfs.sh (no config passed)];
        C5 --> C6[Execute hypervisor_feature_setup_nfs.sh];
        C6 --> C7[Execute hypervisor_feature_setup_samba.sh];
        C7 --> C_END[Hypervisor Setup Complete];
    end

    subgraph "LXC Orchestration Flow (Existing)"
        D --> D1[Validate LXC Inputs];
        D1 --> D2{Container Exists?};
        D2 -- No --> D3[Create/Clone Container];
        D2 -- Yes --> D4[Skip Creation];
        D3 --> D5[Apply LXC Configurations];
        D4 --> D5;
        D5 --> D6{Container Running?};
        D6 -- No --> D7[Start Container];
        D6 -- Yes --> D8[Skip Start];
        D7 --> D9[Apply LXC Features];
        D8 --> D9;
        D9 --> D10[Run Application Script];
        D10 --> D11[Create Template Snapshot];
        D11 --> D_END[LXC Orchestration Complete];
    end

    C_END --> Z[End: Orchestrator Finished];
    D_END --> Z;

    subgraph "VM Management Flow (New)"
        E[Call handle_vm_management_state] --> E1{Parse VM Arguments};
        E1 -- --create-vm --> E2[Execute vm_create.sh];
        E1 -- --start-vm --> E3[Execute vm_start.sh];
        E1 -- --stop-vm --> E4[Execute vm_stop.sh];
        E1 -- --delete-vm --> E5[Execute vm_delete.sh];
        E2 --> E_END[VM Operation Complete];
        E3 --> E_END;
        E4 --> E_END;
        E5 --> E_END;
    end

    B -- --create-vm/--start-vm/--stop-vm/--delete-vm --> E[Call handle_vm_management_state];
    E_END --> Z;
