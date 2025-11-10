# Proposed Changes to Fix Step CA Health Check

This document outlines the necessary changes to fix the Step CA health check issue in container 801.

## 1. New Health Check Script

A new health check script, `check_step_ca_health.sh`, will be created in `usr/local/phoenix_hypervisor/bin/health_checks/`. This script will perform a network-based health check of the Step CA service.

```bash
#!/bin/bash
#
# File: check_step_ca_health.sh
# Description: This script performs a network-based health check of the Step CA service.
#
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- Source common utilities ---
source "$(dirname -- "${BASH_SOURCE[0]}")/../phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CA_URL="https://10.0.0.10:9000/health"
MAX_RETRIES=12
RETRY_DELAY=5

# =====================================================================================
# Function: main
# Description: Main entry point for the script.
# =====================================================================================
main() {
    log_info "Starting Step CA health check..."

    local attempt=1
    while [ "$attempt" -le "$MAX_RETRIES" ]; do
        log_info "Attempting to connect to Step CA at ${CA_URL} (Attempt ${attempt}/${MAX_RETRIES})..."
        
        local response
        response=$(curl -s -k --connect-timeout 5 "${CA_URL}")
        
        if [ "$?" -eq 0 ] && [ "$(echo "$response" | jq -r .status)" == "ok" ]; then
            log_success "Step CA is healthy and responsive."
            exit 0
        fi

        log_warn "Step CA not ready yet. Retrying in ${RETRY_DELAY} seconds..."
        sleep "$RETRY_DELAY"
        attempt=$((attempt + 1))
    done

    log_fatal "Step CA failed to become healthy after ${MAX_RETRIES} attempts."
}

# --- SCRIPT EXECUTION ---
main "$@"
```

## 2. Modify `phoenix_hypervisor_lxc_vllm.sh`

The `wait_for_ca` function in `phoenix_hypervisor_lxc_vllm.sh` will be modified to use the new health check script.

```diff
--- a/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_vllm.sh
+++ b/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_vllm.sh
@@ -98,16 +98,12 @@
 # =====================================================================================
 # Function: wait_for_ca
 # Description: Waits for the Step CA to be ready by checking for a file.
-# =====================================================================================
-wait_for_ca() {
-    log_info "Waiting for Step CA to become ready..."
-    while [ ! -f "${CA_READY_FILE}" ]; do
-        log_info "CA not ready yet. Waiting 5 seconds..."
-        sleep 5
-    done
-    log_success "Step CA is ready."
-}
-
+# =====================================================================================
+wait_for_ca() {
+    log_info "Waiting for Step CA to become ready..."
+    if ! /usr/local/phoenix_hypervisor/bin/health_checks/check_step_ca_health.sh; then
+        log_fatal "Step CA did not become healthy in time."
+    fi
+}
 # =====================================================================================
 # Function: bootstrap_step_cli
 # Description: Bootstraps the step CLI to trust the internal CA.

```

## 3. Modify `lxc-manager.sh`

The `run_application_script` function in `lxc-manager.sh` will be modified to push the new health check script into the container.

```diff
--- a/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
+++ b/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
@@ -945,6 +945,12 @@
     if ! pct push "$CTID" "$common_utils_source_path" "$common_utils_dest_path"; then
         log_fatal "Failed to copy common_utils.sh to container $CTID."
     fi
+
+    # 3b. Copy the new health check script to the container
+    local health_check_source_path="${PHOENIX_BASE_DIR}/bin/health_checks/check_step_ca_health.sh"
+    local health_check_dest_path="${temp_dir_in_container}/check_step_ca_health.sh"
+    log_info "Copying Step CA health check to $CTID:$health_check_dest_path..."
+    pct push "$CTID" "$health_check_source_path" "$health_check_dest_path" || log_fatal "Failed to copy Step CA health check script."
  
     # 3. Copy the application script to the container
     log_info "Copying application script to $CTID:$app_script_dest_path..."
