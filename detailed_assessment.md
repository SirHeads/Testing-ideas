# Phoenix Hypervisor: Detailed Assessment and Diagnostic Plan

## 1. Introduction

This document builds upon the initial `assessment.md` and outlines a concrete plan for implementing diagnostic checks to validate our primary hypotheses:

1.  **Hypothesis 1: Broken Certificate Chain of Trust:** Failures in TLS handshakes between services due to improperly configured or untrusted certificates from the internal Step-CA.
2.  **Hypothesis 2: Firewall and Network Connectivity Issues:** Misconfigured firewall rules are blocking essential communication between the Nginx gateway, the Traefik mesh, the Step-CA, and backend services.

The following plan will introduce targeted logging and a suite of health check scripts to provide clear evidence of where the system is failing.

## 2. Diagnostic Plan

### Phase 1: Certificate Chain of Trust Validation

The goal of this phase is to verify that every component in the chain can obtain a valid certificate from the Step-CA and trust the certificates presented by other components.

**Task 1.1: Enhance Step-CA Health Checks (LXC 103)**
*   **Action:** I will create a dedicated health check script `check_step_ca.sh`.
*   **Details:** This script will be executed from the hypervisor and will:
    1.  Verify the `step-ca` service is running inside the container.
    2.  Check that the CA is listening on port 9000.
    3.  Use the `step` CLI to check the health of the CA endpoint.
    4.  Confirm that the ACME provisioner is active and correctly configured.
    5.  Verify that the root CA certificate has been successfully exported to the shared NFS volume.

**Task 1.2: Implement Traefik Certificate Validation (LXC 102)**
*   **Action:** I will create a health check script `check_traefik_proxy.sh`.
*   **Details:** This script will:
    1.  Verify the `traefik` service is running.
    2.  Check the Traefik logs for errors related to the ACME resolver and certificate acquisition.
    3.  Use `openssl s_client` from within the container to connect to its own dashboard (`traefik.internal.thinkheads.ai`) to ensure it's serving a valid, trusted certificate.

**Task 1.3: Implement Nginx to Traefik TLS Validation (LXC 101)**
*   **Action:** I will create a health check script `check_nginx_gateway.sh`.
*   **Details:** This script will:
    1.  Verify the `nginx` service is running.
    2.  Use `openssl s_client` from within the Nginx container to connect to the Traefik container's secure entrypoint (`10.0.0.12:8443`).
    3.  This test will validate that Nginx trusts the certificate being presented by Traefik, which is a critical step in the proxy chain.

### Phase 2: Firewall and Network Connectivity Analysis

The goal of this phase is to ensure that there are no black holes in the network where packets are being dropped silently by the firewall.

**Task 2.1: Enhance Firewall Logging**
*   **Action:** I will prepare a diff to temporarily modify `usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json`.
*   **Details:** I will add a `log_level` property to the firewall rules. This will instruct `pve-firewall` to log accepted and dropped packets to the hypervisor's syslog (`/var/log/syslog`), giving us visibility into the firewall's decisions.

**Task 2.2: Create a Comprehensive Connectivity Check Script**
*   **Action:** I will create a master health check script `check_firewall.sh`.
*   **Details:** This script will be run from the hypervisor and will perform a matrix of connectivity tests between all critical components using `nc` (netcat) to check for open ports. This will test:
    *   **Nginx (101) -> Traefik (102)** on ports `80` and `8443`.
    *   **Traefik (102) -> Step-CA (103)** on port `9000`.
    *   **Nginx (101) -> Step-CA (103)** on port `9000`.
    *   **Traefik (102) -> Portainer VM (1001)** on port `9443`.
    *   **All containers -> DNS Server (Hypervisor)** on port `53`.

## 3. Confirmation Request

This diagnostic plan is designed to be non-destructive and will provide the necessary data to confirm our diagnosis. The logs and health check results will allow us to move from speculation to a data-driven solution.

Do you confirm this diagnosis and approve of me proceeding with the implementation of these diagnostic checks?