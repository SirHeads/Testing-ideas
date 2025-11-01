# DNS and Firewall Remediation Plan

This plan outlines the necessary changes to resolve the DNS and firewall issues that are causing the ACME challenge failures.

## 1. Correct `ca.internal.thinkheads.ai` DNS Record

The `ca.internal.thinkheads.ai` DNS record must be updated to point to the Step-CA container's IP address (`10.0.0.10`) instead of the Traefik container's IP address (`10.0.0.12`).

**File to Modify:** `usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh`

**Change:**

```diff
--- a/usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh
+++ b/usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh
@@ -82,7 +82,7 @@
- "ip": (if .traefik_service.name == "ca" then $traefik_ip else (.network_config.ip | split("/")[0]) end)
+ "ip": (if .traefik_service.name == "ca" then "10.0.0.10" else (.network_config.ip | split("/")[0]) end)
```

## 2. Add Missing DNS Records

DNS records for `portainer.internal.thinkheads.ai` and `portainer-agent.internal.thinkheads.ai` must be added to the `hypervisor_feature_setup_dns_server.sh` script.

**File to Modify:** `usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh`

**Change:**

```diff
--- a/usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh
+++ b/usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh
@@ -107,6 +107,14 @@
+            {
+                "hostname": "portainer.internal.thinkheads.ai",
+                "ip": $traefik_ip
+            },
+            {
+                "hostname": "portainer-agent.internal.thinkheads.ai",
+                "ip": $traefik_ip
+            },
             # 5. Add a static record for the Traefik dashboard itself
             {
                 "hostname": "traefik.internal.thinkheads.ai",

```

## 3. Add Firewall Rule for Traefik Websecure Entrypoint

A firewall rule must be added to allow inbound traffic to Traefik's websecure entrypoint (port 8443).

**File to Modify:** `usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json`

**Change:**

```diff
--- a/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json
+++ b/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json
@@ -490,6 +490,14 @@
                     "port": "80,443,8443",
                     "comment": "Allow hypervisor host to access Traefik directly"
                 }
+                {
+                    "type": "in",
+                    "action": "ACCEPT",
+                    "source": "10.0.0.10",
+                    "proto": "tcp",
+                    "port": "8443",
+                    "comment": "Allow Step-CA to perform ACME TLS-ALPN challenges with Traefik"
+                }
             ]
         }
     },

```

## 4. Mermaid Diagram of Proposed Changes

```mermaid
graph TD
    subgraph "DNS Remediation"
        A["Correct ca.internal.thinkheads.ai DNS record"] --> B["Add DNS records for Portainer and Portainer Agent"];
    end
    subgraph "Firewall Remediation"
        C["Add firewall rule for Traefik websecure entrypoint"]
    end
    A --> C;
