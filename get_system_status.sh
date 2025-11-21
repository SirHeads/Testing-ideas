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

echo -e "${GREEN}--- Nginx Error log (LXC 101) ---${NC}"
pct exec 101 -- tail -n 50 /var/log/nginx/error.log
echo

echo -e "${GREEN}--- Docker Swarm Service Status (VM 1001) ---${NC}"
qm guest exec 1001 -- docker service ls
echo

echo -e "${YELLOW}--- Traefik Logs Last 100 lines) ---${NC}"
pct exec 102 -- journalctl -u traefik -n 100 --no-pager
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

echo -e "${YELLOW}--- Traefik yml Config ---${NC}"
pct exec 102 -- cat /etc/traefik/traefik.yml
echo

echo -e "${YELLOW}--- Traefik Dynamic Config ---${NC}"
pct exec 102 -- cat /etc/traefik/dynamic/dynamic_conf.yml
echo

echo -e "${YELLOW}--- docker swarm service status ---${NC}"
qm guest exec 1001 -- docker node ls
echo

echo -e "${YELLOW}--- portainer service logs ---${NC}"
qm guest exec 1001 -- docker service logs production_portainer_service_portainer --tail 100;
echo

echo -e "${YELLOW}--- qdrant service logs ---${NC}"
qm guest exec 1001 -- docker service logs production_qdrant_service_qdrant --tail 100;
echo

echo -e "${CYAN}--- Verifying Docker Daemon Status on Swarm Manager (VM 1001) ---${NC}"
qm guest exec 1001 -- systemctl is-active docker
echo

echo -e "${CYAN}--- Verifying Docker Daemon Status on Swarm Worker (VM 1002) ---${NC}"
qm guest exec 1002 -- systemctl is-active docker
echo

echo -e "${GREEN}--- Detailed Docker Swarm Node List (from VM 1001) ---${NC}"
qm guest exec 1001 -- docker node ls
echo

echo -e "${GREEN}--- Docker Swarm Service List (from VM 1001) ---${NC}"
qm guest exec 1001 -- docker service ls
echo

echo -e "${YELLOW}--- Inspecting 'production_portainer_service_portainer' (from VM 1001) ---${NC}"
qm guest exec 1001 -- docker service ps production_portainer_service_portainer
echo

echo -e "${YELLOW}--- Inspecting 'production_qdrant_service_qdrant' (from VM 1001) ---${NC}"
qm guest exec 1001 -- docker service ps production_qdrant_service_qdrant
echo

echo -e "${GREEN}--- Inspecting 'traefik-public' Overlay Network (from VM 1001) ---${NC}"
qm guest exec 1001 -- docker network inspect traefik-public
echo

echo -e "${CYAN}--- Listing Docker Swarm Secrets (from VM 1001) ---${NC}"
qm guest exec 1001 -- docker secret ls
echo

echo -e "${YELLOW}--- Portainer Service Logs (Last 100 lines from VM 1001) ---${NC}"
qm guest exec 1001 -- docker service logs production_portainer_service_portainer --tail 100
echo

echo -e "${YELLOW}--- Docker Daemon Logs on Swarm Manager (Last 50 lines from VM 1001) ---${NC}"
qm guest exec 1001 -- journalctl -u docker -n 50 --no-pager
echo

echo -e "${YELLOW}--- Docker Daemon Logs on Swarm Worker (Last 50 lines from VM 1002) ---${NC}"
qm guest exec 1002 -- journalctl -u docker -n 50 --no-pager
echo