# Phase 1: Foundational Network & DNS Verification Plan

This document outlines the commands to be executed to verify the foundational network connectivity and DNS resolution within the Phoenix Hypervisor environment.

## Step 1.1: Verify Basic Network Connectivity

These commands will test basic network reachability between the Portainer server (VM 1001) and the Portainer agent (VM 1002).

```bash
echo "---> Pinging VM 1002 (10.0.0.102) from VM 1001 (10.0.0.111)..."
qm guest exec 1001 -- ping -c 4 10.0.0.102

echo "---> Pinging VM 1001 (10.0.0.111) from VM 1002 (10.0.0.102)..."
qm guest exec 1002 -- ping -c 4 10.0.0.111

echo "---> Testing TCP connection on port 9001 (Portainer Agent) from VM 1001 to VM 1002..."
qm guest exec 1001 -- nc -zv 10.0.0.102 9001
```

## Step 1.2: Verify DNS Resolution

These commands will test DNS resolution for critical internal hostnames from the perspective of the Proxmox host itself, the Portainer server (VM 1001), and the Portainer agent (VM 1002).

```bash
CRITICAL_HOSTNAMES="portainer.internal.thinkheads.ai portainer-agent.internal.thinkheads.ai ca.internal.thinkheads.ai"

echo "---> Verifying DNS from Proxmox Host..."
for HOSTNAME in $CRITICAL_HOSTNAMES; do
  echo "---> Resolving $HOSTNAME from Host"
  dig +short $HOSTNAME
done

echo "---> Verifying DNS from VM 1001 (Portainer Server)..."
for HOSTNAME in $CRITICAL_HOSTNAMES; do
  echo "---> Resolving $HOSTNAME from VM 1001"
  qm guest exec 1001 -- dig +short $HOSTNAME
done

echo "---> Verifying DNS from VM 1002 (Portainer Agent)..."
for HOSTNAME in $CRITICAL_HOSTNAMES; do
  echo "---> Resolving $HOSTNAME from VM 1002"
  qm guest exec 1002 -- dig +short $HOSTNAME
done