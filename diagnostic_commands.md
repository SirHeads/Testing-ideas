# Diagnostic Commands

This document provides the necessary commands to check the status and logs of the core proxy services.

## Traefik (LXC 102)

### Check Status
```bash
pct exec 102 -- systemctl status traefik
```

### View Logs
```bash
pct exec 102 -- journalctl -u traefik -n 40
```
*(Use `-f` to follow the logs in real-time)*

## Nginx (LXC 101)

### Check Status
```bash
pct exec 101 -- systemctl status nginx
```

### View Logs
```bash
pct exec 101 -- journalctl -u nginx -n 40
```
*(Use `-f` to follow the logs in real-time)*