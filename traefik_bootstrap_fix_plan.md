# Plan: Correct Traefik (CTID 102) Bootstrap Process

## 1. Objective
To correct the bootstrap process for the Traefik container (CTID 102) to remove the circular dependency on the service mesh for initial certificate acquisition.

## 2. Problem Analysis
The `phoenix_hypervisor_lxc_102.sh` script currently uses the domain name `ca.internal.thinkheads.ai` to bootstrap the Step CLI and request a certificate for Traefik. This creates a circular dependency:
- Traefik (102) cannot start without a certificate.
- To get a certificate, it needs to contact the Step-CA (103) via its service name.
- The service name `ca.internal.thinkheads.ai` resolves to Traefik (102) itself, which is not yet running.

This is the same issue that was previously identified and resolved for the Nginx container (101).

## 3. Proposed Solution
The solution is to modify the `phoenix_hypervisor_lxc_102.sh` script to use the hardcoded IP address of the Step-CA (`10.0.0.10`) for the initial bootstrap and certificate request. This will break the circular dependency and allow Traefik to start.

Additionally, a health check will be added to the `phoenix_lxc_configs.json` for CTID 102 to verify connectivity to the Step-CA before the container is considered fully up.

## 4. Implementation Steps

### Step 1: Modify `phoenix_hypervisor_lxc_102.sh`
1.  **Switch to a mode with permissions to edit shell scripts (e.g., `code` or `debug`).**
2.  **Update the `CA_URL` variable to use the hardcoded IP address.**

    **Current Code:**
    ```bash
    CA_URL="https://ca.internal.thinkheads.ai:9000"
    ```

    **Proposed New Code:**
    ```bash
    CA_URL="https://10.0.0.10:9000"
    ```

### Step 2: Add Health Check to `phoenix_lxc_configs.json`
1.  **Switch to a mode with permissions to edit JSON files (e.g., `code` or `debug`).**
2.  **Add a `health_checks` block to the configuration for CTID `102`.** This will use the `check_dns_resolution.sh` script (which now supports direct IP checks) to verify connectivity to the Step-CA.

    **Proposed New Configuration Block:**
    ```json
    "health_checks": [
      {
        "name": "Direct Connectivity to Step-CA",
        "script": "check_dns_resolution.sh",
        "args": "--context guest --guest-id 102 --host 10.0.0.10 --port 9000"
      }
    ],
    ```

This two-part solution will ensure that the Traefik container can bootstrap correctly and that its ability to communicate with the Step-CA is verified before the system proceeds with the creation of dependent services.