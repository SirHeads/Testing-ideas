# LXC Container 920 Network Failure Diagnostic Plan

This document outlines the step-by-step process to diagnose the root cause of the network hang observed when running `add-apt-repository` inside LXC container 920.

## 1. Initial Diagnosis & Hypothesis

- **Symptom:** The command `add-apt-repository -y ppa:deadsnakes/ppa` hangs during an SSL request.
- **Context:** Recent significant changes to AppArmor, user permissions, and shared directory configurations have been made.
- **Primary Hypothesis:** An overly restrictive AppArmor profile is blocking the necessary outbound network connections for the `add-apt-repository` command.
- **Secondary Hypothesis:** A firewall rule or general network misconfiguration (DNS, routing) is preventing connectivity.

## 2. Diagnostic Steps

The following commands will be executed sequentially inside the container (unless otherwise specified) to isolate the failure point.

### Step 2.1: Test DNS Resolution
- **Objective:** Verify that the container can resolve the PPA's domain name.
- **Command:** `nslookup ppa.launchpad.net`
- **Expected Outcome:** Successful resolution to one or more IP addresses.

### Step 2.2: Test General Internet Connectivity
- **Objective:** Confirm that the container has a basic outbound connection to the internet.
- **Command:** `ping -c 4 8.8.8.8`
- **Expected Outcome:** Successful ICMP replies from the Google DNS server.

### Step 2.3: Test Specific Host and Port Connectivity
- **Objective:** Check for connectivity to the PPA host on the required HTTPS port (443). This test is crucial as it closely mimics the failing operation.
- **Command:** `curl -v https://ppa.launchpad.net`
- **Expected Outcome:** A successful TLS handshake and HTTP response. Verbose output will show the connection progress. A hang here would strongly indicate a firewall or AppArmor issue.

### Step 2.4: Inspect AppArmor Profile (on Host)
- **Objective:** Check for AppArmor denials related to the container's network activity.
- **Commands (to be run on the Proxmox host):**
  - `aa-status` (To check the status of AppArmor profiles, especially for the container).
  - `dmesg | grep "apparmor=\"DENIED\""` (To search for real-time denial messages).
  - `grep "apparmor=\"DENIED\"" /var/log/syslog` (To search historical logs for denials).

## 3. Root Cause Determination

Based on the outcomes of the diagnostic steps, the root cause will be determined.
- If DNS fails, the issue is with name resolution.
- If ping fails but DNS succeeds, there is a general routing or firewall issue.
- If `curl` hangs but the previous steps succeed, the issue is likely a firewall blocking port 443 or an AppArmor rule preventing the specific connection.
- If AppArmor logs show "DENIED" messages corresponding to the network access attempts, AppArmor is confirmed as the root cause.
