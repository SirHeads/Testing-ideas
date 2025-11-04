# Certificate Verification Plan

This plan details the steps to verify the entire certificate provisioning and deployment pipeline, with a special focus on file permissions and accessibility.

## Objective

To ensure that the Step-CA (LXC 103) is correctly issuing certificates, that the `certificate-renewal-manager.sh` is deploying them with the correct permissions, and that the services (Nginx, Traefik, Portainer) can access and use them.

## Verification Steps

### 1. Verify Step-CA Health (LXC 103)

*   **Check the Step-CA service status:**
    ```bash
    pct exec 103 -- systemctl status step-ca
    ```
*   **Verify that the CA is responsive:**
    ```bash
    pct exec 103 -- step ca health --ca-url "https://127.0.0.1:9000" --root "/etc/step-ca/ssl/certs/root_ca.crt"
    ```

### 2. Inspect Certificate Files on the Hypervisor

This is the most critical step, as it directly verifies the file permissions on the shared storage before they are mounted into containers.

*   **List the contents of the shared SSL directory for Step-CA:**
    ```bash
    ls -l /mnt/pve/quickOS/lxc-persistent-data/103/ssl/
    ```
    *   **Expected:** `root_ca.crt`, `provisioner_password.txt`, etc., should be owned by `root:root` with restrictive permissions (e.g., `600` for keys/passwords).

*   **Inspect the Nginx certificate and key permissions:**
    ```bash
    ls -l /mnt/pve/quickOS/lxc-persistent-data/101/ssl/
    ```
    *   **Expected:** `nginx.internal.thinkheads.ai.crt` and `nginx.internal.thinkheads.ai.key` should exist. The key file, in particular, must be readable by the user running the Nginx process (often `www-data` or `root`). Check ownership and group permissions carefully.

*   **Inspect the Traefik certificate and key permissions:**
    ```bash
    ls -l /mnt/pve/quickOS/lxc-persistent-data/102/certs/
    ```
    *   **Expected:** `traefik.internal.thinkheads.ai.crt` and `traefik.internal.thinkheads.ai.key` should exist and be readable by the user running Traefik.

*   **Inspect the Portainer certificate and key permissions:**
    ```bash
    ls -l /quickOS/vm-persistent-data/1001/portainer/certs/
    ```
    *   **Expected:** `portainer.crt` and `portainer.key` should exist and be readable by the user running the Portainer container. The directory is likely owned by `nobody:nogroup` for NFS access.

### 3. Verify Certificate Accessibility from within Containers

These checks confirm that the mounted certificates are readable by the services that need them.

*   **From LXC 101 (Nginx):**
    ```bash
    # Check that the Nginx user (www-data) can read the certificate and key
    pct exec 101 -- sudo -u www-data cat /etc/nginx/ssl/nginx.internal.thinkheads.ai.crt > /dev/null
    pct exec 101 -- sudo -u www-data cat /etc/nginx/ssl/nginx.internal.thinkheads.ai.key > /dev/null
    ```

*   **From LXC 102 (Traefik):**
    ```bash
    # Check that the root user (running Traefik) can read the certificate and key
    pct exec 102 -- cat /etc/traefik/certs/traefik.internal.thinkheads.ai.crt > /dev/null
    pct exec 102 -- cat /etc/traefik/certs/traefik.internal.thinkheads.ai.key > /dev/null
    ```

*   **From VM 1001 (Portainer):**
    ```bash
    # Check that the root user (running Portainer) can read the certificate and key
    qm guest exec 1001 -- cat /persistent-storage/portainer/certs/portainer.crt > /dev/null
    qm guest exec 1001 -- cat /persistent-storage/portainer/certs/portainer.key > /dev/null
    ```

## Expected Outcomes

*   All certificate files and private keys exist in their expected locations on the hypervisor's persistent storage.
*   The ownership and permissions of these files are appropriate for the service that will be using them (e.g., readable by `www-data` for Nginx).
*   The `pct exec` and `qm guest exec` commands to `cat` the files should complete without any "Permission denied" errors.

Any permission errors in these steps would strongly indicate that the file permissions are indeed the root cause of the connectivity issues.