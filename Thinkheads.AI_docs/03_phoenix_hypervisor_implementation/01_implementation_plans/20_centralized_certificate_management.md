# Centralized Certificate Management Plan

## 1. Executive Summary

This document outlines the plan to resolve a critical TLS certificate expiration issue and to implement a robust, centralized, and automated certificate renewal system for the Phoenix Hypervisor environment. The current architecture has led to an expired certificate on the NGINX gateway, preventing access to backend services like Portainer.

The agreed-upon solution is to create a dedicated, manifest-driven certificate renewal service that will run on a daily cron schedule. This approach aligns with industry best practices for security, maintainability, and scalability.

## 2. Highlights of Architectural Discussion

- **Problem:** The `phoenix sync all` command was failing because the NGINX gateway's TLS certificate had expired. The root cause was the absence of any automated renewal logic.
- **Initial Idea vs. Final Plan:** We initially considered embedding renewal logic into existing scripts, but agreed that this was not a true automation solution. We opted for a more professional architecture: a standalone, centralized renewal service.
- **Certificate Validity:** We discussed the trade-offs between short-lived (e.g., 24-hour) and long-lived (e.g., 1-year) certificates. We decided on a **30-day validity** as a secure and stable middle ground, managed by a daily automated renewal check.
- **Architectural Pattern:** The chosen design is a **Two-Tiered Proxy with Centralized Certificate Management**.
    - **NGINX (Tier 1):** Acts as the secure TLS Termination point for the entire internal network. It holds the primary certificate.
    - **Traefik (Tier 2):** Acts as a dynamic service mesh, automatically handling the routing for backend Docker containers without needing to manage individual certificates.
- **Professional Standard:** This architecture is considered a professional best practice, mirroring patterns used in major cloud providers and Kubernetes environments. It provides defense-in-depth, separation of concerns, and operational excellence.

## 3. Detailed Implementation Plan

### Step 1: Create the Certificate Manifest File
- **File:** `/usr/local/phoenix_hypervisor/etc/certificate-manifest.json`
- **Action:** Create a JSON file that defines all certificates to be managed by the new service.

### Step 2: Create the Renewal Manager Script
- **File:** `/usr/local/phoenix_hypervisor/bin/managers/certificate-renewal-manager.sh`
- **Action:** Create a new bash script that reads the manifest, checks each certificate for impending expiration, renews it using `step-ca`, and runs a post-renewal command.

### Step 3: Remove Redundant Logic from `portainer-manager.sh`
- **File:** `/usr/local/phoenix_hypervisor/bin/managers/portainer-manager.sh`
- **Action:** Remove the now-obsolete `generate_portainer_certificate` function and its call to decouple it from the new centralized service.

### Step 4: Temporarily Fix `generate_nginx_gateway_config.sh`
- **File:** `/usr/local/phoenix_hypervisor/bin/generate_nginx_gateway_config.sh`
- **Action:** As an immediate fix to get the system running, add logic to this script to generate the NGINX certificate on-the-fly. This will be superseded by the renewal manager.

### Step 5: Set Up the Cron Job
- **Location:** Proxmox Hypervisor's crontab.
- **Action:** Add a new cron job to execute `certificate-renewal-manager.sh` once every 24 hours.

### Step 6: Full System Test
- **Action 1:** Rerun `phoenix sync all` to confirm the temporary fix allows the full synchronization to complete.
- **Action 2:** Manually execute the `certificate-renewal-manager.sh` script to verify the new centralized logic works as designed.

## 4. Workflow Diagram

```mermaid
sequenceDiagram
    participant Cron as Cron Job (Hypervisor)
    participant Manager as certificate-renewal-manager.sh
    participant Manifest as cert-manifest.json
    participant StepCA as Step-CA (LXC 103)
    participant NFS as NFS Share
    participant Service as NGINX or Portainer

    Cron->>Manager: Run daily
    Manager->>Manifest: Read list of certs to manage
    loop For each certificate
        Manager->>NFS: Check expiration of current cert
        alt Certificate nearing expiration
            Manager->>StepCA: Request new certificate
            StepCA-->>Manager: Return new certificate
            Manager->>NFS: Save new certificate and key
            Manager->>Service: Trigger service reload (e.g., nginx reload)
        end
    end