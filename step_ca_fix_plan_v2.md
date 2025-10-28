# Step CA Initialization Fix Plan v2

## 1. Summary of the Problem

The `phoenix-cli` fails during the creation of LXC container `101` because it's stuck waiting for the Step CA root certificate from container `103`. The investigation revealed two root causes affecting core infrastructure containers (`101`, `102`, and `103`):

1.  **Incorrect Volume Configuration:** The `phoenix_lxc_configs.json` file uses `zfs_volumes` instead of `mount_points` for persistent SSL and log directories. This causes new, empty volumes to be created inside the containers instead of mounting the shared directories from the hypervisor. This affects containers `101` (Nginx), `102` (Traefik), and `103` (Step CA).
2.  **Hardcoded IP Address:** The `lxc-manager.sh` script uses a hardcoded IP address (`10.0.0.10`) to check the status of the Step CA service, which is not a robust solution.

## 2. Proposed Solution

To resolve this issue, I will make the following changes:

### 2.1. Update `phoenix_lxc_configs.json`

I will replace the `zfs_volumes` with the correct `mount_points` configuration for containers `101`, `102`, and `103`.

**File:** `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`

**Changes:**

```diff
--- a/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json
+++ b/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json
@@ -523,20 +523,18 @@
                      }
                  ]
              },
-             "zfs_volumes": [
-                 {
-                     "name": "nginx_logs",
-                     "pool": "quickOS-lxc-persistent-data",
-                     "size_gb": 1,
-                     "mount_point": "/logs/nginx"
-                 },
-                 {
-                     "name": "nginx_ssl",
-                     "pool": "quickOS-lxc-persistent-data",
-                     "size_gb": 1,
-                     "mount_point": "/etc/nginx/ssl"
-                 }
-             ]
+            "mount_points": [
+                {
+                    "host_path": "/mnt/pve/quickOS/lxc-persistent-data/101/logs",
+                    "container_path": "/var/log/nginx"
+                },
+                {
+                    "host_path": "/mnt/pve/quickOS/lxc-persistent-data/101/ssl",
+                    "container_path": "/etc/nginx/ssl"
+                }
+            ]
          },
          "914": {
              "name": "ollama-gpu0",
@@ -715,13 +713,12 @@
                      }
                  ]
              },
-             "zfs_volumes": [
-                 {
-                     "name": "step_ca_ssl",
-                     "pool": "quickOS-lxc-persistent-data",
-                     "size_gb": 1,
-                     "mount_point": "/etc/step-ca/ssl"
-                 }
-             ]
+            "mount_points": [
+                {
+                    "host_path": "/mnt/pve/quickOS/lxc-persistent-data/103/ssl",
+                    "container_path": "/etc/step-ca/ssl"
+                }
+            ]
          },
          "102": {
              "name": "Traefik-Internal",
@@ -835,13 +832,12 @@
              "lxc_options": [
                  "lxc.apparmor.profile=unconfined"
              ],
-             "zfs_volumes": [
-                 {
-                     "name": "traefik_ssl",
-                     "pool": "quickOS-lxc-persistent-data",
-                     "size_gb": 1,
-                     "mount_point": "/etc/traefik/certs"
-                 }
-             ]
+            "mount_points": [
+                {
+                    "host_path": "/mnt/pve/quickOS/lxc-persistent-data/102/certs",
+                    "container_path": "/etc/traefik/certs"
+                }
+            ]
          }
      }
  }

```

### 2.2. Update `lxc-manager.sh`

I will modify the `wait_for_ca_certificate` function to dynamically retrieve the IP address of the Step CA container.

**File:** `usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh`

**Change:**

```diff
--- a/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
+++ b/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
@@ -1406,12 +1406,14 @@
 wait_for_ca_certificate() {
      log_info "Waiting for Step CA (CTID 103) root certificate..."
      local ca_root_cert_path="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_ca.crt"
+    local step_ca_ip=$(jq_get_value "103" ".network_config.ip" | cut -d'/' -f1)
      local max_retries=30 # 30 retries * 10 seconds = 5 minutes timeout
      local retry_delay=10
      local attempt=1
  
      while [ "$attempt" -le "$max_retries" ]; do
-         if [ -f "$ca_root_cert_path" ] && nc -z 10.0.0.10 9000; then
+        if [ -f "$ca_root_cert_path" ] && nc -z "$step_ca_ip" 9000; then
              log_success "Root CA certificate found and service is listening on port 9000."
              return 0
          fi
```

## 3. Next Steps

Please review this updated plan. If you approve, I will switch to `code` mode to apply the changes.