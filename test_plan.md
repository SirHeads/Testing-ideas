# Comprehensive Test Plan

## 1. Introduction

This document outlines a comprehensive test plan to validate the changes made to the Step-CA integration and firewall configurations. The goal is to ensure that all components are communicating correctly and that the system is stable and secure.

## 2. Test Cases

The following test cases will be executed after the containers and VMs have been recreated:

### 2.1. Step-CA Health Check

*   **Objective:** Verify that the Step-CA service is running and healthy.
*   **Steps:**
    1.  Exec into LXC 103: `pct exec 103 -- /bin/bash`
    2.  Run the Step-CA health check: `step ca health`
*   **Expected Result:** The command should return `ok`.

### 2.2. Nginx Certificate Acquisition

*   **Objective:** Verify that the Nginx container can obtain a certificate from the Step-CA.
*   **Steps:**
    1.  Exec into LXC 101: `pct exec 101 -- /bin/bash`
    2.  Check for the existence of the certificate and key files: `ls /etc/nginx/ssl`
*   **Expected Result:** The directory should contain `phoenix.thinkheads.ai.crt` and `phoenix.thinkheads.ai.key`.

### 2.3. Traefik Certificate Acquisition

*   **Objective:** Verify that the Traefik container can obtain a certificate from the Step-CA.
*   **Steps:**
    1.  Exec into LXC 102: `pct exec 102 -- /bin/bash`
    2.  Check the Traefik logs for messages related to ACME and certificate acquisition: `journalctl -u traefik`
*   **Expected Result:** The logs should show that Traefik has successfully obtained a certificate for `traefik.internal.thinkheads.ai`.

### 2.4. Portainer UI Accessibility

*   **Objective:** Verify that the Portainer UI is accessible through the Nginx and Traefik proxies.
*   **Steps:**
    1.  From a machine on the same network, open a web browser and navigate to `https://portainer.phoenix.thinkheads.ai`.
*   **Expected Result:** The Portainer login page should be displayed.

### 2.5. Portainer Agent Connectivity

*   **Objective:** Verify that the Portainer server can connect to the agent on VM 1002.
*   **Steps:**
    1.  Log in to the Portainer UI.
    2.  Navigate to the "Endpoints" section.
*   **Expected Result:** The `dr-phoenix` endpoint should show a status of "up".

## 3. Next Steps

Once this test plan is approved, I will proceed with the remediation steps outlined in the main plan.