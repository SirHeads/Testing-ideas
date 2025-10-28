# Step-CA Final Fix Plan v3

## 1. Diagnosis

The Step-CA service is now running correctly, but the application-level health check is failing with a TLS validation error: `x509: cannot validate certificate for 127.0.0.1 because it doesn't contain any IP SANs`.

This is because the health check connects to `127.0.0.1`, but the CA's certificate is not valid for this IP address.

## 2. The Fix

The solution is to add `127.0.0.1` to the list of names for which the CA's certificate is valid. This is done by adding it to the `--dns` flag in the `step ca init` command.

**File to Modify:** `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_103.sh`

**Change:**
Modify the `step ca init` command to include `127.0.0.1` in the list of DNS names.

## 3. Validation

After applying this change, the `phoenix create 103` command should be re-run. The `step ca init` command will now generate a certificate that is valid for `127.0.0.1`, and the final `step ca health` check will succeed.