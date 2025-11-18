#!/bin/bash

# --- Color Codes for Output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}--- Traefik Status (LXC 102) ---${NC}"
pct exec 102 -- systemctl status traefik --no-pager
echo

echo -e "${YELLOW}--- Traefik Logs (Last 20 lines) ---${NC}"
pct exec 102 -- journalctl -u traefik -n 20 --no-pager
echo

echo -e "${GREEN}--- Nginx Status (LXC 101) ---${NC}"
pct exec 101 -- systemctl status nginx --no-pager
echo

echo -e "${YELLOW}--- Nginx Logs (Last 20 lines) ---${NC}"
pct exec 101 -- journalctl -u nginx -n 20 --no-pager
echo

echo -e "${GREEN}--- Docker Swarm Service Status (VM 1001) ---${NC}"
qm guest exec 1001 -- docker service ls
echo

echo -e "${YELLOW}--- Docker Swarm Service Logs (portainer_service_portainer, Last 20 lines) ---${NC}"
qm guest exec 1001 -- docker service logs prod_portainer_service_portainer --tail 20
echo

echo -e "${YELLOW}--- Docker Swarm Service Logs (qdrant_service, Last 20 lines) ---${NC}"
qm guest exec 1001 -- docker service logs prod_qdrant_service_qdrant --tail 20
echo