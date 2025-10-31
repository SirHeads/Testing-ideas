# Remediation Plan: Nginx Firewall DNS Egress

## 1. Problem Analysis

The Nginx container (101) is unable to resolve internal hostnames, despite being configured with the correct DNS server (`10.0.0.13`). This is because the container's firewall is blocking outbound DNS traffic.

## 2. Proposed Solution

The solution is to add a new firewall rule to the Nginx container's configuration in `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`. This rule will explicitly allow outbound UDP traffic on port 53 to the DNS server.

## 3. Implementation Steps

1.  **Modify `phoenix_lxc_configs.json`:**
    *   Locate the `firewall.rules` array for LXC container `101`.
    *   Add a new rule to allow outbound UDP traffic to `10.0.0.13` on port `53`.

2.  **Switch to Code Mode:** Request a switch to the `code` persona to apply the necessary changes to the `phoenix_lxc_configs.json` file.

## 4. Validation

After the fix is applied, the user will re-run the `phoenix sync all` command. We will monitor the output to confirm that the Portainer authentication succeeds and the `sync` process completes successfully.