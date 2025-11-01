# Firewall Remediation Plan

## 1. Diagnosis

The `phoenix-cli --sync all` command is failing due to a malformed firewall rule in `/etc/pve/firewall/cluster.fw`. The rule `IN ACCEPT iface vmbr0` is syntactically incorrect and redundant.

The Proxmox firewall requires more specific parameters than just an interface for `IN` rules. Furthermore, the existing rule `IN ACCEPT -source 10.0.0.0/24 -dest 10.0.0.0/24` already allows all necessary internal traffic on the `vmbr0` bridge.

## 2. Remediation

The invalid rule will be removed from the `global_firewall_rules` section of `usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json`.

## 3. Validation

After the change is applied, the `phoenix-cli --sync all` command will be re-run. We will verify that:
1.  The command completes without any firewall-related errors.
2.  The original ACME challenge issue is resolved, and certificates are being issued successfully.

## 4. Rollback

In the event of a failure, the change to `phoenix_hypervisor_config.json` can be reverted.