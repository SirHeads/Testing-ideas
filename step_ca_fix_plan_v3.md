# Step CA Initialization Fix Plan v3

## 1. Summary of the Problem

After fixing the mount point and permissions issues, the `step-ca` service is still failing to start reliably. The logs show that the `step ca init` command is failing because a partial configuration already exists from previous failed attempts. The initialization script is not truly idempotent, causing it to fail if it's run more than once.

## 2. Proposed Solution

To resolve this, I will add the `--force` flag to the `step ca init` command in the `run-step-ca.sh` script. This will ensure that any existing partial configuration is overwritten, allowing the CA to initialize cleanly every time the script is run.

### 2.1. Update `run-step-ca.sh`

**File:** `usr/local/phoenix_hypervisor/bin/run-step-ca.sh`

**Change:**

```diff
--- a/usr/local/phoenix_hypervisor/bin/run-step-ca.sh
+++ b/usr/local/phoenix_hypervisor/bin/run-step-ca.sh
@@ -49,7 +49,7 @@
      step ca init --name "$root_ca_name" --provisioner "$provisioner_name" \
          --dns "$dns_name" --dns "phoenix.thinkheads.ai" --dns "*.phoenix.thinkheads.ai" --dns "*.internal.thinkheads.ai" \
          --address "$address" --password-file "${SSL_DIR}/ca_password.txt" --provisioner-password-file "${SSL_DIR}/provisioner_password.txt" \
-         --with-ca-url "https://${dns_name}:9000"
+         --with-ca-url "https://${dns_name}:9000" --force
  
      # Add ACME provisioner
      step ca provisioner add acme --type ACME
```

## 3. Next Steps

Please review this plan. If you approve, I will switch to `code` mode to apply the change.