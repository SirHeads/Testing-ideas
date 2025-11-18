# Diagnostic Commands for Certificate Renewal Issue

Please run the following commands on your Proxmox host to diagnose the file permission issues within the guest VMs.

## VM 1002 (drphoenix-agent)

### 1. Check the contents and permissions of the /etc/docker/tls directory
```bash
qm guest exec 1002 -- /bin/ls -la /etc/docker/tls
```

### 2. Check the permissions of the /etc/docker/tls directory itself
```bash
qm guest exec 1002 -- /bin/ls -ld /etc/docker/tls
```

## VM 1001 (docker-daemon)

### 1. Check the contents and permissions of the /etc/docker/tls directory
```bash
qm guest exec 1001 -- /bin/ls -la /etc/docker/tls
```

### 2. Check the permissions of the /etc/docker/tls directory itself
```bash
qm guest exec 1001 -- /bin/ls -ld /etc/docker/tls
```

Please paste the full output of these commands.