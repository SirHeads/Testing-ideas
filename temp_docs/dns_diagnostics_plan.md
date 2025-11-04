# Final DNS Script Remediation Plan

This document contains the precise `diff` required to fix the DNS generation logic in `hypervisor_feature_setup_dns_server.sh`.

## The Elegant Solution

As per our discussion, this solution preserves the general `traefik_service` rule while surgically overriding the IP for the `portainer-agent` to ensure it gets its correct, direct IP address. This is achieved by reordering the `jq` query to ensure the specific agent rule is processed last, taking precedence.

## The `diff` to be Applied

The following `diff` should be applied to `usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh`.

```diff
--- a/usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh
+++ b/usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh
@@ -102,21 +102,21 @@
              ($vm_config.vms[] | select(.traefik_service.name?) | {
                  "hostname": "\(.traefik_service.name).internal.thinkheads.ai",
                  "ip": $gateway_ip
-             }),
+             }),
              # 3. Add records for all guests (LXC and VM) that need to be addressed by their own name
              ($lxc_config.lxc_configs | values[] | select(.name and .network_config.ip) | {
                  "hostname": "\(.name | ascii_downcase).internal.thinkheads.ai",
                  "ip": (.network_config.ip | split("/")[0])
-             }),
+             }),
              ($vm_config.vms[] | select(.name and .network_config.ip and .network_config.ip != "dhcp") | {
                  "hostname": "\(.name | ascii_downcase).internal.thinkheads.ai",
                  "ip": (.network_config.ip | split("/")[0])
-             }),
+             }),
              # 4. Add records for Portainer agents specifically
              ($vm_config.vms[] | select(.portainer_role == "agent") | {
                  "hostname": .portainer_agent_hostname,
                  "ip": (.network_config.ip | split("/")[0])
-             }),
+             })
              # 5. Add static records
              { "hostname": "portainer.internal.thinkheads.ai", "ip": $gateway_ip },
-             { "hostname": "portainer-agent.internal.thinkheads.ai", "ip": $gateway_ip },
              { "hostname": "traefik.internal.thinkheads.ai", "ip": $gateway_ip }
          ] | unique_by(.hostname)
          '

```

This change correctly removes the erroneous static record for the agent and ensures the dynamic rule that assigns the correct IP (`10.0.0.102`) takes precedence.