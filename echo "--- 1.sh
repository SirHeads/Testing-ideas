echo "--- 1. Traefik Container Logs ---"
pct exec 102 -- tail -n 50 /var/log/traefik/traefik.log

echo "\n--- 2. Traefik Dynamic Configuration ---"
pct exec 102 -- cat /etc/traefik/dynamic/dynamic_conf.yml


cat /usr/local/phoenix_hypervisor/etc/nginx/sites-available/gateway


echo "--- Test 1: Hypervisor to Nginx Gateway (101) ---"
curl -v --cacert /mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt https://portainer.internal.thinkheads.ai/api/system/status

echo "\n--- Test 2: Nginx Gateway (101) to Traefik (102) ---"
pct exec 101 -- curl -v http://10.0.0.12:80 -H "Host: portainer.internal.thinkheads.ai"

echo "\n--- Test 3: Traefik (102) to Portainer (1001) ---"
pct exec 102 -- curl -v --cacert /etc/step-ca/ssl/phoenix_root_ca.crt https://10.0.0.111:9443
