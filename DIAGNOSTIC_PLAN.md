# Diagnostic Plan: 502 Bad Gateway on Portainer and n8n

## 1. Introduction

This document provides a step-by-step diagnostic plan to identify the root cause of the 502 Bad Gateway errors affecting the Portainer and n8n Web UIs. The plan is designed to be executed by a debug-focused agent and is based on an analysis of the `phoenix_hypervisor` system architecture.

## 2. Diagnostic Steps

### Step 1: Verify Container Status and Logs

1.  **Check the status of the Nginx gateway container (LXC 953):**
    ```bash
    pct status 953
    ```

2.  **If the container is not running, attempt to start it:**
    ```bash
    pct start 953
    ```

3.  **Access the container's console:**
    ```bash
    pct enter 953
    ```

4.  **Check the status of the Nginx service:**
    ```bash
    systemctl status nginx
    ```

5.  **Review the Nginx error logs for any obvious issues:**
    ```bash
    tail -n 100 /var/log/nginx/error.log
    ```

### Step 2: Validate Nginx Configuration

1.  **Verify that the Portainer and n8n proxy configurations are enabled:**
    ```bash
    ls -l /etc/nginx/sites-enabled/
    ```
    *Expected output should include symbolic links for `portainer_proxy` and `n8n_proxy`.*

2.  **Test the Nginx configuration for syntax errors:**
    ```bash
    nginx -t
    ```

3.  **Review the proxy configurations to ensure the upstream server IPs and ports are correct:**
    *   `portainer_proxy`: `10.0.0.99:9443`
    *   `n8n_proxy`: `10.0.0.154:5678`

### Step 3: Test Network Connectivity

1.  **From within the Nginx container (LXC 953), test connectivity to the Portainer and n8n containers:**
    ```bash
    # Test Portainer connectivity
    curl -k https://10.0.0.99:9443

    # Test n8n connectivity
    curl http://10.0.0.154:5678
    ```
    *A successful connection should return a response from the respective services.*

2.  **If connectivity fails, check the firewall rules on the host and within the containers.**

### Step 4: Inspect Shared Volume Permissions

1.  **On the Proxmox host, verify the permissions of the shared SSL certificate directory:**
    ```bash
    ls -l /mnt/pve/quickOS/shared-prod-data/ssl
    ```
    *The Nginx container's user (typically `www-data`) should have read access to the certificates.*

2.  **Check the AppArmor profiles to ensure they are not blocking access to the shared volumes.**

### Step 5: Review AppArmor Profiles

1.  **Check the AppArmor status to see if any profiles are in complain or enforce mode:**
    ```bash
    aa-status
    ```

2.  **Review the AppArmor logs for any denial messages related to Nginx or the shared volumes:**
    ```bash
    grep "apparmor=\"DENIED\"" /var/log/syslog
    ```

## 3. Conclusion

By following this diagnostic plan, a debug-focused agent should be able to systematically identify the root cause of the 502 Bad Gateway errors. The findings from this investigation will inform the necessary steps to resolve the issue.