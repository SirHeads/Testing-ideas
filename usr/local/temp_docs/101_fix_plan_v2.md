# Implementation Plan (v2): Redefining LXC Container 101 (Nginx Gateway)

## 1. Overview

This document outlines the revised, robust plan to redefine and redeploy LXC container 101. This plan replaces the previous fragile file-copying mechanism with a reliable, industry-standard tarball-based approach.

## 2. Proposed Changes

### 2.1. `lxc-manager.sh`: Create and Push Tarball

The `run_application_script` function in `/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh` will be modified. The failing `pct push` logic for the Nginx directories will be replaced with logic to create, push, and then clean up a tarball.

**New Logic for `lxc-manager.sh`:**

```diff
--- a/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
+++ b/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
@@ -765,28 +765,23 @@
     fi
 
     # --- START OF MODIFICATIONS FOR NGINX CONFIG PUSH ---
     # If the application script is for the Nginx gateway (101), push the necessary configs.
     if [[ "$app_script_name" == "phoenix_hypervisor_lxc_101.sh" ]]; then
-        log_info "Nginx gateway script detected. Pushing configuration files..."
-        
-        # Push the sites-available directory
-        local sites_available_path="${PHOENIX_BASE_DIR}/etc/nginx/sites-available"
-        if ! pct push "$CTID" "$sites_available_path" "${temp_dir_in_container}"; then
-            log_fatal "Failed to push Nginx sites-available directory to container $CTID."
-        fi
+        log_info "Nginx gateway script detected. Packaging and pushing configuration files..."
+        local nginx_config_path="${PHOENIX_BASE_DIR}/etc/nginx"
+        local temp_tarball="/tmp/nginx_configs_${CTID}.tar.gz"
 
-        # Push the scripts directory
-        local scripts_path="${PHOENIX_BASE_DIR}/etc/nginx/scripts"
-        if ! pct push "$CTID" "$scripts_path" "${temp_dir_in_container}"; then
-            log_fatal "Failed to push Nginx scripts directory to container $CTID."
-        fi
+        # Create a tarball of the nginx configs on the host
+        log_info "Creating tarball of Nginx configs at ${temp_tarball}"
+        if ! tar -czf "${temp_tarball}" -C "${nginx_config_path}" sites-available scripts; then
+            log_fatal "Failed to create Nginx config tarball."
+        fi
+
+        # Push the single tarball to the container
+        if ! pct push "$CTID" "$temp_tarball" "${temp_dir_in_container}/nginx_configs.tar.gz"; then
+            log_fatal "Failed to push Nginx config tarball to container $CTID."
+        fi
+
+        # Clean up the temporary tarball on the host
+        rm -f "$temp_tarball"
     fi
     # --- END OF MODIFICATIONS FOR NGINX CONFIG PUSH ---
 
```

### 2.2. `phoenix_hypervisor_lxc_101.sh`: Extract Tarball

The setup script `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_101.sh` will be modified to include a new step at the beginning that extracts the tarball.

**New Logic for `phoenix_hypervisor_lxc_101.sh`:**

```diff
--- a/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_101.sh
+++ b/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_101.sh
@@ -12,6 +12,13 @@
 apt-get update
 apt-get install -y nginx
 
+# --- Config Extraction from Tarball ---
+TMP_DIR="/tmp/phoenix_run"
+CONFIG_TARBALL="${TMP_DIR}/nginx_configs.tar.gz"
+
+echo "Extracting Nginx configurations from tarball..."
+tar -xzf "$CONFIG_TARBALL" -C "$TMP_DIR" || { echo "Failed to extract Nginx config tarball." >&2; exit 1; }
+
 # --- Config Copying from Temp Dir ---
 TMP_DIR="/tmp/phoenix_run"
 SITES_AVAILABLE_DIR="/etc/nginx/sites-available"

```

## 3. Next Steps

1.  Review and approve this new, robust plan.
2.  Switch to Code mode to implement the changes to both scripts.
3.  Execute the `lxc-manager.sh` script to create the new container 101.
4.  Verify that the new container is running and that the Nginx gateway is functioning correctly.