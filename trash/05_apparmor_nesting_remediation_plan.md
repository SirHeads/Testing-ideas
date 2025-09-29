# AppArmor Nesting Remediation Plan

## 1. Executive Summary

This document outlines the remediation plan for a fatal error occurring when starting a Docker container inside an LXC container. The root cause has been identified as a missing AppArmor configuration that prevents the Docker daemon from accessing the AppArmor filesystem.

The solution is to add the `lxc.apparmor.allow_nesting=1` option to the container's configuration, which will grant the necessary permissions and resolve the error.

## 2. Problem Analysis

The error `Could not check if docker-default AppArmor profile was loaded: open /sys/kernel/security/apparmor/profiles: permission denied` indicates that the Docker daemon, running within the LXC container, is being blocked by AppArmor from accessing its own security profiles.

This occurs because the container is configured with `"apparmor_profile": "unconfined"`, but it is missing the Proxmox-specific flag that allows nested AppArmor management.

## 3. Remediation Steps

The following changes will be made to `/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json` to resolve the issue.

### 3.1. Update Container 952 Configuration

The `lxc_options` for container `952` will be updated to include the `lxc.apparmor.allow_nesting=1` flag.

**Current Configuration:**
```json
"952": {
    ...
    "lxc_options": [
        "lxc.apparmor.profile=unconfined"
    ],
    ...
}
```

**New Configuration:**
```json
"952": {
    ...
    "lxc_options": [
        "lxc.apparmor.profile=unconfined",
        "lxc.apparmor.allow_nesting=1"
    ],
    ...
}
```

## 4. Implementation

This remediation plan will be implemented by the `code` mode. The `code` mode will be responsible for applying the changes to the `phoenix_lxc_configs.json` file.

## 5. Verification

After the changes have been applied, the `phoenix_orchestrator.sh` script should be run for container `952`. The expected outcome is that the container will start successfully and the Docker container will run without any AppArmor-related errors.