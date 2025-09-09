---
title: 'LXC Container 953: api-gateway-lxc - Implementation Plan'
summary: This document provides a detailed, step-by-step implementation plan for converting LXC container 953 into a high-performance, secure Nginx reverse proxy and API gateway.
document_type: Technical
status: Final
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Team/Individual Name
tags:
- LXC Container
- API Gateway
- Nginx
- Reverse Proxy
- Implementation
- Proxmox
- Security
- Performance
- Phoenix Hypervisor
review_cadence: Annual
last_reviewed: YYYY-MM-DD
---

## 1. Introduction

This document outlines the detailed implementation plan for transforming LXC container `953` into `api-gateway-lxc`, a dedicated Nginx reverse proxy. This plan is based on the architecture defined in `lxc_953_architectural_plan.md` and provides actionable steps, commands, and configuration examples to ensure a successful deployment.

The implementation is divided into four phases:
1.  **LXC Container Provisioning and Initial Setup**
2.  **Nginx Configuration**
3.  **Security Hardening**
4.  **Integration and Validation**

## 2. Phase 1: LXC Container Provisioning and Initial Setup

This phase covers the creation and basic configuration of the LXC container.

### Step 1.1: Update `phoenix_lxc_configs.json`

Modify the entry for container `953` in `/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json` to reflect the resource allocation and network configuration specified in the architectural plan.

**Example JSON Snippet:**
```json
{
  "lxc_id": 953,
  "hostname": "api-gateway-lxc",
  "template": "local:vztmpl/debian-11-standard_11.3-1_amd64.tar.gz",
  "storage": "quickOS-lxc-disks",
  "disk_size": "32G",
  "cores": 4,
  "memory": 4096,
  "swap": 512,
  "network": {
    "name": "eth0",
    "bridge": "vmbr0",
    "ip": "10.0.0.153/24",
    "gw": "10.0.0.1",
    "mac": "52:54:00:67:89:B3"
  },
  "features": ["nesting=1"],
  "unprivileged": true,
  "app_runner_script": "phoenix_hypervisor_lxc_953.sh"
}
```

### Step 1.2: Create `phoenix_hypervisor_lxc_953.sh`

Create the application runner script at `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_953.sh`. This script will automate the installation of Nginx and other required packages.

```bash
#!/bin/bash

# Exit on any error
set -e

# Update package lists and install Nginx
apt-get update
apt-get install -y nginx

# Enable and start Nginx service
systemctl enable nginx
systemctl start nginx

# Perform health check
if ! systemctl is-active --quiet nginx; then
    echo "Nginx service is not running."
    exit 1
fi

echo "Nginx has been installed and started successfully."
exit 0
```
Make the script executable: `chmod +x /usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_953.sh`

### Step 1.3: Run `phoenix_orchestrator.sh`

Execute the orchestrator script to create, configure, and start the LXC container based on the updated configuration.

```bash
/usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh --lxc 953 --action create
```

## 3. Phase 2: Nginx Configuration

This phase involves configuring Nginx to function as a reverse proxy with caching, load balancing, and other performance features.

### Step 2.1: Basic Reverse Proxy and Load Balancing

Create a new server block configuration file at `/etc/nginx/sites-available/api.example.com`.

```nginx
# /etc/nginx/sites-available/api.example.com

# Define the backend server pool
upstream vllm_backend {
    server 10.0.0.151:8000;
    server 10.0.0.152:8000;
}

server {
    listen 80;
    server_name api.example.com;

    location / {
        proxy_pass http://vllm_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable this site by creating a symbolic link:
`ln -s /etc/nginx/sites-available/api.example.com /etc/nginx/sites-enabled/`

### Step 2.2: Configure Caching

Edit `/etc/nginx/nginx.conf` and add the `proxy_cache_path` directive within the `http` block.

```nginx
# /etc/nginx/nginx.conf

http {
    # ... other http block settings ...

    proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=api_cache:10m max_size=10g inactive=60m use_temp_path=off;

    # ... include server blocks ...
}
```

Now, update the server block at `/etc/nginx/sites-available/api.example.com` to use the cache.

```nginx
# /etc/nginx/sites-available/api.example.com

server {
    # ... listen and server_name ...

    location / {
        proxy_cache api_cache;
        proxy_cache_valid 200 302 10m;
        proxy_cache_valid 404 1m;
        proxy_cache_key "$scheme$request_method$host$request_uri";
        add_header X-Proxy-Cache $upstream_cache_status;

        proxy_pass http://vllm_backend;
        # ... other proxy_set_header directives ...
    }
}
```

### Step 2.3: Enable HTTP/2 and Gzip

Modify the `listen` directive in the server block to enable HTTP/2. Gzip can be enabled in `/etc/nginx/nginx.conf`.

```nginx
# /etc/nginx/nginx.conf

http {
    # ...
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    # ...
}
```

```nginx
# /etc/nginx/sites-available/api.example.com (for SSL/TLS server block)

server {
    listen 443 ssl http2;
    # ... rest of the configuration ...
}
```

### Step 2.4: Set up SSL/TLS Termination

1.  Obtain SSL/TLS certificates (e.g., using Let's Encrypt).
2.  Store the certificates in `/etc/nginx/ssl/`.
3.  Create a new server block for HTTPS or modify the existing one.

```nginx
# /etc/nginx/sites-available/api.example.com

server {
    listen 80;
    server_name api.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.example.com;

    ssl_certificate /etc/nginx/ssl/api.example.com.crt;
    ssl_certificate_key /etc/nginx/ssl/api.example.com.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers off;

    # ... location block with proxy_pass and caching ...
}
```

After making these changes, test the configuration and reload Nginx:
`nginx -t && systemctl reload nginx`

## 4. Phase 3: Security Hardening

This phase focuses on securing the Nginx server and the container.

### Step 3.1: Nginx Hardening

Edit `/etc/nginx/nginx.conf` to hide the Nginx version and ensure worker processes run as a non-root user.

```nginx
# /etc/nginx/nginx.conf

user www-data;
http {
    # ...
    server_tokens off;
    # ...
}
```

### Step 3.2: Implement Rate Limiting

In `/etc/nginx/nginx.conf`, define a rate limit zone.

```nginx
# /etc/nginx/nginx.conf

http {
    # ...
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    # ...
}
```

Apply the rate limit in the server block.

```nginx
# /etc/nginx/sites-available/api.example.com

server {
    # ...
    location / {
        limit_req zone=api_limit burst=20 nodelay;
        # ... proxy_pass and other directives ...
    }
}
```

### Step 3.3: Add Security Headers

Add the following headers to your server block.

```nginx
# /etc/nginx/sites-available/api.example.com

server {
    # ...
    location / {
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Content-Security-Policy "default-src 'self'";
        # ... proxy_pass and other directives ...
    }
}
```

### Step 3.4: Install and Configure ModSecurity (WAF)

1.  Install ModSecurity:
    `apt-get install -y libnginx-mod-http-modsecurity`
2.  Enable the module in `/etc/nginx/nginx.conf`:
    `load_module modules/ngx_http_modsecurity_module.so;`
3.  Configure ModSecurity in the `http` block:
    ```nginx
    http {
        # ...
        modsecurity on;
        modsecurity_rules_file /etc/nginx/modsec/main.conf;
        # ...
    }
    ```
4.  Set up the OWASP Core Rule Set (CRS) for robust protection.

### Step 3.5: Install and Configure Fail2ban

1.  Install Fail2ban:
    `apt-get install -y fail2ban`
2.  Create a new jail configuration for Nginx in `/etc/fail2ban/jail.local`:
    ```ini
    [nginx-http-auth]
    enabled = true
    port    = http,https
    logpath = /var/log/nginx/error.log

    [nginx-dos]
    enabled = true
    port    = http,https
    logpath = /var/log/nginx/access.log
    filter  = nginx-dos
    ```
3.  Start and enable the Fail2ban service:
    `systemctl enable fail2ban && systemctl start fail2ban`

## 5. Phase 4: Integration and Validation

### Step 5.1: Proxmox Integration

-   **Networking:** Ensure the LXC container's virtual bridge (`vmbr0`) is correctly configured on the Proxmox host and that firewall rules on Proxmox do not block traffic to ports 80 and 443 on the container's IP (`10.0.0.153`).
-   **Backups:** Configure regular backups for the `api-gateway-lxc` container through the Proxmox web interface.

### Step 5.2: Validation and Testing Plan

1.  **Health Checks:** The `phoenix_hypervisor_lxc_953.sh` script should include a final health check to verify Nginx is running and can connect to the backend services.
2.  **Performance Testing:** Use tools like `ab` (Apache Benchmark) or `wrk` to simulate traffic and measure response times and throughput.
3.  **Security Audit:** Use tools like `nmap` and `sslyze` to scan for open ports and check SSL/TLS configuration strength.
4.  **UAT:** Manually test API endpoints through the reverse proxy to ensure correct routing, caching, and security header implementation.

## 6. Summary

This implementation plan provides a comprehensive guide to deploying a secure and high-performance Nginx reverse proxy within LXC container 953. By following these steps, `api-gateway-lxc` will serve as a robust entry point for all backend services, enhancing security, performance, and scalability.