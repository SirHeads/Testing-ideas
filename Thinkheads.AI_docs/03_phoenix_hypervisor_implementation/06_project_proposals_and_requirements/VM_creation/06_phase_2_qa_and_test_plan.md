# Phase 2 QA and Test Plan: VM Creation

## 1. Introduction

This document outlines the Quality Assurance (QA) and test plan for the Phase 2 features of the VM creation initiative. The initial framing for Phase 2, which includes dynamic Cloud-Init, VM templating, and feature scripts, has been implemented. This plan details the necessary steps to ensure the quality, reliability, and correctness of these new features before they are fully integrated into the main development branch.

## 2. Testing Objectives

The primary objectives of this QA process are as follows:

*   **Verify Dynamic Cloud-Init Generation:** Ensure that the `phoenix_orchestrator.sh` script correctly generates `user-data` and `network-config` files from the templates and populates them with the correct values from the `phoenix_vm_configs.json` file.
*   **Confirm VM Creation from Template:** Validate that new VMs can be successfully created from a template image as defined in the configuration.
*   **Validate VM Cloning:** Ensure that new VMs can be successfully cloned from an existing VM snapshot.
*   **Test Feature Script Execution:** Confirm that feature scripts (e.g., `feature_install_docker.sh`) are executed correctly within the newly created VM.
*   **Ensure Idempotency:** Verify that repeated executions of the orchestrator script do not cause unintended side effects or errors.
*   **Validate Configuration Schema:** Ensure that the `phoenix_hypervisor_config.schema.json` correctly validates the new `vms` section and its properties.

## 3. Test Cases

### 3.1. Dynamic Cloud-Init Generation

| Test Case ID | Description | Pre-conditions | Execution Steps | Expected Result | Actual Result |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **P2-TC-01** | Verify `user-data.yml` generation | A valid VM configuration exists in `phoenix_vm_configs.json` with a unique username, password hash, and SSH key. | 1. Run `phoenix_orchestrator.sh` for the target VM. <br> 2. Inspect the generated `/tmp/user-data-<VMID>.yml` file. | The file should be generated with the `__HOSTNAME__`, `__USERNAME__`, `__PASSWORD_HASH__`, and `__SSH_PUBLIC_KEY__` placeholders replaced with the correct values from the configuration. | |
| **P2-TC-02** | Verify `network-config.yml` generation | A valid VM configuration exists with a static IP address and gateway. | 1. Run `phoenix_orchestrator.sh` for the target VM. <br> 2. Inspect the generated `/tmp/network-config-<VMID>.yml` file. | The file should be generated with the `__IPV4_ADDRESS__` and `__IPV4_GATEWAY__` placeholders replaced with the correct values. | |

### 3.2. VM Creation and Configuration

| Test Case ID | Description | Pre-conditions | Execution Steps | Expected Result | Actual Result |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **P2-TC-03** | Create a VM from a template | A valid VM configuration exists that uses a template image. The template image is available in the Proxmox ISO storage. | 1. Run `phoenix_orchestrator.sh` for the target VM. | The VM is created with the specified resources (cores, memory, disk size) and network configuration. The VM boots successfully. | |
| **P2-TC-04** | Clone a VM from a snapshot | A source VM with a designated `template_snapshot_name` exists. A new VM is configured to clone from the source VM. | 1. Run `phoenix_orchestrator.sh` for the new VM. | The new VM is created as a clone of the source VM's snapshot. The VM boots successfully and has a unique hostname and IP address. | |
| **P2-TC-05** | Verify VM network configuration | A VM has been created with a static IP address. | 1. SSH into the VM. <br> 2. Run `ip a` and `ip r`. | The VM's network interface should have the correct static IP address, and the default route should point to the correct gateway. | |
| **P2-TC-06** | Verify user account creation | A VM has been created with a specific username and SSH key. | 1. Attempt to SSH into the VM as the specified user with the corresponding private key. | Successful SSH login without a password. | |

### 3.3. Feature Script Execution

| Test Case ID | Description | Pre-conditions | Execution Steps | Expected Result | Actual Result |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **P2-TC-07** | Test Docker feature script | A VM is configured with the `docker` feature. | 1. Create the VM using `phoenix_orchestrator.sh`. <br> 2. SSH into the VM. <br> 3. Run `docker --version`. <br> 4. Run `docker run hello-world`. | Docker is installed and running. The `hello-world` container runs successfully. The configured user can run Docker commands without `sudo`. | |

### 3.4. Idempotency and Error Handling

| Test Case ID | Description | Pre-conditions | Execution Steps | Expected Result | Actual Result |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **P2-TC-08** | Test orchestrator idempotency | A VM has already been successfully created. | 1. Run `phoenix_orchestrator.sh` for the same VM again. | The script should recognize that the VM already exists and not attempt to re-create it. No errors should occur. | |
| **P2-TC-09** | Test with invalid configuration | The `phoenix_vm_configs.json` file contains a VM with a missing required field (e.g., `name`). | 1. Run `phoenix_orchestrator.sh` for the invalid VM. | The script should fail with a clear error message indicating a validation failure against the schema. | |

## 4. Sign-off

This test plan has been reviewed and is believed to accurately reflect the necessary QA steps to validate the current scripts and prepare for the continuation of Phase 2 development. Successful execution of these test cases will provide confidence in the stability and correctness of the new VM creation features.
