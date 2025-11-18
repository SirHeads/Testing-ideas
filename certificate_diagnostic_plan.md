# Certificate Diagnostic Plan

This plan outlines the steps to gather detailed information about the TLS certificate chain of trust between Traefik (LXC 102) and the Docker daemon (VM 1001).

## Objective

To definitively identify the root cause of the TLS handshake failure by inspecting the permissions, ownership, and content of all relevant certificates and keys on the live system.

## Diagnostic Commands

Please execute the following commands on the Proxmox host and paste the complete, unedited output back for analysis.

### 1. CA Certificate (LXC 103)

This command will verify the permissions and ownership of the root CA certificate, which is the foundation of the trust chain.

```bash
echo "--- CA Certificate Details (LXC 103) ---"
pct exec 103 -- ls -l /etc/step-ca/ssl/certs/root_ca.crt
```

### 2. Docker Daemon Certificates (VM 1001)

These commands will inspect the server-side certificates used by the Docker daemon.

```bash
echo "--- Docker Daemon Certificate Details (VM 1001) ---"
# Check permissions and ownership of the certs on the hypervisor's shared storage
ls -l /mnt/pve/quickOS/vm-persistent-data/1001/docker/certs/

# Inspect the SANs of the server certificate
echo "--- Docker Daemon Server Certificate SANs ---"
openssl x509 -in /mnt/pve/quickOS/vm-persistent-data/1001/docker/certs/server-cert.pem -noout -text | grep -A1 "Subject Alternative Name"
```

### 3. Traefik Client Certificates (LXC 102)

These commands will inspect the client-side certificates used by Traefik.

```bash
echo "--- Traefik Certificate Details (LXC 102) ---"
# Check permissions and ownership of the certs inside the container
pct exec 102 -- ls -l /etc/traefik/certs/

# Inspect the SANs of the client certificate
echo "--- Traefik Client Certificate SANs ---"
openssl x509 -in /mnt/pve/quickOS/lxc-persistent-data/102/certs/client-cert.pem -noout -text | grep -A1 "Subject Alternative Name"
```

### 4. Manual TLS Handshake Test (from LXC 102)

This is the most critical test. It simulates the exact TLS connection that Traefik is failing to make, but with verbose output from `openssl` that will tell us precisely why the handshake is failing.

```bash
echo "--- Manual TLS Handshake from Traefik to Docker Daemon ---"
pct exec 102 -- openssl s_client -connect 10.0.0.111:2376 \
    -CAfile /etc/traefik/certs/ca.pem \
    -cert /etc/traefik/certs/client-cert.pem \
    -key /etc/traefik/certs/client-key.pem