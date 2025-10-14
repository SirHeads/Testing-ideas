# DNS and Certificate Trust Chain Audit Plan

## 1. Objective

This document outlines a systematic audit to definitively diagnose the root cause of the "Invalid environment name" error occurring during Portainer environment creation. The audit will verify DNS resolution and TLS certificate trust at every layer of the Phoenix Hypervisor stack, from the Proxmox host down to the Portainer container.

## 2. Audit Steps

The audit will be conducted in two phases: DNS Resolution and Certificate Trust Chain.

### 2.1. Phase 1: DNS Resolution Audit

This phase will verify that the FQDN `agent.agent.phoenix.local` can be resolved at each layer of the system.

| Step | Layer | Command | Expected Outcome |
|---|---|---|---|
| 1.1 | Proxmox Host | `nslookup agent.agent.phoenix.local` | Resolves to `10.0.0.102` |
| 1.2 | DNS Server (LXC 101) | `pct exec 101 -- nslookup agent.agent.phoenix.local` | Resolves to `10.0.0.102` |
| 1.3 | Portainer VM (1001) | `qm guest exec 1001 -- nslookup agent.agent.phoenix.local` | Resolves to `10.0.0.102` |
| 1.4 | Portainer Container | `qm guest exec 1001 -- docker exec <ID> nslookup agent.agent.phoenix.local` | Resolves to `10.0.0.102` |

### 2.2. Phase 2: Certificate Trust Chain Audit

This phase will verify that the certificate presented by the Portainer agent is trusted at each layer.

| Step | Layer | Command | Expected Outcome |
|---|---|---|---|
| 2.1 | Proxmox Host | `openssl s_client -connect 10.0.0.102:9001 -CAfile /path/to/ca.crt` | `Verify return code: 0 (ok)` |
| 2.2 | Portainer VM (1001) | `qm guest exec 1001 -- openssl s_client -connect 10.0.0.102:9001 -CAfile /path/to/ca.crt` | `Verify return code: 0 (ok)` |
| 2.3 | Portainer Container | `qm guest exec 1001 -- docker exec <ID> openssl s_client -connect 10.0.0.102:9001 -CAfile /path/to/ca.crt` | `Verify return code: 0 (ok)` |

## 3. Execution

Upon your approval of this plan, I will request to switch to the `code` role to execute these commands and gather the results. The results will be presented to you for review before any further action is taken.