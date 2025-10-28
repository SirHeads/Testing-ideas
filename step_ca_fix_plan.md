# Step-CA Health Check Fix Plan

## 1. Problem Summary

The `check_step_ca.sh` health check is failing due to a TLS certificate validation error. The script uses `https://127.0.0.1:9000` to check the service's health, but the certificate is not valid for the IP address `127.0.0.1`.

**Error Message:**
```
client GET https://127.0.0.1:9000/health failed: tls: failed to verify certificate: x509: cannot validate certificate for 127.0.0.1 because it doesn't contain any IP SANs
```

## 2. Proposed Solution

The solution is to update the `check_step_ca.sh` script to use the correct DNS name, `ca.internal.thinkheads.ai`, which is present in the certificate.

## 3. Implementation Details

The following change will be made to `usr/local/phoenix_hypervisor/bin/health_checks/check_step_ca.sh`:

**Current Code (Line 70):**
```bash
if ! step ca health --ca-url "https://127.0.0.1:9000" --root "/root/.step/certs/root_ca.crt"; then
```

**Proposed Change:**
```bash
if ! step ca health --ca-url "https://ca.internal.thinkheads.ai:9000" --root "/root/.step/certs/root_ca.crt"; then
```

This change ensures the health check correctly validates the service using its designated DNS name.