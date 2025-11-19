# Deployment Test Plan

Here is a set of commands to verify that the system is fully functional. These commands will test DNS resolution, the Nginx gateway, the Traefik proxy, and the Portainer service.

## 1. DNS Resolution Test

Pinging `portainer.internal.thinkheads.ai` from the hypervisor:

```bash
ping -c 1 portainer.internal.thinkheads.ai
```

## 2. Nginx Gateway Test

Checking the Nginx logs for any errors:

```bash
pct exec 101 -- journalctl -u nginx -n 20 --no-pager
```

## 3. Traefik Proxy Test

Checking the Traefik logs for any errors:

```bash
pct exec 102 -- journalctl -u traefik -n 20 --no-pager
```

## 4. Portainer API Test

Making a curl request to the Portainer API through the Nginx gateway and Traefik proxy:

```bash
curl -k https://portainer.internal.thinkheads.ai/api/system/status
