# Step CA Initialization Fix Plan v4

## 1. Summary of the Problem

After a thorough re-examination of the scripts, I've identified a critical logic flaw in `lxc-manager.sh`. The function responsible for creating the CA password file on the hypervisor is only called when the initial target is `101` or `103`. This means that if you run `phoenix create 103` directly, the password file is never created, causing the `run-step-ca.sh` script to fail.

## 2. Proposed Solution

To resolve this, I will modify the `lxc-manager.sh` script to ensure that the `manage_ca_password_on_hypervisor` function is always called when the `create` workflow is initiated for container `103`.

### 2.1. Update `lxc-manager.sh`

**File:** `usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh`

**Change:**

```diff
--- a/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
+++ b/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
@@ -1454,7 +1454,7 @@
                  wait_for_ca_certificate
              fi
  
-             if [ "$ctid" -eq 101 ] || [ "$ctid" -eq 103 ]; then
+             if [ "$ctid" -eq 103 ]; then
                  manage_ca_password_on_hypervisor "103"
                  manage_provisioner_password_on_hypervisor "103"
              fi
```

## 3. Next Steps

Please review this plan. If you approve, I will switch to `code` mode to apply the change.