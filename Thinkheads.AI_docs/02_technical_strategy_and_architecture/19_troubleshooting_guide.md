---
title: Troubleshooting Guide
summary: A guide to troubleshooting common issues with the Phoenix Hypervisor.
document_type: Technical Guide
status: Draft
version: 1.0.0
author: Roo
owner: Technical VP
tags:
  - Troubleshooting
  - Guide
  - Phoenix Hypervisor
review_cadence: Quarterly
last_reviewed: 2025-09-29
---

# Troubleshooting Guide

This guide provides solutions to common issues that may arise when working with the Phoenix Hypervisor.

## 1. General Troubleshooting Steps

When encountering an issue, follow these general troubleshooting steps:

1.  **Check the Logs:** The `phoenix_orchestrator.sh` script logs its output to `/var/log/phoenix_hypervisor/orchestrator_*.log`. This should be the first place you look for errors.
2.  **Run in Dry-Run Mode:** Use the `--dry-run` flag to see what commands the orchestrator will execute without actually making any changes.
3.  **Validate Configuration:** Ensure that your JSON configuration files are valid and that they match the schema.
4.  **Check Service Status:** If a service is not working, check its status inside the container using `systemctl status <service>`.

## 2. Common Issues and Resolutions

### 2.1. Container Fails to Start

*   **Symptom:** The `pct start <CTID>` command fails.
*   **Cause:** This can be caused by a variety of issues, including incorrect network configuration, insufficient resources, or a misconfigured AppArmor profile.
*   **Resolution:**
    1.  Check the container's configuration in `/etc/pve/lxc/<CTID>.conf`.
    2.  Check the system logs for any AppArmor denials (`dmesg | grep apparmor`).
    3.  Try starting the container in debug mode (`lxc-start -n <CTID> -l DEBUG -o /tmp/lxc-<CTID>.log`).

### 2.2. Docker Issues

*   **Symptom:** Docker commands fail inside a container.
*   **Cause:** This is often due to an incorrect AppArmor profile or a missing dependency.
*   **Resolution:**
    1.  Ensure that the container is using the `lxc-phoenix-v2` AppArmor profile.
    2.  Verify that the `fuse-overlayfs` package is installed in the container.
    3.  Check the Docker daemon logs for errors (`journalctl -u docker`).

### 2.3. Network Issues

*   **Symptom:** A container cannot access the network or other containers.
*   **Cause:** This is usually due to an incorrect network configuration in `phoenix_lxc_configs.json`.
*   **Resolution:**
    1.  Verify that the container's IP address, gateway, and bridge are correctly configured.
    2.  Check the host's firewall rules to ensure that traffic is not being blocked.
    3.  Use `ping` and `traceroute` to diagnose network connectivity issues.