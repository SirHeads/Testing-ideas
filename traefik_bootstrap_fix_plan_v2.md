# Plan: Correct Traefik (CTID 102) Bootstrap Process - v2

## 1. Objective
To implement a robust and intelligent bootstrap process for the Traefik container (CTID 102) that uses a direct IP connection for initial setup and the service mesh for ongoing operations.

## 2. Problem Analysis
The `phoenix_hypervisor_feature_install_traefik.sh` script fails during the `step ca bootstrap` command because it attempts to use the service name `ca.internal.thinkheads.ai`, which resolves to the Traefik container itself, creating a circular dependency.

A durable solution must use the Step-CA's direct IP address (`10.0.0.10`) for the initial bootstrap but ensure that the final, persistent Traefik configuration uses the service name to leverage the service mesh.

## 3. Proposed Solution
The solution is to introduce a new, optional `bootstrap_ca_url` property to the `lxc_configs` in `phoenix_lxc_configs.json`. When this property is present, the `lxc-manager.sh` script will pass its value as an argument to the feature installation scripts.

The `phoenix_hypervisor_feature_install_traefik.sh` script will then be modified to:
1.  Accept the bootstrap CA URL as an optional argument.
2.  Use this URL for the `step ca bootstrap` command.
3.  Continue to use the standard service name (`ca.internal.thinkheads.ai`) in the final `traefik.yml` configuration file, preserving the service mesh architecture for ongoing operations.

## 4. Implementation Steps

### Step 1: Add `bootstrap_ca_url` to `phoenix_lxc_configs.json`
1.  **Switch to a mode with permissions to edit JSON files (e.g., `code`).**
2.  **Add the `bootstrap_ca_url` property to the configuration for CTID `102`.**

    **Proposed Addition:**
    ```json
    "bootstrap_ca_url": "https://10.0.0.10:9000",
    ```

### Step 2: Modify `lxc-manager.sh` to Pass the Bootstrap URL
1.  **Switch to a mode with permissions to edit shell scripts (e.g., `code`).**
2.  **In the `apply_features` function, read the `bootstrap_ca_url` and pass it as an argument to the feature script.**

    **Proposed Change:**
    ```bash
    # In apply_features function, inside the for loop
    local bootstrap_ca_url=$(jq_get_value "$CTID" ".bootstrap_ca_url" || echo "")
    if ! (set +e; "$feature_script_path" "$CTID" "$bootstrap_ca_url"); then
        # ... error handling
    fi
    ```

### Step 3: Modify `phoenix_hypervisor_feature_install_traefik.sh`
1.  **Switch to a mode with permissions to edit shell scripts (e.g., `code`).**
2.  **Update the script to accept the bootstrap URL as an argument and use it for the bootstrap command.**

    **Proposed Changes:**
    ```bash
    # At the top of the script
    CTID="$1"
    BOOTSTRAP_CA_URL="$2"
    FINAL_CA_URL="https://ca.internal.thinkheads.ai:9000"

    # In the bootstrap_step_cli function
    local ca_url_to_use="${BOOTSTRAP_CA_URL:-$FINAL_CA_URL}"
    step ca bootstrap --ca-url "$ca_url_to_use" ...

    # In the configure_traefik function
    sed -i "s|__CA_URL__|${FINAL_CA_URL}|g" "/etc/traefik/traefik.yml"
    ```

This approach provides a flexible and robust solution that correctly handles the bootstrap dependency without compromising the final system architecture.