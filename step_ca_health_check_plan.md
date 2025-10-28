# Step CA Health Check Implementation Plan

## 1. Summary

Based on your excellent suggestion, this plan refactors the startup logic to make the Step CA container (`103`) responsible for its own health check. This is a superior design that simplifies the creation process for dependent containers and provides more direct feedback if the CA fails to start.

## 2. Proposed Changes

### 2.1. Add Health Check to Container 103

I will add a `health_check` configuration to container `103` in the `phoenix_lxc_configs.json` file. This check will use `nc` (netcat) to verify that the `step-ca` service is listening on port 9000. The `lxc-manager.sh` script will automatically run this check at the end of the creation workflow for container `103`.

**File:** `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`

**Change:**

```diff
--- a/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json
+++ b/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json
@@ -715,6 +715,11 @@
                      "container_path": "/etc/step-ca/ssl"
                  }
              ]
+            "health_check": {
+                "command": "nc -z localhost 9000",
+                "retries": 30,
+                "interval": 10
+            }
          },
          "102": {
              "name": "Traefik-Internal",
```

### 2.2. Remove Wait Logic from `lxc-manager.sh`

With the health check now part of the `103` creation process, the `wait_for_ca_certificate` function in `lxc-manager.sh` is redundant. I will remove the function and the code that calls it.

**File:** `usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh`

**Changes:**

```diff
--- a/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
+++ b/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
@@ -1396,31 +1396,6 @@
      systemctl reload apparmor || log_warn "Failed to reload AppArmor profiles."
  }
  # =====================================================================================
-# Function: wait_for_ca_certificate
-# Description: Waits for the Step CA (CTID 103) to generate and export its root certificate.
-#              This is a critical synchronization point for containers that depend on the CA.
-# Arguments:
-#   None.
-# Returns:
-#   None. Exits with a fatal error if the certificate is not found after a timeout.
-# =====================================================================================
-wait_for_ca_certificate() {
-    log_info "Waiting for Step CA (CTID 103) root certificate..."
-    local ca_root_cert_path="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_ca.crt"
-    local step_ca_ip
-    step_ca_ip=$(jq_get_value "103" ".network_config.ip" | cut -d'/' -f1)
-    local max_retries=30 # 30 retries * 10 seconds = 5 minutes timeout
-    local retry_delay=10
-    local attempt=1
-
-    while [ "$attempt" -le "$max_retries" ]; do
-        if [ -f "$ca_root_cert_path" ] && nc -z "$step_ca_ip" 9000; then
-            log_success "Root CA certificate found and service is listening on port 9000."
-            return 0
-        fi
-        log_info "Attempt $attempt/$max_retries: Waiting for Step CA certificate and service. Retrying in $retry_delay seconds..."
-        sleep "$retry_delay"
-        attempt=$((attempt + 1))
-    done
-
-    log_fatal "Root CA certificate not found at $ca_root_cert_path after waiting. Cannot proceed."
-}
-
-# =====================================================================================
  # Function: main_lxc_orchestrator
  # Description: The main entry point for the LXC manager script. It parses the
  #              action and CTID, and then executes the appropriate lifecycle
@@ -1439,13 +1414,6 @@
      case "$action" in
          create)
              log_info "Starting 'create' workflow for CTID $ctid..."
- 
-             # Check for dependency on Step CA and wait for its certificate if needed
-             local dependencies
-             dependencies=$(jq_get_array "$ctid" "(.dependencies // [])[]" || echo "")
-             if echo "$dependencies" | grep -q "103"; then
-                 wait_for_ca_certificate
-             fi
  
              if [ "$ctid" -eq 103 ]; then
                  manage_ca_password_on_hypervisor "103"

```

## 3. Next Steps

Please review this new plan. If you approve, I will switch to `code` mode to implement these changes.