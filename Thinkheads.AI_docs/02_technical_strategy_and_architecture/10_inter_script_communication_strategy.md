---
title: Inter-Script Communication Strategy
summary: A strategy for communication between the phoenix dispatcher and its manager scripts, recommending the use of command-line arguments for optimal decoupling.
document_type: Technical Strategy
status: Implemented
version: 2.0.0
author: Roo
owner: Technical VP
tags:
  - Inter-Script Communication
  - Shell Scripting
  - Phoenix CLI
  - Orchestration
  - Decoupling
review_cadence: Annual
last_reviewed: 2025-09-30
---

# Inter-Script Communication Strategy for Phoenix Hypervisor

**Author:** Roo, Architect
**Version:** 2.0.0
**Date:** 2025-09-30

## 1. Problem Statement

The `phoenix` CLI, which serves as the central dispatcher for the Phoenix Hypervisor framework, needs to invoke specialized manager scripts (`hypervisor-manager.sh`, `lxc-manager.sh`, `vm-manager.sh`) and pass them the necessary context to perform their tasks.

The primary challenge is to establish a communication pattern that is robust, maintainable, and aligns with our architectural principle of loose coupling between the dispatcher and its managers.

## 2. Architectural Overview

The `phoenix` CLI employs a dispatcher-manager architecture. The `phoenix` script is responsible for parsing user commands and routing them to the appropriate manager. The managers contain the business logic for their respective domains.

This separation of concerns requires a clear and efficient communication strategy.

## 3. Communication Strategy

The communication between the `phoenix` dispatcher and the manager scripts is handled through command-line arguments. The dispatcher passes the relevant arguments to the managers, which then use them to execute their tasks.

### Example Flow: `phoenix create 9001`

1.  The user executes `phoenix create 9001`.
2.  The `phoenix` dispatcher parses the command and identifies the verb (`create`) and the ID (`9001`).
3.  The dispatcher determines the resource type (LXC or VM) by querying the configuration files.
4.  Assuming `9001` is an LXC container, the dispatcher invokes the `lxc-manager.sh` script, passing the necessary arguments:
    ```bash
    /usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh --action create --id 9001
    ```
5.  The `lxc-manager.sh` script then parses these arguments and executes the container creation logic.

### Advantages of this Approach

*   **Optimal Decoupling:** The manager scripts are self-contained and can be tested in isolation by passing the appropriate arguments.
*   **Clarity and Maintainability:** The data flow is explicit and easy to follow, making the system easier to debug and maintain.
*   **Follows Unix Philosophy:** Adheres to the principle of creating small, focused tools that are controlled by command-line arguments.

## 4. Deprecated Strategy: Standard Input

The previous version of the orchestrator used standard input to pipe JSON configuration snippets to sub-scripts. While this provided some level of decoupling, it has been superseded by the dispatcher-manager architecture.

The new approach is more explicit and provides a clearer separation of concerns, as the dispatcher is solely responsible for routing, and the managers are responsible for execution. This eliminates the need for complex data piping and makes the entire system more robust and maintainable.