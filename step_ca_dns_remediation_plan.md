# Step-CA DNS and ACME Challenge Remediation Plan (v4 - Direct Bootstrap)

## 1. Problem Diagnosis

The root cause of the `phoenix sync all` failure is a DNS conflict during the initial trust establishment between Traefik and Step-CA. The `step ca bootstrap` command is using the DNS name `ca.internal.thinkheads.ai`, which incorrectly resolves to the Traefik IP, leading to a failed connection.

## 2. Proposed Solution: Direct IP Bootstrap

We will resolve this by modifying the `phoenix_hypervisor_lxc_102.sh` script to use the `--ca-url` flag with the direct IP address of the Step-CA container during the initial bootstrap. This will bypass the faulty DNS lookup and establish the necessary trust for all subsequent operations.

The updated workflow will be:

1.  **Direct Bootstrap:** The script will call `step ca bootstrap --ca-url https://10.0.0.10:9000 ...`. This will force the initial connection to go directly to the Step-CA container, bypassing DNS.
2.  **Standard Certificate Operations:** Once the root CA is trusted, all subsequent commands, including `step ca certificate` and the ACME challenges from Traefik, will function correctly using the standard DNS names.

This is the cleanest and most direct solution, as it uses the intended functionality of the `step-ca` CLI to solve the bootstrap problem.

## 3. Implementation Plan

1.  **Modify `phoenix_hypervisor_lxc_102.sh`:** I will use `apply_diff` to update the `bootstrap_step_cli` function to use the `--ca-url` flag with the direct IP address.
2.  **Re-run `phoenix sync all`:** After the fix is applied, you will need to re-run the `phoenix sync all` command to trigger the updated Traefik provisioning script and validate that the issue is resolved.

This plan will definitively resolve the ACME challenge and Portainer API failures.