# Phoenix Post-Sync Verification Plan

This document provides a step-by-step guide to verify the health and functionality of the Phoenix environment after the initial `phoenix sync all` command has been executed.

## 1. Core Component Health Check

First, ensure all the core infrastructure components are running.

**Command:**
```bash
phoenix status 101 102 103 1001 1002
```

**Expected Outcome:**
You should see a "status: running" message for each of the LXC containers and VMs.

## 2. Gateway and Routing Verification

Check that the Nginx gateway and Traefik service discovery are functioning correctly.

**Commands:**
```bash
# Check Nginx logs for errors
pct exec 101 -- journalctl -u nginx -n 50

# Check Traefik logs for errors and service discovery
pct exec 102 -- journalctl -u traefik -n 100
```

**Expected Outcome:**
- Nginx logs should show no critical errors and indicate that it has successfully loaded the configuration.
- Traefik logs should show that it has detected the Docker Swarm provider and is discovering services (like Portainer).

## 3. Certificate Validation

Verify that the Step-CA has successfully issued certificates for the core services.

**Commands:**
```bash
# Check the Nginx certificate
ls -l /mnt/pve/quickOS/lxc-persistent-data/101/ssl/

# Check the Portainer certificate
ls -l /mnt/pve/quickOS/vm-persistent-data/1001/portainer/certs/

# Check the Traefik certificate
ls -l /mnt/pve/quickOS/lxc-persistent-data/102/certs/
```

**Expected Outcome:**
Each directory should contain the relevant `.crt` and `.key` files, indicating that the certificates were generated and placed correctly.

## 4. Docker Swarm and Portainer Status

Ensure the Docker Swarm is active and that the Portainer service is running.

**Commands:**
```bash
# Check the status of all nodes in the Swarm
phoenix swarm status

# List the services running on the Swarm
qm guest exec 1001 -- docker service ls
```

**Expected Outcome:**
- `phoenix swarm status` should show both the manager (VM 1001) and the worker (VM 1002) with a status of "Ready" and "Active".
- `docker service ls` should show the `prod_portainer_service_portainer` service with `1/1` replicas running.

## 5. Application Stack Verification

Finally, check that the application stacks defined in your configuration have been deployed.

**Command:**
```bash
# List all deployed stacks on the Swarm
qm guest exec 1001 -- docker stack ls
```

**Expected Outcome:**
You should see a list of the stacks that were deployed by the `sync all` command, such as `prod_qdrant_service`.

By following these steps, you can be confident that your Phoenix environment is fully operational.
