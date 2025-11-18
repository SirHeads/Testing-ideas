# Project Plan: Secure Traefik and Docker Swarm Integration

**Objective:** Transition the connection between Traefik (LXC 102) and the Docker Swarm manager (VM 1001) from an insecure TCP socket to a secure, TLS-encrypted endpoint managed by the internal Step-CA.

This plan details every required change, providing a clear roadmap for this strategic transition.

---

## Phase 1: Centralized Certificate Management

**Goal:** Integrate the Docker TLS certificates into the existing Step-CA infrastructure.

### 1.1. `usr/local/phoenix_hypervisor/etc/certificate-manifest.json`

*   **Action:** Add two new entries to the manifest: one for the Docker server certificate and one for the client certificate that Traefik will use.
*   **Details:**
    *   **Server Certificate:**
        *   `common_name`: `docker-daemon.internal.thinkheads.ai`
        *   `sans`: `10.0.0.111`
        *   `cert_path`: `/mnt/pve/quickOS/vm-persistent-data/1001/docker/certs/server-cert.pem`
        *   `key_path`: `/mnt/pve/quickOS/vm-persistent-data/1001/docker/certs/server-key.pem`
        *   `post_renewal_command`: `qm guest exec 1001 -- systemctl restart docker`
    *   **Client Certificate:**
        *   `common_name`: `traefik-client.internal.thinkheads.ai`
        *   `cert_path`: `/mnt/pve/quickOS/lxc-persistent-data/102/traefik/certs/client-cert.pem`
        *   `key_path`: `/mnt/pve/quickOS/lxc-persistent-data/102/traefik/certs/client-key.pem`
        *   `post_renewal_command`: `pct exec 102 -- systemctl restart traefik`

---

## Phase 2: Automated Certificate Deployment

**Goal:** Modify the feature scripts to automatically request and deploy the new certificates.

### 2.1. `usr/local/phoenix_hypervisor/bin/vm_features/feature_install_docker_proxy.sh`

*   **Action:** Remove the OpenSSL-based self-signed certificate generation.
*   **Action:** Add a call to the `certificate-renewal-manager.sh` script to request the `docker-daemon.internal.thinkheads.ai` certificate from Step-CA.
*   **Action:** Update the `daemon.json` creation to reference the new certificate paths and configure the Docker daemon for TLS on port `2376`.

### 2.2. `usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_traefik.sh`

*   **Action:** Add a step to copy the `ca.pem`, `client-cert.pem`, and `client-key.pem` from the shared certificate store to the Traefik container's `/etc/traefik/certs` directory.
*   **Action:** Add a step to set `chmod 600` on the copied certificate files.

---

## Phase 3: Service Reconfiguration

**Goal:** Update the Traefik and Docker configurations to use the new secure endpoint.

### 3.1. `usr/local/phoenix_hypervisor/etc/traefik/traefik.yml.template`

*   **Action:** Change the `endpoint` in the `docker` provider to `tcp://10.0.0.111:2376`.
*   **Action:** Add the `tls` section to the `docker` provider, referencing the paths to the new client certificates.

---

## Phase 4: Network Security Hardening

**Goal:** Update the firewall rules to reflect the new secure communication channel.

### 4.1. `usr/local/phoenix_hypervisor/etc/phoenix_vm_configs.json`

*   **Action:** In the firewall rules for VM 1001, locate the rule that allows inbound traffic on port `2375`.
*   **Action:** Change the port to `2376`.

### 4.2. `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`

*   **Action:** In the firewall rules for LXC 102, locate the rule that allows outbound traffic to port `2375`.
*   **Action:** Change the port to `2376`.

---

## Phase 5: Execution and Verification

**Goal:** Apply all changes and verify the successful implementation.

1.  **Execute `phoenix sync all`:** This will trigger the updated scripts, generate the new certificates, and reconfigure all services.
2.  **Verify Traefik Logs:** Check the logs in LXC 102 to confirm that Traefik starts without errors and establishes a successful connection to the Docker Swarm.
3.  **Verify Portainer UI:** Access the Portainer web interface to confirm that it is accessible and that all Swarm services are correctly displayed.

This comprehensive plan ensures a seamless and secure transition, fully integrating the Docker and Traefik components with your existing PKI infrastructure.
