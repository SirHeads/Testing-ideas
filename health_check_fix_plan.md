# Plan: Correct Nginx (CTID 101) Health Check for Bootstrap Process

## 1. Objective
To correct the health check for the Nginx container (CTID 101) so that it aligns with the system's bootstrap sequence.

## 2. Problem Analysis
The current health check for CTID 101 fails because it attempts to validate DNS resolution for `ca.internal.thinkheads.ai`. However, during the creation of CTID 101, the Traefik container (CTID 102), which handles routing for internal service names, has not yet been created.

The bootstrap process for CTID 101 is designed to communicate directly with the Step-CA container (CTID 103) via its hardcoded IP address (`10.0.0.10`). The health check must validate this direct connectivity.

## 3. Proposed Solution
Modify the health check configuration for CTID 101 in `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`. The DNS resolution check will be replaced with a direct TCP port check to the Step-CA's IP address (`10.0.0.10`) on its service port (`9000`).

This ensures the health check validates the actual connectivity requirement at this specific stage of the bootstrap process.

## 4. Implementation Steps
1.  **Switch to a mode with permissions to edit JSON files (e.g., `code` or `debug`).**
2.  **Modify the `health_checks` array for CTID `101` in `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json` to replace the existing check.**

    **Current Configuration:**
    ```json
    "health_checks": [
        {
            "name": "DNS Resolution for Step-CA",
            "script": "check_dns_resolution.sh",
            "args": "--context guest --guest-id 101 --domain ca.internal.thinkheads.ai --expected-ip 10.0.0.10"
        }
    ]
    ```

    **Proposed New Configuration:**
    ```json
    "health_checks": [
      {
        "name": "Direct Connectivity to Step-CA",
        "script": "check_service_status.sh",
        "args": "--guest-id 101 --host 10.0.0.10 --port 9000"
      }
    ]
    ```
    *(Note: This assumes the `check_service_status.sh` script can perform a host and port check. If not, a different existing script or a new simple one might be required, but this represents the correct logical check.)*
