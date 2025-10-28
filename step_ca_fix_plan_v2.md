# Step-CA Final Fix Plan

## 1. Diagnosis

The root cause of the Step-CA service failure has been identified. The `lxc-manager.sh` is not executing the main application script (`phoenix_hypervisor_lxc_103.sh`) for the Step-CA container (CTID 103). This is because the `"application_script"` key is missing from the container's configuration in `phoenix_lxc_configs.json`.

Without this script, the CA is never initialized, and the `systemd` service fails when it tries to start, leading to a restart loop and the health check failure.

## 2. The Fix

The solution is to add the missing `"application_script"` line to the configuration for CTID 103.

**File to Modify:** `usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json`

**Change:**
```json
            "features": [
                "base_setup",
                "step_ca"
            ],
            "application_script": "phoenix_hypervisor_lxc_103.sh",
```

## 3. Validation

After applying this change, the `phoenix create 103` command should be re-run. The `lxc-manager` will now correctly execute the application script, the CA will be initialized, the `systemd` service will start successfully, and the health check will pass.