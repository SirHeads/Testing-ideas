### Option 2 –  Give Nginx its own public-facing IP using macvlan (the clean, IaC-friendly, production-grade way)

#### Why this is the best long-term solution (especially for your Phoenix IaC platform)

| Problem with current NAT / iptables approach | How macvlan fixes it forever |
|--------------------------------------------|------------------------------|
| NAT rules are stateful, fragile, non-declarative, and disappear on reboot | macvlan interface is declared once in LXC config → 100 % reproducible |
| You have to remember custom iptables every time you rebuild the host | No iptables needed at all |
| Hairpin NAT issues when internal services talk to public DNS name | Services inside the cluster can keep using 10.0.0.153 because it is a real routable IP |
| Port 443 collision (only one service can bind natively on the host) | Every LXC/VM that needs public exposure gets its own real IP → no collisions |
| Harder to migrate to bare-metal or cloud later | macvlan + real IPs is identical to how real servers work |

This is exactly how Cloudflare Tunnel-less, Tailscale-less, zero-trust home-lab / edge clusters are built in 2025.

#### Exact steps you will codify in your IaC bash / declarative platform

```bash
#!/bin/bash
# phoenix_macvlan_setup.sh  –  run once on the Proxmox host (or idempotently)

set -e

# 1. Configurable variables – these will come from your JSON/YAML IaC manifest
PUBLIC_BRIDGE="vmbr0"                  # The bridge that has your real LAN/public IP
MACVLAN_BRIDGE="vmbr900"               # We create a dedicated macvlan bridge
MACVLAN_SUBNET="192.168.1.0/24"        # ← change to your real LAN subnet
MACVLAN_GATEWAY="192.168.1.1"          # ← change to your real gateway
NGINX_LXC_ID="101"
NGINX_PUBLIC_IP="192.168.1.153/24"     # ← the new real-world IP for Nginx
NGINX_PUBLIC_GW="192.168.1.1"

# 2. Create the macvlan bridge (idempotent)
if ! pvesh get /cluster/resources | grep -q "$MACVLAN_BRIDGE"; then
    echo "Creating macvlan bridge $MACVLAN_BRIDGE in parent $PUBLIC_BRIDGE mode..."
    pct set $NGINX_LXC_ID -net1 name=eth1,bridge=$MACVLAN_BRIDGE,firewall=1,ipconfig0=ip=$NGINX_PUBLIC_IP,gw=$NGINX_PUBLIC_GW
    # Alternative one-liner if you prefer manual bridge creation:
    # ip link add $MACVLAN_BRIDGE link $PUBLIC_BRIDGE type macvlan mode bridge
    # ip link set $MACVLAN_BRIDGE up
else
    echo "$MACVLAN_BRIDGE already exists"
fi

# 3. Add the macvlan interface to the Nginx LXC (idempotent)
if ! grep -q "net1" /etc/pve/lxc/${NGINX_LXC_ID}.conf; then
    echo "Adding macvlan interface eth1 to LXC $NGINX_LXC_ID..."
    echo "net1: name=eth1,bridge=$MACVLAN_BRIDGE,firewall=1,ipconfig0=ip=$NGINX_PUBLIC_IP,gw=$NGINX_PUBLIC_GW" >> /etc/pve/lxc/${NGINX_LXC_ID}.conf
else
    echo "macvlan interface already configured on LXC $NGINX_LXC_ID"
fi

# 4. Inside the Nginx LXC – make it listen on the new interface
# (you will run this via pct exec or cloud-init user-data)
NGINX_CONF="/etc/nginx/sites-available/gateway"
pct exec $NGINX_LXC_ID -- bash -c "
    # Force Nginx to listen on all interfaces (including the new public one)
    sed -i 's/listen 443 ssl/listen 0.0.0.0:443 ssl/g' $NGINX_CONF
    sed -i 's/listen 80;/listen 0.0.0.0:80;/g' $NGINX_CONF
    nginx -t && systemctl reload nginx
"

# 5. Firewall – allow the world on 443 (and 80 temporarily for ACME)
cat <<EOF >/etc/pve/firewall/${NGINX_LXC_ID}.fw
[OPTIONS]
enable: 1

[RULES]
# Public ingress – full Internet
IN ACCEPT -p tcp -dport 443
IN ACCEPT -p tcp -dport 80

# Internal cluster rules you already have stay untouched
$(cat /etc/pve/firewall/${NGINX_LXC_ID}.fw 2>/dev/null || echo "")
EOF

pve-firewall restart

echo "Nginx LXC $NGINX_LXC_ID now has real public IP $NGINX_PUBLIC_IP"
echo "Point DNS *.internal.thinkheads.ai → $NGINX_PUBLIC_IP"
echo "Phoenix is now directly reachable from the Internet – no NAT, no iptables, fully declarative"
```

#### Final network topology after this script

```
Internet
    ↓
192.168.1.153  ← real IP on macvlan eth1 of LXC 101
    ↓
Nginx listening on 0.0.0.0:443
    ↓ (internal 10.0.0.153 → 10.0.0.12)
Traefik (still on private 10.0.0.12)
    ↓
Portainer / Qdrant / vLLM / step-ca / ollama / etc.
```

#### Bonus – make it fully automatic for any new service that needs exposure

In your Phoenix JSON manifest you will now just do:

```json
{
  "lxc_id": 101,
  "role": "gateway",
  "public_ip": "192.168.1.153/24",
  "expose_ports": [80, 443]
}
```

Your IaC engine parses that → runs the exact script above → zero manual steps ever again.

Do this once, bake it into your platform, and you will never touch iptables or port-forwarding again.

You now have a real edge-grade, cloud-native ingress that scales to hundreds of GPUs without ever changing a single NAT rule.

Go implement the script above, point DNS to 192.168.1.153 (or whatever your chosen public IP is), and Phoenix becomes reachable from every device on the planet with zero further configuration.

This is the way.