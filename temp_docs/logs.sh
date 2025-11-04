logs

pct exec 102 -- curl https://ca.internal.thinkheads.ai:9000
 &&
 pct exec 101 -- tail -n 50 /var/log/nginx/error.log
 &&
 pct exec 101 -- tail -n 50 /var/log/nginx/access.log
 &&
 cat /usr/local/phoenix_hypervisor/etc/nginx/sites-available/gateway
 systemctl status dnsmasq --no-pager && journalctl -u dnsmasq -n 50 --no-pager
 && 
 pct exec 102 -- cat /etc/traefik/dynamic/dynamic_conf.yml
 && 
 pct exec 102 -- curl -v https://10.0.0.10:9000 --insecure
 &&
 pct exec 102 -- curl -v --insecure https://10.0.0.111:9443
 &&
 pct exec 101 -- curl -v http://10.0.0.12:80 -H "Host: portainer.internal.thinkheads.ai"
 &&
 pct exec 102 -- dig ca.internal.thinkheads.ai
 &&
 pct exec 102 -- journalctl -u traefik --no-pager
 &&
 pct exec 103 -- journalctl -u step-ca -n 50 --no-pager
 &&
 pct exec 103 -- ping -c 3 10.0.0.13
 &&
 pct exec 103 -- cat /etc/resolv.conf
 &&
 pct exec 103 -- dig google.com
 && 
 cat /etc/resolv.conf
 &&
 pct exec 103 -- curl -v http://portainer.internal.thinkheads.ai/.well-known/acme-challenge/test
 &&
 qm guest exec 1002 -- docker logs portainer_agent && qm guest exec 1001 -- docker logs portainer_server && qm guest exec 1002 -- docker ps -a && qm guest exec 1001 -- docker ps -a
 &&
 cat /etc/pve/firewall/1001.fw && cat /etc/pve/firewall/1002.fw && cat /etc/pve/firewall/101.fw && cat /etc/pve/firewall/102.fw && cat /etc/pve/firewall/103.fw && cat /etc/pve/firewall/900.fw && cat /etc/pve/firewall/cluster.fw
 &&
 cat /etc/pve/firewall/101.fw && cat /etc/pve/firewall/102.fw && cat /etc/pve/firewall/1001.fw && cat /etc/pve/firewall/cluster.fw
 &&
 pct exec 101 -- tail -n 50 /var/log/nginx/error.log
 &&
 pct exec 103 -- curl -v http://traefik.internal.thinkheads.ai/.well-known/acme-challenge/test

phoenix delete 1002 1001 9000 102 101 103 900 && phoenix setup && phoenix create 900 103 101 102 9000 1001 1002 && phoenix sync all

 # Check 1: Verify Portainer container status and logs on VM 1001
qm guest exec 1001 -- docker ps -a
qm guest exec 1001 -- docker logs portainer_server

# Check 2: Verify the existence and content of the Portainer certificates on the hypervisor
ls -l /quickOS/vm-persistent-data/1001/portainer/certs/
cat /quickOS/vm-persistent-data/1001/portainer/certs/portainer.crt

# Check 3: Verify network connectivity from the hypervisor to the Step-CA (LXC 103)
curl -v --cacert /mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt https://10.0.0.10:9000

# Check 4: Verify network connectivity from Nginx (101) to Traefik (102)
pct exec 101 -- curl -v http://10.0.0.12:80 -H "Host: portainer.internal.thinkheads.ai"

# Check 5: Verify network connectivity from Traefik (102) to Portainer (1001)
pct exec 102 -- curl -v --cacert /etc/step-ca/ssl/phoenix_root_ca.crt https://10.0.0.111:9443






iptables -v -n -L PVEFW-HOST-OUT




#!/bin/bash
set -x

echo "--- 1. Portainer Service Health (on VM 1001) ---"
qm guest exec 1001 -- docker ps -a
qm guest exec 1001 -- docker logs portainer_server
qm guest exec 1001 -- curl -v --insecure https://localhost:9443/api/system/status

echo "--- 2. Traefik -> Portainer Connectivity (from LXC 102) ---"
pct exec 102 -- curl -v --cacert /etc/step-ca/ssl/phoenix_root_ca.crt https://10.0.0.111:9443/api/system/status

echo "--- 3. Nginx -> Traefik Connectivity (from LXC 101) ---"
pct exec 101 -- curl -v http://10.0.0.12:80 -H "Host: portainer.internal.thinkheads.ai"

echo "--- 4. Host -> Nginx Connectivity (from Proxmox Host) ---"
dig portainer.internal.thinkheads.ai @127.0.0.1
curl -v --cacert /mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt https://portainer.internal.thinkheads.ai/api/system/status

echo "--- 5. Certificate & Config Inspection ---"
echo "--- Nginx Config ---"
cat /usr/local/phoenix_hypervisor/etc/nginx/sites-available/gateway
echo "--- Traefik Config ---"
pct exec 102 -- cat /etc/traefik/dynamic/dynamic_conf.yml
echo "--- Portainer Certificate Details ---"
openssl x509 -in /mnt/pve/quickOS/vm-persistent-data/1001/portainer/certs/portainer.crt -text -noout
echo "--- Nginx Certificate Details ---"
openssl x509 -in /mnt/pve/quickOS/lxc-persistent-data/101/ssl/nginx.internal.thinkheads.ai.crt -text -noout

echo "--- 6. Firewall Rule Inspection ---"
echo "--- Cluster Firewall ---"
cat /etc/pve/firewall/cluster.fw
echo "--- Nginx (101) Firewall ---"
cat /etc/pve/firewall/101.fw
echo "--- Traefik (102) Firewall ---"
cat /etc/pve/firewall/102.fw
echo "--- Portainer (1001) Firewall ---"
cat /etc/pve/firewall/1001.fw

set +x




#!/bin/bash
set -x

echo "--- 1. DNS Service Status ---"
systemctl status dnsmasq --no-pager
journalctl -u dnsmasq -n 50 --no-pager

echo "--- 2. Host DNS Configuration ---"
cat /etc/resolv.conf

echo "--- 3. Dnsmasq Configuration Inspection ---"
cat /etc/dnsmasq.conf
echo "--- Dnsmasq Generated Records ---"
cat /etc/dnsmasq.d/00-phoenix-internal.conf

echo "--- 4. Network Listener Check ---"
# Check what is listening on port 53
ss -tuln | grep ':53'

echo "--- 5. Direct DNS Query Test (using host's configured DNS) ---"
dig portainer.internal.thinkheads.ai

echo "--- 1. Nginx Service Status (inside LXC 101) ---"
pct exec 101 -- systemctl status nginx --no-pager
pct exec 101 -- journalctl -u nginx -n 50 --no-pager

echo "--- 2. Nginx Network Listener Check (inside LXC 101) ---"
# Check what is listening on ports 80 and 443 inside the container
pct exec 101 -- ss -tuln | grep -E ':80|:443'

echo "--- 3. Nginx Configuration Test (inside LXC 101) ---"
pct exec 101 -- nginx -t

echo "--- 1. Nginx Certificate Verification ---"
echo "--- Host-side ---"
ls -l /mnt/pve/quickOS/lxc-persistent-data/101/ssl/
openssl x509 -in /mnt/pve/quickOS/lxc-persistent-data/101/ssl/nginx.internal.thinkheads.ai.crt -text -noout
echo "--- Container-side ---"
pct exec 101 -- ls -l /etc/nginx/ssl/
pct exec 101 -- openssl x509 -in /etc/nginx/ssl/nginx.internal.thinkheads.ai.crt -text -noout

echo "--- 2. Portainer Certificate Verification ---"
echo "--- Host-side ---"
ls -l /mnt/pve/quickOS/vm-persistent-data/1001/portainer/certs/
openssl x509 -in /mnt/pve/quickOS/vm-persistent-data/1001/portainer/certs/portainer.crt -text -noout
echo "--- Container-side ---"
qm guest exec 1001 -- ls -l /persistent-storage/portainer/certs/
qm guest exec 1001 -- openssl x509 -in /persistent-storage/portainer/certs/portainer.crt -text -noout

echo "--- 3. Traefik Certificate Verification ---"
echo "--- Host-side ---"
ls -l /mnt/pve/quickOS/lxc-persistent-data/102/certs/
openssl x509 -in /mnt/pve/quickOS/lxc-persistent-data/102/certs/traefik.internal.thinkheads.ai.crt -text -noout
echo "--- Container-side ---"
pct exec 102 -- ls -l /etc/traefik/certs/
pct exec 102 -- openssl x509 -in /etc/traefik/certs/traefik.internal.thinkheads.ai.crt -text -noout

echo "--- Test 1: Host to Nginx (LXC 101) on Port 443 ---"
# This tests DNS, host firewall, and Nginx's SSL listener.
curl -v --cacert /mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt https://portainer.internal.thinkheads.ai/api/system/status

echo "--- Test 2: Nginx (LXC 101) to Traefik (LXC 102) on Port 80 ---"
# This tests the proxy_pass directive in Nginx and the Traefik entrypoint.
pct exec 101 -- curl -v http://10.0.0.12:80 -H "Host: portainer.internal.thinkheads.ai"

echo "--- Test 3: Traefik (LXC 102) to Portainer (VM 1001) on Port 9443 ---"
# This tests the Traefik service definition and routing to the final destination.
pct exec 102 -- curl -v --cacert /etc/step-ca/ssl/phoenix_root_ca.crt https://10.0.0.111:9443/api/system/status

echo "--- Test 4: Direct to Portainer (inside VM 1001) ---"
# This confirms the Portainer service itself is responding correctly on its HTTPS port.
qm guest exec 1001 -- curl -v --insecure https://localhost:9443/api/system/status

set +x


#!/bin/bash
set -x

root@phoenix:~# # 1. Check permissions on the hypervisor's NFS share
ls -ld /mnt/pve/quickOS/lxc-persistent-data/101/ssl/
ls -l /mnt/pve/quickOS/lxc-persistent-data/101/ssl/

# 2. Check permissions from within the Nginx container
pct exec 101 -- ls -ld /etc/nginx/ssl/
pct exec 101 -- ls -l /etc/nginx/ssl/

# 3. Display the Nginx configuration file that controls ports
pct exec 101 -- cat /etc/nginx/sites-available/gateway

set +x