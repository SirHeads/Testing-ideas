# IPv6 APT Remediation Plan

## 1. Problem Analysis

The `phoenix setup` command is failing during the `apt-get update` process, which is a prerequisite for installing `dnsmasq`. The logs indicate a "Network is unreachable" error when trying to connect to the Proxmox repositories via IPv6. This initial failure prevents the DNS server from being installed, which in turn breaks all subsequent DNS-dependent operations, including the `phoenix sync all` command.

## 2. Proposed Solution

The most direct and least intrusive solution is to configure `apt` to prefer IPv4 for its connections. This will not disable IPv6 system-wide but will ensure that package management operations can proceed without being blocked by IPv6 connectivity issues.

This will be accomplished by adding a single line to the `hypervisor_initial_setup.sh` script, which creates a configuration file for `apt`.

### Implementation Diff

The following diff should be applied to `usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_initial_setup.sh`:

```diff
<<<<<<< SEARCH
:start_line:10
-------
    log_info "Starting hypervisor initial setup..."
    
    # --- Update package lists and install base packages ---
    log_info "Updating package lists and installing base packages..."
    apt-get update -y
=======
    log_info "Starting hypervisor initial setup..."
    
    # --- Force APT to use IPv4 ---
    echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
    
    # --- Update package lists and install base packages ---
    log_info "Updating package lists and installing base packages..."
    apt-get update -y
>>>>>>> REPLACE
```

## 3. Next Steps

1.  Approve this final plan.
2.  Switch to a mode with code-editing capabilities.
3.  Apply the specified change to the `hypervisor_initial_setup.sh` script.
4.  Re-run the `phoenix setup` command. This will now successfully install `dnsmasq` and correctly configure the host's DNS.
5.  Re-run the `phoenix sync all` command to validate that the entire end-to-end process is now working as expected.