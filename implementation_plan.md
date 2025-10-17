# VM Manager Firewall Enhancement Plan

## 1. Objective

To enhance the `vm-manager.sh` script to support the declarative configuration of guest-specific firewall rules from the `phoenix_vm_configs.json` file.

## 2. Proposed Changes

### a. Create `apply_firewall_rules` Function

A new function, `apply_firewall_rules`, will be created. This function will:
1.  Accept a `VMID` as an argument.
2.  Read the `firewall` block from the corresponding VM's definition in `phoenix_vm_configs.json`.
3.  Iterate through the `rules` array.
4.  For each rule, construct and execute a `pvesh` command to create the firewall rule for the specified VM.

### b. Integrate into `orchestrate_vm`

The `apply_firewall_rules` function will be called from within the `orchestrate_vm` function, after the core and network configurations have been applied.

### c. Example Configuration

The `phoenix_vm_configs.json` file will be updated to include a `firewall` block in the Portainer VM's definition, like so:

```json
"firewall": {
    "enabled": true,
    "rules": [
        {
            "type": "in",
            "action": "ACCEPT",
            "source": "10.0.0.0/24",
            "proto": "tcp",
            "port": "9443",
            "comment": "Allow Traefik to access Portainer"
        }
    ]
}
```

## 3. Implementation Steps

1.  **Add the `apply_firewall_rules` function to `vm-manager.sh`.**
2.  **Call `apply_firewall_rules` from `orchestrate_vm`.**
3.  **Update `phoenix_vm_configs.json` with the new firewall configuration for the Portainer VM.**
4.  **Run `phoenix setup` to apply the changes.**
5.  **Run `phoenix sync all` to confirm the fix.**