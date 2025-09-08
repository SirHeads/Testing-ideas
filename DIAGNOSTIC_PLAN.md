# LXC Provisioning Failure Diagnostic Plan

## 1. Primary Hypothesis: Race Condition

The most likely cause of the "Unit file does not exist" error is a race condition where `systemctl daemon-reload` is executed before the `pct push` command has fully written the service file to the container's filesystem.

## 2. Diagnostic Steps

Execute these commands on the **Proxmox host** after the provisioning script has failed, leaving the LXC container (ID 958) in its failed state.

### Step 2.1: Verify File Existence and Content

These commands will confirm if the `embedding_server.service` file was successfully copied into the container and if its contents are correct.

```bash
# Check if the service file exists and view its permissions
pct exec 958 -- ls -l /etc/systemd/system/

# Display the content of the service file to check for corruption or syntax errors
pct exec 958 -- cat /etc/systemd/system/embedding_server.service
```

### Step 2.2: Check Systemd's State

This command checks if `systemd` is aware of the service file, even if it's masked, invalid, or failed to load.

```bash
# List all unit files known to systemd
pct exec 958 -- systemctl list-unit-files | grep embedding_server
```

### Step 2.3: Inspect Systemd Logs

This command inspects the `systemd` journal for any errors related to loading or parsing unit files during the `daemon-reload` process.

```bash
# View the last 100 lines of the systemd journal
pct exec 958 -- journalctl -u systemd -n 100
```

### Step 2.4: Manually Test Systemd Commands

These commands attempt to manually reload the `systemd` daemon and enable the service, which may succeed if the file has since been fully written to the filesystem.

```bash
# Manually reload the systemd daemon
pct exec 958 -- systemctl daemon-reload

# Attempt to enable the service again
pct exec 958 -- systemctl enable embedding_server.service
```

## 3. Proposed Solution

If the manual `systemctl enable` command in Step 2.4 succeeds, it strongly indicates a race condition. The definitive solution is to introduce a small delay in the provisioning script between copying the file and reloading the daemon.

**Proposed Change in `usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_lxc_958.sh`:**

```diff
...
38 | pct push 958 /usr/local/phoenix_hypervisor/src/rag-api-service/systemd/ /etc/systemd/system/
39 | 
40 | # Create requirements.txt
...
61 | log_info "Reloading systemd..."
62 | pct exec $LXC_ID -- systemctl daemon-reload
...
```

**Should be changed to:**

```diff
...
38 | pct push 958 /usr/local/phoenix_hypervisor/src/rag-api-service/systemd/ /etc/systemd/system/
   | + sleep 2 # Add a 2-second delay to ensure the filesystem syncs
39 | 
40 | # Create requirements.txt
...
61 | log_info "Reloading systemd..."
62 | pct exec $LXC_ID -- systemctl daemon-reload
...
```

This change will be implemented by the **Code** mode after you approve this plan.