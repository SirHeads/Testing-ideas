cat << 'EOF' > /tmp/phoenix_diag.sh && chmod +x /tmp/phoenix_diag.sh && /tmp/phoenix_diag.sh
#!/bin/bash
set -eu

echo "============================================================"
echo "                PHOENIX SYNC ALL DIAGNOSTICS"
echo "============================================================"
echo ""

# --- DNS Diagnostics ---
echo "--- 1. DNS Resolution & Configuration ---"
echo "[INFO] Hypervisor /etc/resolv.conf:"
cat /etc/resolv.conf
echo ""
echo "[INFO] Dnsmasq internal records configuration:"
cat /etc/dnsmasq.d/00-phoenix-internal.conf 2>/dev/null || echo "File not found."
echo ""
echo "[INFO] Dnsmasq service status:"
systemctl status dnsmasq --no-pager 2>/dev/null || echo "Service not running or found."
echo ""
echo "[INFO] Performing DNS lookup for portainer.internal.thinkheads.ai from hypervisor:"
dig portainer.internal.thinkheads.ai @127.0.0.1 || echo "Dig command failed."
echo ""

# --- Firewall Diagnostics ---
echo "--- 2. Firewall Status & Rules ---"
echo "[INFO] Proxmox Firewall Service Status:"
pve-firewall status || echo "Command failed."
echo ""
echo "[INFO] Cluster Firewall Rules (/etc/pve/firewall/cluster.fw):"
cat /etc/pve/firewall/cluster.fw 2>/dev/null || echo "File not found."
echo ""
echo "[INFO] Hypervisor Firewall Rules (/etc/pve/firewall/<node_name>.fw):"
cat /etc/pve/firewall/$(hostname).fw 2>/dev/null || echo "File not found."
echo ""
echo "[INFO] Nginx (101) Firewall Rules (/etc/pve/firewall/101.fw):"
cat /etc/pve/firewall/101.fw 2>/dev/null || echo "File not found."
echo ""
echo "[INFO] Traefik (102) Firewall Rules (/etc/pve/firewall/102.fw):"
cat /etc/pve/firewall/102.fw 2>/dev/null || echo "File not found."
echo ""
echo "[INFO] Portainer (1001) Firewall Rules (/etc/pve/firewall/1001.fw):"
cat /etc/pve/firewall/1001.fw 2>/dev/null || echo "File not found."
echo ""

# --- Service Configuration & Status ---
echo "--- 3. Service Configuration & Status ---"
echo "[INFO] Nginx (101) Service Status:"
pct exec 101 -- systemctl status nginx --no-pager 2>/dev/null || echo "Failed to get status."
echo ""
echo "[INFO] Nginx (101) Gateway Config (/etc/nginx/sites-available/gateway):"
pct exec 101 -- cat /etc/nginx/sites-available/gateway 2>/dev/null || echo "File not found."
echo ""
echo "[INFO] Traefik (102) Service Status:"
pct exec 102 -- systemctl status traefik --no-pager 2>/dev/null || echo "Failed to get status."
echo ""
echo "[INFO] Traefik (102) Static Config (/etc/traefik/traefik.yml):"
pct exec 102 -- cat /etc/traefik/traefik.yml 2>/dev/null || echo "File not found."
echo ""
echo "[INFO] Portainer (1001) Docker Service Status:"
qm guest exec 1001 -- docker service ps prod_portainer_service_portainer --no-trunc 2>/dev/null || echo "Failed to get status."
echo ""

# --- Connectivity Test ---
echo "--- 4. End-to-End Connectivity Test ---"
echo "[INFO] Testing connection from Hypervisor to Portainer via Nginx gateway..."
echo "[CMD] curl -v --cacert /usr/local/share/ca-certificates/phoenix_internal_root_ca.crt https://portainer.internal.thinkheads.ai/api/status"
curl -v --cacert /usr/local/share/ca-certificates/phoenix_internal_root_ca.crt https://portainer.internal.thinkheads.ai/api/status || echo "Curl command failed."
echo ""

echo "============================================================"
echo "                      DIAGNOSTICS COMPLETE"
echo "============================================================"
EOF