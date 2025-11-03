#!/bin/bash
#
# Verification Script for Phoenix Hypervisor Network Remediation

echo "--- 1. Verifying Firewall Rules ---"
echo "--- 1a. Hypervisor (Global) Firewall ---"
cat /etc/pve/firewall/cluster.fw

echo "--- 1b. Nginx (101) Firewall ---"
cat /etc/pve/firewall/101.fw

echo "--- 1c. Portainer Server (1001) Firewall ---"
cat /etc/pve/firewall/1001.fw

echo "--- 1d. Traefik (1001) Firewall ---"
cat /etc/pve/firewall/102.fw

echo "--- 2. Verifying DNS Resolution ---"
echo "--- 2a. Querying for 'portainer.internal.thinkheads.ai' from hypervisor ---"
dig @10.0.0.13 portainer.internal.thinkheads.ai +short

echo "--- 2b. Querying for 'portainer.internal.thinkheads.ai' from inside Traefik container (102) ---"
pct exec 102 -- dig portainer.internal.thinkheads.ai +short

echo "--- 3. Verifying Certificates ---"
echo "--- 3a. Checking for wildcard certificate on Nginx container (101) ---"
pct exec 101 -- ls -l /etc/nginx/ssl/

echo "--- 3b. Verifying the certificate is loaded by Nginx ---"
pct exec 101 -- nginx -T | grep 'ssl_certificate /etc/nginx/ssl/wildcard'

echo "--- 4. End-to-End Connectivity Test ---"
echo "--- 4a. Testing API call from Hypervisor to Portainer via Gateway ---"
curl --cacert /mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt https://portainer.internal.thinkheads.ai/api/system/status
