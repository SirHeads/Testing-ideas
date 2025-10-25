# Troubleshooting Guide

This guide provides a structured approach to diagnosing and resolving common issues with the Phoenix Hypervisor.

## General Troubleshooting Steps

When encountering an issue, it is best to follow a systematic approach to identify the root cause. The following steps are recommended:

1.  **Check the Logs**: All scripts in the Phoenix Hypervisor framework log their output to `/var/log/phoenix_hypervisor.log`. This is the first place to look for error messages and other diagnostic information. You can use the `tail -f` command to monitor the log in real-time.
2.  **Verify the Configuration**: Ensure that the `phoenix_hypervisor_config.json` and `phoenix_lxc_configs.json` files are correctly configured. Pay close attention to IP addresses, storage pool names, and other critical parameters.
3.  **Check the Network**: Verify that the network is correctly configured and that all containers and VMs have network connectivity. Use the `ping` and `nc` commands to test connectivity between components.
4.  **Check the Storage**: Ensure that the storage pool is correctly configured and that there is sufficient space available. Use the `pvesm status` command to check the status of your storage pools.
5.  **Check the Host**: Verify that the Proxmox host is running correctly and that all services are up and running. Use the `systemctl status` command to check the status of key services like `pvedaemon` and `pveproxy`.

## Common Issues and Resolutions

### `idmap` Generation Failure

**Symptom**: The `idmap` generation fails, and the container fails to start.

**Cause**: This is often caused by an overly restrictive AppArmor profile that prevents unprivileged containers from performing necessary `mount` operations during startup.

**Resolution**: Modify the AppArmor profile to allow these operations. The `lxc-phoenix-v2` profile is a good starting point.

### Container Fails to Start

**Symptom**: A container fails to start, and the `pct start` command returns an error.

**Cause**: This can be caused by a variety of issues, including incorrect configuration, insufficient resources, or a problem with the container's template.

**Resolution**:

1.  Check the container's configuration in the `phoenix_lxc_configs.json` file.
2.  Ensure that there are sufficient resources (CPU, memory, storage) available on the Proxmox host.
3.  Try creating a new container from the same template to see if the issue is with the template itself.
4.  Check the system log (`/var/log/syslog`) for more detailed error messages.

### Service Not Accessible from the Network

**Symptom**: A service running in a container is not accessible from the network.

**Cause**: This is often caused by a firewall issue or an incorrect NGINX configuration.

**Resolution**:

1.  Check the firewall rules on the Proxmox host and in the container.
2.  Verify that the NGINX configuration is correct and that the reverse proxy is correctly configured.
3.  Use the `ping` and `nc` commands to test network connectivity between the client, the NGINX gateway, and the container.