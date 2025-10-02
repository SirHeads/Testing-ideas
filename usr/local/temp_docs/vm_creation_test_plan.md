# VM Creation Workflow Test Plan

## 1. Introduction

This document outlines the test plan for the enhanced VM creation workflow in the Phoenix Hypervisor system. The plan covers all new and modified functionality, ensuring the stability and correctness of the implementation.

## 2. Test Objectives

*   Validate all new and modified schema properties in `phoenix_vm_configs.json`.
*   Verify the end-to-end VM creation workflow from a cloud image template.
*   Ensure the idempotent nature of all `vm-manager.sh` functions.
*   Validate the modular feature installation system, specifically the Docker feature.
*   Test the lifecycle snapshot management system.

## 3. Test Environment

*   Proxmox VE Environment
*   Phoenix Hypervisor scripts and configurations

## 4. Test Cases

### 4.1. Schema Validation

| Test Case ID | Description | Expected Result |
| :--- | :--- | :--- |
| SCH-001 | Validate a `phoenix_vm_configs.json` file with all required `vm_defaults` properties. | The configuration is considered valid. |
| SCH-002 | Validate a `phoenix_vm_configs.json` file with a VM definition that includes all required properties (`vmid`, `name`). | The configuration is considered valid. |
| SCH-003 | Validate a VM definition with the `start_at_boot` property set to `true`. | The configuration is valid, and the VM is configured to start on boot. |
| SCH-004 | Validate a VM definition with `boot_order` and `boot_delay` properties. | The configuration is valid, and the VM has the correct boot order and delay. |
| SCH-005 | Validate a VM definition with a list of `features`. | The configuration is valid. |
| SCH-006 | Validate a VM definition with `snapshots` properties (`pre_features`, `post_features`). | The configuration is valid. |
| SCH-007 | Validate a VM definition with `qm_options`. | The configuration is valid, and the options are applied to the VM. |
| SCH-008 | Validate a VM definition with `volumes`. | The configuration is valid, and the volumes are created and attached. |
| SCH-009 | Validate a VM definition with `firewall` rules. | The configuration is valid, and the firewall rules are applied. |
| SCH-010 | Validate a VM definition with `network_config`. | The configuration is valid, and the network is configured correctly. |
| SCH-011 | Validate a VM definition with `user_config`. | The configuration is valid, and the user is configured correctly. |

### 4.2. End-to-End Workflow

| Test Case ID | Description | Expected Result |
| :--- | :--- | :--- |
| E2E-001 | Create a new VM from a cloud image template (`ubuntu-24.04-standard`). | The VM is created, configured, and started successfully. |
| E2E-002 | Clone an existing VM. | The new VM is created as a clone of the source VM. |
| E2E-003 | The `orchestrate_vm` function completes all steps successfully. | The VM is fully provisioned without any errors. |

### 4.3. Idempotency

| Test Case ID | Description | Expected Result |
| :--- | :--- | :--- |
| IDM-001 | Run the `create` action for an existing VM. | The script should detect that the VM already exists and skip the creation process. No changes should be made to the VM. |
| IDM-002 | Run the `start` action for a running VM. | The script should detect that the VM is already running and do nothing. |
| IDM-003 | Run the `stop` action for a stopped VM. | The script should detect that the VM is already stopped and do nothing. |

### 4.4. Modular Feature Installation

| Test Case ID | Description | Expected Result |
| :--- | :--- | :--- |
| FTR-001 | Create a VM with the "docker" feature. | The VM is created, and the Docker feature is installed and configured correctly. The `docker` service should be running, and the specified user should be in the `docker` group. |
| FTR-002 | Run the `apply_vm_features` function on a VM that already has the feature installed. | The feature script should detect that the feature is already installed and skip the installation process. |

### 4.5. Lifecycle Snapshot Management

| Test Case ID | Description | Expected Result |
| :--- | :--- | :--- |
| SNP-001 | Create a VM with `snapshots.pre_features` enabled. | A snapshot is created before the features are applied. |
| SNP-002 | Create a VM with `snapshots.post_features` enabled. | A snapshot is created after the features are applied. |
| SNP-003 | Run the `manage_snapshots` function for a snapshot that already exists. | The script should detect that the snapshot already exists and skip the creation process. |
