---
title: Troubleshooting Guide
summary: A comprehensive guide to troubleshooting common issues with the Phoenix Hypervisor.
document_type: Technical Guide
status: Revised
version: 1.1.0
author: Roo
owner: Technical VP
tags:
  - Troubleshooting
  - Guide
  - Phoenix Hypervisor
  - LXC
  - VM
  - Docker
  - AppArmor
review_cadence: Quarterly
last_reviewed: 2025-09-30
---

# Troubleshooting Guide

This guide provides solutions to common issues that may arise when working with the Phoenix Hypervisor. It covers general troubleshooting, LXC containers, VMs, and specific services like Docker.

## 1. General Troubleshooting Steps

When encountering an issue, follow these general troubleshooting steps first:

1.  **Check the Orchestrator Logs:** The `phoenix_orchestrator.sh` script is the primary entry point for all operations. Its logs are the first place to look for errors. Check the log file at `/var/log/phoenix_hypervisor/orchestrator_*.log`.
2.  **Run in Dry-Run Mode:** Use the `--dry-run` flag with `phoenix_orchestrator.sh` to see what commands the orchestrator will execute without making any changes. This is useful for verifying configurations before applying them.
3.  **Validate Configuration:** Ensure that your JSON configuration files (`phoenix_hypervisor_config.json`, `phoenix_lxc_configs.json`, `phoenix_vm_configs.json`) are valid and match their respective schemas.
4.  **Check Service Status:** If a service inside a container or VM is not working, check its status using `systemctl status <service>` or `journalctl -u <service>`.

## 2. Orchestrator Issues

The `phoenix_orchestrator.sh` script is central to all operations. If you encounter issues with the orchestrator itself:

*   **Symptom:** The script fails with a syntax error or unexpected behavior.
*   **Cause:** This can be due to incorrect permissions, missing dependencies, or an issue with the script itself.
*   **Resolution:**
    1.  Ensure the script is executable (`chmod +x phoenix_orchestrator.sh`).
    2.  Verify that all dependencies are installed (e.g., `jq`, `pct`, `qm`).
    3.  Run the script with `bash -x` to get a detailed execution trace.

## 3. LXC Container Issues

### 3.1. Container Fails to Start

*   **Symptom:** The `pct start <CTID>` command fails.
*   **Cause:** This can be caused by a variety of issues, including incorrect network configuration, insufficient resources, or a misconfigured AppArmor profile.
*   **Resolution:**
    1.  Check the container's configuration in `/etc/pve/lxc/<CTID>.conf`.
    2.  Check the system logs for any AppArmor denials (`dmesg | grep apparmor`).
    3.  Try starting the container in debug mode (`lxc-start -n <CTID> -l DEBUG -o /tmp/lxc-<CTID>.log`).

### 3.2. Docker Issues

*   **Symptom:** Docker commands fail inside a container.
*   **Cause:** This is often due to an incorrect AppArmor profile or a missing dependency.
*   **Resolution:**
    1.  **AppArmor Profile:** For most Docker containers, the `unconfined` AppArmor profile is recommended. This is the default in the `phoenix_lxc_configs.json`. If you need a more restrictive setup, the `lxc-phoenix-v2` profile can be used, but it may require customization.
    2.  **fuse-overlayfs:** Verify that the `fuse-overlayfs` package is installed in the container. This is handled by the `phoenix_hypervisor_feature_install_docker.sh` script.
    3.  **Check Docker Logs:** Check the Docker daemon logs for errors using `journalctl -u docker` inside the container.

### 3.3. Network Issues

*   **Symptom:** A container cannot access the network or other containers.
*   **Cause:** This is usually due to an incorrect network configuration in `phoenix_lxc_configs.json`.
*   **Resolution:**
    1.  Verify that the container's IP address, gateway, and bridge are correctly configured.
    2.  Check the host's firewall rules to ensure that traffic is not being blocked.
    3.  Use `ping` and `traceroute` to diagnose network connectivity issues.

## 4. VM Issues

### 4.1. VM Fails to Start

*   **Symptom:** The `qm start <VMID>` command fails.
*   **Cause:** This can be due to incorrect storage configuration, insufficient memory, or an issue with the VM's image.
*   **Resolution:**
    1.  Check the VM's configuration in `/etc/pve/qemu-server/<VMID>.conf`.
    2.  Review the Proxmox task logs for the failed start attempt.
    3.  Access the VM's console to check for boot errors.

### 4.2. Cloud-Init Issues

*   **Symptom:** The VM starts, but the user or network configuration is not applied.
*   **Cause:** This is often due to an error in the Cloud-Init user data or network configuration.
*   **Resolution:**
    1.  Check the generated Cloud-Init files in `/var/lib/vz/snippets/`.
    2.  Review the Cloud-Init logs inside the VM at `/var/log/cloud-init.log`.