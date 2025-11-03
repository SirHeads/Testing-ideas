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