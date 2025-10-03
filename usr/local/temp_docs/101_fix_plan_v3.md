# Implementation Plan (v3): Redefining LXC Container 101 (Nginx Gateway)

## 1. Overview

This document outlines the final, definitive plan to resolve the Nginx setup failure in container 101. After a thorough root cause analysis, the issue has been identified as a missing module activation step, not a package installation or file transfer problem.

This plan will ensure the Nginx Javascript (NJS) module is correctly installed **and loaded**, which will resolve the `unknown directive "js_include"` error.

## 2. The Final, Corrected `phoenix_hypervisor_lxc_101.sh` Script

The following change is the only one required. It modifies the `/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_101.sh` script to add the crucial module loading step.

**The change involves adding a `sed` command to insert the `load_module` directive into `/etc/nginx/nginx.conf` immediately after `nginx-extras` is installed.**

```diff
--- a/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_101.sh
+++ b/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_101.sh
@@ -13,6 +13,12 @@
 echo "Updating package lists and installing Nginx with extra modules (including NJS)..."
 apt-get update
 apt-get install -y nginx-extras
+
+# --- Nginx Module Activation ---
+echo "Activating Nginx Javascript (NJS) module..."
+NGINX_CONF="/etc/nginx/nginx.conf"
+LOAD_MODULE_LINE="load_module /usr/lib/nginx/modules/ngx_http_js_module.so;"
+sed -i "1i${LOAD_MODULE_LINE}" "$NGINX_CONF" || { echo "Failed to activate NJS module." >&2; exit 1; }
 
 # --- Config Extraction from Tarball ---
 TMP_DIR="/tmp/phoenix_run"

```

## 3. Next Steps

1.  Approve this final plan.
2.  Switch to Code mode to apply this single, targeted fix.
3.  Re-run the `phoenix create 101` command, which will now succeed.