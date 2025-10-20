# Phoenix Hypervisor Remediation Plan

## 1. Executive Summary

This document outlines the plan to remediate the critical networking failure in the Phoenix Hypervisor environment. The root cause has been identified as incorrect, hardcoded `/etc/hosts` entries in the setup scripts for the Traefik (LXC 102) and Step-CA (LXC 103) containers. These entries bypass the intended dual-horizon DNS architecture, causing a complete breakdown in communication between the core networking services, preventing certificate issuance and internal service routing.

The proposed solution is to remove the faulty `/etc/hosts` entries from the setup scripts and ensure that all components rely on the central `dnsmasq` server in the Nginx Gateway container (LXC 101) for all DNS resolution.

## 2. Problem Analysis

The investigation revealed the following critical issues:

*   **LXC 103 (Step-CA):** The setup script `phoenix_hypervisor_lxc_103.sh` incorrectly adds `/etc/hosts` entries that point internal service hostnames to the Nginx gateway's IP (`10.0.0.153`) instead of their actual IPs. This causes the CA to fail when trying to validate ACME challenges.
*   **LXC 102 (Traefik):** The setup script `phoenix_hypervisor_lxc_102.sh` adds incorrect `/etc/hosts` entries, pointing backend services to the wrong IP (`10.0.0.101`). This prevents Traefik from discovering and routing traffic to the correct backend services.

These misconfigurations create a situation where the core networking components cannot communicate with each other correctly, leading to the observed failures.

## 3. Remediation Steps

The following steps will be taken to resolve the issue:

1.  **Modify `phoenix_hypervisor_lxc_103.sh`:**
    *   Remove the section that adds incorrect hostnames to the `/etc/hosts` file.
    *   Ensure the container's DNS resolver is correctly configured to point to the Nginx gateway (`10.0.0.153`).

2.  **Modify `phoenix_hypervisor_lxc_102.sh`:**
    *   Remove the section that adds incorrect hostnames to the `/etc/hosts` file.
    *   Ensure the container's DNS resolver is correctly configured to point to the Nginx gateway (`10.0.0.153`).

3.  **Redeploy Networking Containers:**
    *   Destroy and recreate the core networking containers (LXC 101, 102, and 103) using the `phoenix-cli` to apply the corrected setup scripts.

## 4. Implementation Plan

The remediation will be implemented by the **Code** mode, which will perform the following actions:

1.  Use `apply_diff` to remove the incorrect `/etc/hosts` entries from `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_103.sh`.
2.  Use `apply_diff` to remove the incorrect `/etc/hosts` entries from `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_102.sh`.
3.  Provide instructions to the user on how to redeploy the networking containers using the `phoenix-cli`.

## 5. Expected Outcome

Upon successful completion of this remediation plan, the Phoenix Hypervisor environment will be fully functional:

*   All containers will correctly use the central `dnsmasq` server for DNS resolution.
*   The Step-CA will be able to successfully issue and validate certificates for all internal services.
*   Traefik will be able to correctly discover and route traffic to all backend services.
*   The entire system will be aligned with the intended dual-horizon DNS architecture, ensuring a stable and scalable networking environment.
