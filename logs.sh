logs

pct exec 102 -- curl https://ca.internal.thinkheads.ai:9000
 && 
 pct exec 102 -- cat /etc/traefik/dynamic/dynamic_conf.yml --no-pager 
 && 
 pct exec 102 -- curl -v https://10.0.0.10:9000 --insecure
 &&
 pct exec 102 -- dig ca.internal.thinkheads.ai
 &&
 pct exec 102 -- journalctl -u traefik --no-pager
 &&
 pct exec 103 -- journalctl -u step-ca --no-pager
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
 qm guest exec 1002 -- docker logs portainer_agent
 &&
 qm guest exec 1001 -- docker logs portainer_server
 &&
 qm guest exec 1002 -- docker ps -a
 &&
 qm guest exec 1001 -- docker ps -a