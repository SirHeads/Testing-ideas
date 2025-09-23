---
title: NVIDIA Run File Installer Plan
summary: This document outlines a detailed plan for handling the NVIDIA run file during LXC container creation.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- NVIDIA
- GPU
- Driver Installation
- LXC Container
- Automation
review_cadence: Annual
last_reviewed: 2025-09-23
---

# Plan for Handling NVIDIA Run File During LXC Container Creation

This document outlines a detailed plan for handling the NVIDIA run file during LXC container creation.

## 1. Define a Shared Location for the NVIDIA Run File

To centralize the NVIDIA run file and avoid redundant downloads, we will use a dedicated directory on the hypervisor. This directory will serve as a cache for the run file.

- **Proposed Location:** `/usr/local/phoenix_hypervisor/cache`
- **Rationale:** This location is already used for caching downloads, as seen in `hypervisor_feature_install_nvidia.sh`. Utilizing the same directory ensures consistency.

## 2. Implement Run File Verification Logic

The LXC container's NVIDIA installation script (`phoenix_hypervisor_feature_install_nvidia.sh`) will be modified to first check for the existence of the run file in the hypervisor's cache.

- **Logic:**
    1. The script will read the required NVIDIA driver version and run file URL from the configuration.
    2. It will construct the expected local path to the run file within the `/usr/local/phoenix_hypervisor/cache` directory.
    3. The script will check if the file exists at the expected path.

## 3. Create a Fallback Download Mechanism

If the run file is not found in the cache, the script will automatically download it.

- **Process:**
    1. If the file is missing, the script will use `wget` or a similar utility to download the run file from the URL specified in the configuration.
    2. The downloaded file will be saved to the `/usr/local/phoenix_hypervisor/cache` directory.
    3. The script will then proceed with the installation.

## 4. Refine NVIDIA Driver Installation Steps

The driver installation process within the container will be streamlined to improve reliability.

- **Steps:**
    1. The script will push the run file from the hypervisor's cache to a temporary location within the container (e.g., `/tmp`).
    2. The script will execute the run file with the appropriate flags (`--silent`, `--no-kernel-module`, etc.).
    3. After a successful installation, the temporary run file will be removed from the container.

## 5. Centralize NVIDIA Driver Version Configuration

To ensure consistency, the NVIDIA driver version will be managed from a single, authoritative source.

- **Configuration File:** `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`
- **Rationale:** This file already contains NVIDIA-related settings, making it the logical place to manage the driver version. The `phoenix_hypervisor_config.json` file will still hold the URL, but the version number will be the primary key.

## 6. Develop a Verification Step

After the installation, a verification step will be added to confirm that the correct driver version is active.

- **Method:**
    1. The script will execute `nvidia-smi` within the container.
    2. The output will be parsed to extract the installed driver version.
    3. This version will be compared against the version specified in the configuration file.
    4. If the versions do not match, the script will log an error.

## Workflow Diagram

```mermaid
graph TD
    A[Start Installation] --> B[Detect Container OS Version];
    B --> C[Construct Dynamic CUDA Repository URL];
    C --> D[Configure NVIDIA CUDA apt Repository];
    D --> E[Update apt Package Lists];
    E --> F[Install CUDA Toolkit & Utilities];
    F --> G[Download NVIDIA .run File];
    G --> H[Push .run File to Container];
    H --> I[Execute .run File];
    I --> J[Clean Up .run File];
    J --> K{Verification};
    K -->|nvidia-smi & nvcc OK?| L[Installation Successful];
    K -->|Verification Fails| M[Log Error & Abort];
    L --> N[End];
    M --> N;