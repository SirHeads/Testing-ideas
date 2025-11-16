# --- Color Codes for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=======================================================================${NC}"
echo -e "${BLUE} NGINX Gateway Diagnostics (LXC 101)${NC}"
echo -e "${BLUE}=======================================================================${NC}"

echo -e "\n${YELLOW}--- Nginx Service Status ---${NC}"
if pct exec 101 -- systemctl is-active --quiet nginx; then
    echo -e "${GREEN}Nginx service is active.${NC}"
else
    echo -e "${RED}Nginx service is INACTIVE.${NC}"
fi

echo -e "\n${YELLOW}--- Nginx Main Config (/etc/nginx/nginx.conf) ---${NC}"
pct exec 101 -- cat /etc/nginx/nginx.conf

echo -e "\n${YELLOW}--- Nginx Site Config (/etc/nginx/sites-enabled/gateway) ---${NC}"
pct exec 101 -- cat /etc/nginx/sites-enabled/gateway

echo -e "\n${YELLOW}--- Nginx Access Log (last 50 lines) ---${NC}"
pct exec 101 -- tail -n 50 /var/log/nginx/access.log

echo -e "\n${YELLOW}--- Nginx Error Log (last 50 lines) ---${NC}"
pct exec 101 -- tail -n 50 /var/log/nginx/error.log

echo -e "\n\n${BLUE}=======================================================================${NC}"
echo -e "${BLUE} TRAEFIK Service Mesh Diagnostics (LXC 102)${NC}"
echo -e "${BLUE}=======================================================================${NC}"

echo -e "\n${YELLOW}--- Traefik Service Status ---${NC}"
if pct exec 102 -- systemctl is-active --quiet traefik; then
    echo -e "${GREEN}Traefik service is active.${NC}"
else
    echo -e "${RED}Traefik service is INACTIVE.${NC}"
fi

echo -e "\n${YELLOW}--- Traefik Static Config (/etc/traefik/traefik.yml) ---${NC}"
pct exec 102 -- cat /etc/traefik/traefik.yml

echo -e "\n${YELLOW}--- Traefik Dynamic Config (/etc/traefik/dynamic/dynamic_conf.yml) ---${NC}"
pct exec 102 -- cat /etc/traefik/dynamic/dynamic_conf.yml

echo -e "\n${YELLOW}--- Traefik Logs (last 50 lines) ---${NC}"
pct exec 102 -- journalctl -u traefik -n 50 --no-pager
