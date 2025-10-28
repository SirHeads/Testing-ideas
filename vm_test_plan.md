# Test Plan: VM & Docker Step CA Integration Verification

## 1. Objective
This plan verifies that the refactored VM and Docker provisioning process correctly integrates with the Traefik-managed, Step CA-powered certificate infrastructure. The primary goal is to confirm that Portainer (VM 1001) runs as a non-TLS service and is securely exposed via Traefik, which handles all TLS termination.

## 2. Prerequisites
- The Proxmox environment is clean.
- Destroy any existing guests that will be used in this test (101, 102, 103, 9000, 1001) to ensure a fresh deployment.
  ```bash
  phoenix-cli delete lxc 101 102 103
  phoenix-cli delete vm 9000 1001
  ```

## 3. Execution Steps
1.  **Deploy the Entire Stack:** Use the `LetsGo` command to create and start all defined guests in the correct dependency and boot order. This will build the template, the core LXC services, and finally the Portainer VM.
    ```bash
    phoenix-cli LetsGo
    ```
2.  **Synchronize Docker Stacks:** After the `LetsGo` command completes, run `phoenix sync all` to deploy the Portainer Docker stack.
    ```bash
    phoenix-cli sync all
    ```

## 4. Verification Steps

### 4.1. Verify Portainer Container is Running Without TLS
1.  **Access the Portainer VM's shell:**
    ```bash
    qm enter 1001
    ```
2.  **Inspect the running Portainer container.** Check the `COMMAND` column to ensure it is running without any `--tlsverify` flags.
    ```bash
    docker ps
    ```
    **Expected Outcome:** The command for the `portainer_server` container should be simply `-H unix:///var/run/docker.sock`.

### 4.2. Verify Traefik Log for Successful Certificate Acquisition
1.  **Access the Traefik container's shell:**
    ```bash
    pct enter 102
    ```
2.  **Check the Traefik service logs.** Look for messages indicating a successful ACME challenge and certificate acquisition for `portainer.phoenix.thinkheads.ai`.
    ```bash
    journalctl -u traefik -f --no-pager | grep "Certificate obtained"
    ```
    **Expected Outcome:** You should see log entries confirming that a certificate was successfully obtained for the Portainer service.

### 4.3. Verify Portainer Accessibility and Certificate
1.  **Access the Portainer UI:** From a machine on the internal network (e.g., the hypervisor), use `curl` to access the Portainer UI via its external, secure endpoint. The `--cacert` flag is used to explicitly trust our internal root CA.
    ```bash
    curl --cacert /mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt https://portainer.phoenix.thinkheads.ai
    ```
    **Expected Outcome:** You should receive the HTML content of the Portainer login page.

2.  **Inspect the Certificate Served by Traefik:** Use `openssl` to connect to the Traefik service and inspect the certificate it presents for the Portainer domain.
    ```bash
    openssl s_client -connect 10.0.0.12:443 -servername portainer.phoenix.thinkheads.ai -showcerts < /dev/null 2>/dev/null | openssl x509 -text -noout
    ```
    **Expected Outcome:** The output should show the certificate details, with the "Issuer" field pointing to "CN=ThinkHeads Internal CA" and the "Subject" containing "CN=portainer.phoenix.thinkheads.ai". This confirms Traefik is serving the correct, internally-issued certificate.

### 4.4. Verify Portainer Agent Accessibility and Certificate
1.  **Access the Portainer Agent Endpoint:** From a machine on the internal network, use `curl` to access the Portainer agent's `/ping` endpoint via its Traefik-managed, secure hostname.
    ```bash
    curl --cacert /mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt https://portainer-agent.internal.thinkheads.ai/ping
    ```
    **Expected Outcome:** The command should return a `204 No Content` status, which is the expected response from the agent's health check endpoint.

2.  **Inspect the Certificate Served by Traefik for the Agent:** Use `openssl` to connect to the Traefik service and inspect the certificate it presents for the Portainer agent domain.
    ```bash
    openssl s_client -connect 10.0.0.12:443 -servername portainer-agent.internal.thinkheads.ai -showcerts < /dev/null 2>/dev/null | openssl x509 -text -noout
    ```
    **Expected Outcome:** The output should show the certificate details, with the "Issuer" field pointing to "CN=ThinkHeads Internal CA" and the "Subject" containing "CN=portainer-agent.internal.thinkheads.ai". This confirms Traefik is serving the correct, internally-issued certificate for the agent.