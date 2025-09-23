---
title: API Gateway Access Guide
summary: This guide explains how to connect to services that are exposed through the api-gateway-lxc (Container 953).
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- API Gateway
- NGINX
- Networking
- LXC
review_cadence: Annual
last_reviewed: 2025-09-23
---

# How to Access Services via the API Gateway

This guide explains how to connect to services that are exposed through the `api-gateway-lxc` (Container 953).

## 1. Ensure the API Gateway is Running

The API Gateway container (953) must be created and running. The provisioning script `phoenix_hypervisor_lxc_953.sh` automatically configures all the necessary reverse proxy settings.

## 2. Update Your Local `hosts` File

To access the services using a friendly domain name, you need to map the domain to the IP address of the API Gateway (`10.0.0.153`) in your local `hosts` file.

1.  Open the `hosts` file on your macOS machine with administrative privileges:
    ```bash
    sudo nano /etc/hosts
    ```

2.  Add the following line for the n8n service:
    ```
    10.0.0.153  n8n.phoenix.local
    ```

3.  Save the file and exit the editor.

## 3. Access n8n in Your Browser

You can now access n8n in your browser at [https://n8n.phoenix.local](https://n8n.phoenix.local).

**Note:** The service uses a self-signed SSL certificate, so your browser will display a security warning. You will need to accept the warning to proceed to the site.