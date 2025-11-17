# Phoenix System Diagnostic Commands

Please execute the following commands on your Proxmox host and provide the output.

## 1. Service Status & Logs
### Docker on VM 1001 (Swarm Manager)
echo "--- Docker Service Status on VM 1001 ---"
qm guest exec 1001 -- systemctl status docker --no-pager
echo "--- Last 20 Docker Log Entries on VM 1001 ---"
qm guest exec 1001 -- journalctl -u docker -n 20 --no-pager
### Traefik on LXC 102
echo "--- Traefik Service Status on LXC 102 ---"
pct exec 102 -- systemctl status traefik --no-pager
echo "--- Last 20 Traefik Log Entries on LXC 102 ---"
pct exec 102 -- journalctl -u traefik -n 20 --no-pager
### Nginx on LXC 101
echo "--- Nginx Service Status on LXC 101 ---"
pct exec 101 -- systemctl status nginx --no-pager
echo "--- Last 20 Nginx Log Entries on LXC 101 ---"
pct exec 101 -- journalctl -u nginx -n 20 --no-pager
## 2. Firewall Configuration
echo "--- Proxmox Host Firewall Rules ---"
cat /etc/pve/firewall/cluster.fw
echo "--- VM 1001 Firewall Rules ---"
cat /etc/pve/firewall/1001.fw
echo "--- LXC 102 Firewall Rules ---"
cat /etc/pve/firewall/102.fw
## 3. Network Connectivity Tests
### From Proxmox Host
echo "--- Pinging Swarm Manager (VM 1001) from Host ---"
ping -c 3 10.0.0.111
echo "--- Pinging Traefik (LXC 102) from Host ---"
ping -c 3 10.0.0.12
### From Traefik Container (LXC 102)
echo "--- Pinging Swarm Manager (VM 1001) from Traefik (LXC 102) ---"
pct exec 102 -- ping -c 3 10.0.0.111
echo "--- Curling Docker API on Swarm Manager (VM 1001) from Traefik (LXC 102) ---"
pct exec 102 -- curl --cacert /etc/step-ca/ssl/phoenix_root_ca.crt --cert /etc/traefik/certs/cert.pem --key /etc/traefik/certs/key.pem https://10.0.0.111:2376/info
### DNS Resolution
echo "--- Digging portainer.internal.thinkheads.ai from Host ---"
dig portainer.internal.thinkheads.ai @10.0.0.13
echo "--- Digging traefik.internal.thinkheads.ai from Host ---"
dig traefik.internal.thinkheads.ai @10.0.0.13