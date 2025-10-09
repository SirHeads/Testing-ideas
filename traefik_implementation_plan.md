# Nginx and Traefik Implementation Plan

This document outlines the necessary steps to resolve the certificate generation failure in the Nginx container (LXC 101) and to implement the Traefik container (LXC 102) for internal service routing.

## Part 1: Fix the Nginx (LXC 101) Deployment

The current deployment of the Nginx container fails because of a logical flaw in how it attempts to bootstrap trust with the Step CA, compounded by the fact that the root CA certificate is not being placed in a shared location. We will address this with a two-pronged approach.

### 1.1: Correct the Step CA Bootstrap Logic

The script `phoenix_hypervisor_lxc_101.sh` incorrectly tries to fetch the CA fingerprint over the network, which requires the fingerprint to begin with. The correct approach is to read the fingerprint from the root CA certificate file that is mounted into the container.

**Action:** Modify `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_101.sh`.

**The `generate_nginx_certs` function will be updated to:**
1.  Remove the flawed network-based fingerprint retrieval loop.
2.  Go directly to the logic that reads the fingerprint from the `phoenix_ca.crt` file located in the mounted `/etc/nginx/ssl` directory.

This change will make the certificate generation process reliable and dependent only on the presence of the root CA certificate.

### 1.2: Export the Root CA Certificate from Step CA (LXC 103)

The root cause of the missing certificate is that the `phoenix_ca.crt` file, which is generated inside the Step CA container (LXC 103), is never exported to the hypervisor's shared storage. We need to add a step to the orchestration to handle this.

**Action:** Modify the `lxc-manager.sh` script to add a post-creation step for CTID 103.

**The `main_lxc_orchestrator` function in `usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh` will be updated to:**
1.  After the successful creation of LXC 103, add a specific block of code: `if [ "$ctid" -eq 103 ]; then ... fi`.
2.  Inside this block, use `pct pull` to copy the generated root certificate from inside the container (`/home/step/certs/root_ca.crt`) to the hypervisor's persistent storage directory (`/usr/local/phoenix_hypervisor/persistent-storage/ssl/phoenix_ca.crt`).

This ensures that after the CA is created, its public root certificate is immediately made available to any other container that needs to trust it.

---

## Part 2: Plan the Traefik (LXC 102) Implementation

With the certificate infrastructure corrected, we can proceed with the implementation of the Traefik container. This will involve defining the container's configuration and creating an application script to set it up.

### 2.1: Configure the Traefik Container

The Traefik container (LXC 102) will be defined in `phoenix_lxc_configs.json`. It will be a standard container cloned from the base template, with the addition of the `traefik` feature.

**Action:** Update the `lxc_configs` object in `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`.

**The configuration for CTID 102 will include:**
- `name`: "Traefik-Internal"
- `clone_from_ctid`: "900"
- `features`: `["base_setup", "traefik"]`
- `application_script`: "phoenix_hypervisor_lxc_102.sh"
- `dependencies`: `["103"]` (to ensure the Step CA is available)
- Standard resource and network configurations.

### 2.2: Create the Traefik Application Script

The `phoenix_hypervisor_lxc_102.sh` script will be responsible for the final configuration of Traefik inside the container. This will include setting up the connection to the Step CA for automatic certificate generation.

**Action:** Create the file `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_102.sh`.

**The script will perform the following steps:**
1.  **Install `step-cli`:** Just like the Nginx script, it will first ensure the `step-cli` is installed.
2.  **Bootstrap Traefik with Step CA:** It will use `step ca bootstrap` with the CA URL and fingerprint (read from the mounted `phoenix_ca.crt`) to configure the `step` client.
3.  **Configure Traefik:** It will create the main `traefik.yml` configuration file, defining the entrypoints (e.g., `websecure` on port 443) and the ACME provider, pointing it to the Step CA.
4.  **Start Traefik:** It will enable and start the Traefik service.

This will result in a fully functional Traefik instance that can automatically provision TLS certificates for any internal services it exposes.

---

This completes the plan. Once you approve, we can switch to `code` mode to implement these changes.
