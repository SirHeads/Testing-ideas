#!/bin/bash

# --- Color Codes for Output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}--- Try and curl it ---${NC}"
curl -k https://portainer.internal.thinkheads.ai/api/system/status
echo

echo -e "${GREEN}--- Traefik Status (LXC 102) ---${NC}"
pct exec 102 -- systemctl status traefik --no-pager
echo

echo -e "${GREEN}--- Nginx Status (LXC 101) ---${NC}"
pct exec 101 -- systemctl status nginx --no-pager
echo

echo -e "${GREEN}--- Docker Swarm Service Status (VM 1001) ---${NC}"
qm guest exec 1001 -- docker service ls
echo

echo -e "${YELLOW}--- Traefik Logs Last 100 lines) ---${NC}"
pct exec 102 -- journalctl -u traefik -n 100 --no-pager
echo

echo -e "${YELLOW}--- Docker Swarm Service Logs (portainer_service_portainer, Last 100 lines) ---${NC}"
qm guest exec 1001 -- docker service logs prod_portainer_service_portainer --tail 100
echo

echo -e "${YELLOW}--- Docker Swarm Service Logs (qdrant_service, Last 100 lines) ---${NC}"
qm guest exec 1001 -- docker service logs prod_qdrant_service_qdrant --tail 100
echo

echo -e "${YELLOW}--- Docker Swarm nodes ---${NC}"
qm guest exec 1001 -- docker node ls
echo

echo -e "${YELLOW}--- Swarm Overlay Network ---${NC}"
qm guest exec 1001 -- docker network ls --filter driver=overlay
echo

echo -e "${YELLOW}--- docker - traefik network ---${NC}"
qm guest exec 1001 -- docker network inspect traefik-public
echo

echo -e "${YELLOW}--- Nginx Gateway Config ---${NC}"
pct exec 101 -- cat /etc/nginx/sites-enabled/gateway
echo

echo -e "${YELLOW}--- Traefik Dynamic Config ---${NC}"
pct exec 102 -- cat /etc/traefik/dynamic/dynamic_conf.yml
echo

