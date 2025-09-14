# Diagnostic Plan: VS Code "fetch failed" with Codebase Indexer

This document outlines a step-by-step plan to diagnose and resolve the "fetch failed" error occurring in Visual Studio Code during the initial scan of the codebase indexer. The environment involves a Proxmox host managed by `phoenix_hypervisor` with LXC containers 951, 952, and 953.

## 1. Initial Triage & Network Diagnostics

This section focuses on verifying basic network connectivity from the development machine where VS Code is running.

*   **Step 1.1: Verify DNS Resolution**
    *   Open a terminal on your development machine.
    *   Attempt to resolve the Proxmox host and any other relevant hostnames.
    *   Command: `ping <proxmox_host_ip_or_hostname>`
    *   Command: `nslookup <proxmox_host_ip_or_hostname>`
    *   **Expected Outcome:** The hostname should resolve to the correct IP address, and ping should receive responses.

*   **Step 1.2: Check Outbound Connectivity**
    *   Verify that the development machine can reach external networks. This is to ensure no general network issue is blocking VS Code's requests.
    *   Command: `ping 8.8.8.8` (Google's DNS)
    *   Command: `curl -v https://github.com`
    *   **Expected Outcome:** Successful pings and a successful HTTPS connection.

*   **Step 1.3: Test Connectivity to LXC Containers**
    *   From the development machine, try to connect to the services running inside the LXC containers if they are exposed.
    *   First, get the IP addresses of the containers from the Proxmox host. You might need to SSH into the Proxmox host and run `pct list`.
    *   Command: `ping <lxc_951_ip>`
    *   Command: `ping <lxc_952_ip>`
    *   Command: `ping <lxc_953_ip>`
    *   **Expected Outcome:** Successful ping responses from all relevant containers.

## 2. LXC Container Health Check

This section involves inspecting the health and configuration of the LXC containers that the indexer might depend on. These commands should be run on the Proxmox host.

*   **Step 2.1: Check Container Status**
    *   SSH into the Proxmox host.
    *   Use the `pct` command to check the status of the containers.
    *   Command: `pct status 951`
    *   Command: `pct status 952`
    *   Command: `pct status 953`
    *   **Expected Outcome:** All containers should be in a `running` state.

*   **Step 2.2: Review Container Logs**
    *   Check the console logs for each container for any startup errors or network-related issues.
    *   Command: `pct console 951` (Press Ctrl+A, Q to exit)
    *   Command: `pct console 952`
    *   Command: `pct console 953`
    *   Also, check system logs within the container by entering it.
    *   Command: `pct enter 951` then `journalctl -u <service_name>` or check `/var/log/syslog`.
    *   **Expected Outcome:** No obvious errors in the logs.

*   **Step 2.3: Inspect Container Network Configuration**
    *   Check the network configuration of each container.
    *   Command: `pct config 951`
    *   Command: `pct config 952`
    *   Command: `pct config 953`
    *   Verify the IP address, gateway, and bridge settings.
    *   **Expected Outcome:** The network configuration should be correct and consistent with the Proxmox network setup.

## 3. VS Code & Extension Integrity Check

This section focuses on the VS Code client and its configuration.

*   **Step 3.1: Check VS Code Proxy Settings**
    *   In VS Code, go to `File > Preferences > Settings`.
    *   Search for "proxy".
    *   Ensure that `Http: Proxy` and related settings are either empty or correctly configured for your network.
    *   **Expected Outcome:** Proxy settings are correct. If you don't use a proxy, they should be blank.

*   **Step 3.2: Review Remote Development Configuration**
    *   If you are using VS Code's Remote Development extensions (e.g., Remote - SSH), check the configuration file (`~/.ssh/config`).
    *   Ensure the `Host`, `HostName`, `User`, and any `ProxyCommand` settings are correct for connecting to your development environment (which might be one of the LXCs or the Proxmox host).
    *   **Expected Outcome:** The SSH configuration is correct.

*   **Step 3.3: Disable Extensions**
    *   Temporarily disable all extensions except for the one providing the codebase indexer functionality to rule out conflicts.
    *   Go to the Extensions view (`Ctrl+Shift+X`).
    *   Use the `Disable All Installed Extensions` command, then re-enable only the necessary ones.
    *   **Expected Outcome:** If the error disappears, an extension is causing the issue. Re-enable them one by one to find the culprit.

*   **Step 3.4: Check VS Code Logs**
    *   Open the Output panel in VS Code (`View > Output`).
    *   Check the logs for "Log (Window)" and any logs related to the codebase indexer or remote development for more detailed error messages.
    *   **Expected Outcome:** The logs may contain a more specific error message about why the fetch is failing.

## 4. Proxmox Host Investigation (Optional)

Perform these checks on the Proxmox host if the above steps don't identify the problem.

*   **Step 4.1: Check Proxmox Firewall**
    *   Check if the Proxmox host firewall is enabled and if it might be blocking traffic.
    *   Command: `pve-firewall status`
    *   If enabled, review the rules: `cat /etc/pve/firewall/cluster.fw` and `cat /etc/pve/firewall/<node>.fw`.
    *   **Expected Outcome:** Firewall rules should not be blocking the required traffic between the development machine and the LXC containers.

*   **Step 4.2: Inspect Network Bridge**
    *   Review the network bridge configuration on the Proxmox host.
    *   Command: `cat /etc/network/interfaces`
    *   Ensure the bridge (`vmbr0` or similar) is correctly configured and up.
    *   **Expected Outcome:** The bridge configuration is correct and allows traffic to/from the LXC containers.

## 5. Resolution Pathways

Based on the findings from the diagnostic steps, here are some potential resolutions.

*   **Scenario A: Network Connectivity Issue**
    *   **Finding:** DNS fails, pings fail, or connections to LXCs are blocked.
    *   **Resolution:**
        1.  Correct DNS settings on the development machine.
        2.  Fix firewall rules on the Proxmox host, development machine, or network hardware.
        3.  Correct the network configuration of the LXC containers.

*   **Scenario B: LXC Container Issue**
    *   **Finding:** Container is not running, has errors in logs, or is misconfigured.
    *   **Resolution:**
        1.  Restart the container: `pct stop <vmid>` then `pct start <vmid>`.
        2.  Fix the underlying issue identified in the container logs.
        3.  Correct the container's configuration using `pct set`.

*   **Scenario C: VS Code or Extension Issue**
    *   **Finding:** "fetch failed" is caused by proxy settings, a conflicting extension, or corrupted cache.
    *   **Resolution:**
        1.  Correct or remove proxy settings in VS Code.
        2.  Identify and disable/update the conflicting extension.
        3.  Clear VS Code's caches. The location varies by OS. For example, on Linux, it's often in `~/.config/Code/Cache` and `~/.config/Code/CachedData`.

*   **Scenario D: Proxmox Host Configuration Issue**
    *   **Finding:** Proxmox firewall or network bridge is misconfigured.
    *   **Resolution:**
        1.  Adjust Proxmox firewall rules to allow necessary traffic.
        2.  Correct the `/etc/network/interfaces` file on the Proxmox host and reboot or restart networking services.
