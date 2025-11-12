# Plan to Fix Portainer Service and Certificate Renewal

This document outlines the necessary changes to resolve the `phoenix sync` hang and ensure the long-term stability of the Portainer service.

## 1. The Problem

The `phoenix sync` process is failing because the Portainer service, when deployed to Docker Swarm, is not publishing its ports correctly. This makes the Portainer API inaccessible to the orchestration script, causing it to hang indefinitely. Additionally, the certificate renewal process for Portainer is configured to restart a container by a static name, which is incompatible with a Swarm environment where container names are dynamic.

## 2. Proposed Solution

I will make the following two changes to fix these issues:

### Change 1: Correct Portainer's Port Mapping

I will modify the `usr/local/phoenix_hypervisor/stacks/portainer_service/docker-compose.yml` file to move the port definitions under the `deploy` key. This is the correct way to publish ports for a service in a Docker Swarm, and it will make the Portainer API accessible on the network.

### Change 2: Update Certificate Renewal Command

I will update the `usr/local/phoenix_hypervisor/etc/certificate-manifest.json` file to change the post-renewal command for the Portainer certificate. The new command will force a service update (`docker service update --force prod_portainer_service_portainer`), which is the correct way to apply a new certificate in a Swarm environment.

## 3. Expected Outcome

These changes will:

1.  **Resolve the `phoenix sync` hang:** By correctly publishing the Portainer ports, the orchestration script will be able to connect to the API and complete the setup process.
2.  **Ensure reliable certificate renewals:** The updated post-renewal command will ensure that new certificates are applied to the Portainer service without any manual intervention.
3.  **Restore 1001-to-1002 communication:** Once the Portainer service is running correctly, it will be able to manage the agent on VM 1002, resolving the user's concern about the two VMs being unable to communicate.

I am confident that these changes will fully resolve the issues you are experiencing. I am ready to proceed with the implementation as soon as you approve this plan.