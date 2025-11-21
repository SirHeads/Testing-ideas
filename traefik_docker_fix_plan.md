# Traefik mTLS Configuration Fix Plan (v2)

## 1. Problem Analysis

The `phoenix sync all` command completes, and all Docker Swarm services are healthy. However, accessing any internal service via the Nginx gateway results in a `502 Bad Gateway` error.

**Root Cause:** The Traefik logs show a persistent error, `unknown TLS options: require-mtls@file`. This indicates that the static Traefik configuration (`traefik.yml`) is attempting to use a named TLS option that has not been defined.

## 2. Refined Solution Analysis

The `phoenix-cli` infrastructure already provides a robust, IaC-driven mechanism for certificate management that we can leverage:
- The `phoenix_lxc_configs.json` defines a mount point for `LXC 102` that maps the host's Step-CA SSL directory (`/mnt/pve/quickOS/lxc-persistent-data/103/ssl`) to `/etc/step-ca/ssl` inside the Traefik container.
- This means the root CA certificate (`phoenix_root_ca.crt`) is already reliably available inside the Traefik container at `/etc/step-ca/ssl/phoenix_root_ca.crt`.

The most elegant and compliant solution is to modify the `traefik.yml.template` to use this existing file path directly to enforce mTLS on the `mesh` entrypoint, rather than creating a separate named TLS option.

## 3. Detailed Plan

### Step 1: Propose the Corrected `traefik.yml.template`

We will replace the faulty `mesh` entrypoint configuration with the correct, Traefik v3 compliant mTLS definition that points directly to the mounted CA file.

**File to Modify:** [`/usr/local/phoenix_hypervisor/etc/traefik/traefik.yml.template`](/usr/local/phoenix_hypervisor/etc/traefik/traefik.yml.template)

**Proposed Change:**

Replace this block:
```yaml
  mesh:
    address: ":8443"
    transport:
      respondingTimeouts:
        readTimeout: 60s
        writeTimeout: 60s
        idleTimeout: 300s
    http:
      tls:
        options: require-mtls
```

With this block:
```yaml
  mesh:
    address: ":8443"
    http:
      tls:
        clientCA:
          files:
            - /etc/step-ca/ssl/phoenix_root_ca.crt
        clientAuthType: RequireAndVerifyClientCert
```

### Step 2: Apply the Fix

A `code` mode agent will apply the proposed change to the `traefik.yml.template` file using a precise `apply_diff` operation.

### Step 3: Re-run System Convergence

After the file is updated, we will re-run the `phoenix sync all` command. This will propagate the corrected configuration into the Traefik container (`LXC 102`) and restart the service, allowing it to correctly build all mTLS-enabled routes.

### Step 4: Final Validation

To confirm the fix, we will execute a validation command that curls the Portainer endpoint. A successful `200 OK` response with JSON output will verify that the entire routing path is functional.

**Validation Command:**
```bash
curl --cacert /mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt https://portainer.internal.thinkheads.ai/api/system/status
```

## 4. Next Steps

This plan is now finalized. I will proceed immediately to **Step 2: Apply the Fix**.
