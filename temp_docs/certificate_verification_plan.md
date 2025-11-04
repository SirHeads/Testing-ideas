# Certificate Verification Plan

This plan outlines the steps to verify the entire certificate chain and deployment process, from the Step-CA to the individual services.

## 1. Verify Step-CA (LXC 103) Health

First, we must ensure the Certificate Authority itself is healthy and operational.

*   **Action:** Check the status of the `step-ca` service.
*   **Command:** `pct exec 103 -- systemctl status step-ca`
*   **Verification:** The service should be `active (running)`.

*   **Action:** Verify that the CA is listening on its designated port.
*   **Command:** `pct exec 103 -- ss -tuln | grep ':9000'`
*   **Verification:** The command should show a `LISTEN` state on port 9000.

*   **Action:** Check the `step-ca` logs for any errors.
*   **Command:** `pct exec 103 -- journalctl -u step-ca -n 50`
*   **Verification:** The logs should not contain any fatal errors or repeated warnings.

## 2. Verify Certificate Generation and Placement

The `certificate-renewal-manager.sh` is responsible for creating and placing certificates. We need to verify that this process is working correctly.

*   **Action:** Manually run the certificate manager with the `--force` flag to ensure all certificates are fresh.
*   **Command:** `/usr/local/phoenix_hypervisor/bin/managers/certificate-renewal-manager.sh --force`
*   **Verification:** The script should complete without errors.

*   **Action:** Inspect the generated certificates on the hypervisor's shared storage.
*   **Command:** `ls -l /mnt/pve/quickOS/lxc-persistent-data/101/ssl/`
*   **Verification:** The directory should contain the `nginx.internal.thinkheads.ai.crt` and `.key` files with recent timestamps.

## 3. Verify Certificate Deployment to Guests

Finally, we need to ensure that the generated certificates are correctly mounted and used by the services in their respective guests.

### Nginx (LXC 101):

*   **Action:** Verify the certificate files are present inside the Nginx container.
*   **Command:** `pct exec 101 -- ls -l /etc/nginx/ssl/`
*   **Verification:** The directory should contain the `nginx.internal.thinkheads.ai.crt` and `.key` files.

*   **Action:** Use `openssl` to connect to the Nginx gateway and inspect the served certificate.
*   **Command:** `openssl s_client -connect 10.0.0.153:443 -servername nginx.internal.thinkheads.ai < /dev/null 2>/dev/null | openssl x509 -noout -text`
*   **Verification:**
    *   The "Issuer" should be our internal CA.
    *   The "Subject" should be `CN = nginx.internal.thinkheads.ai`.
    *   The certificate should not be expired.

### Traefik (LXC 102):

*   **Action:** Verify the certificate files are present inside the Traefik container.
*   **Command:** `pct exec 102 -- ls -l /etc/traefik/certs/`
*   **Verification:** The directory should contain the `traefik.internal.thinkheads.ai.crt` and `.key` files.

## 4. Key Areas of Concern

*   **Step-CA Failure:** If the Step-CA service is not running, no certificates can be issued.
*   **Permissions Issues:** Incorrect file permissions on the shared storage can prevent the certificate manager from writing files or the guest containers from reading them.
*   **Outdated Certificates:** If the renewal manager is failing, services may be attempting to use expired certificates.