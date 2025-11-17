# Traefik Swarm Discovery Fix Plan (v2)

## Root Cause Analysis

The Docker daemon on the Swarm Manager VM (1001) is failing to start due to a configuration conflict. Logs confirm that the `hosts` directive is being specified in two places simultaneously:
1.  As a command-line flag (`-H fd://`) in the default systemd service file.
2.  As a `hosts` array in the `/etc/docker/daemon.json` configuration file.

Docker cannot start with these conflicting instructions. The previous fixes were insufficient because they did not remove the default command-line flag from the main service file.

## The Definitive Fix Plan

The solution is to establish the `/etc/docker/daemon.json` file as the single source of truth for Docker's configuration. This will be achieved by modifying the installation script to be more robust and idempotent.

### 1. Update the Docker Installation Script

The script at `usr/local/phoenix_hypervisor/bin/vm_features/feature_install_docker.sh` will be modified to perform the following actions in sequence:

1.  **Clean Up Conflicting Overrides:** Add a step to forcefully remove the systemd override directory (`/etc/systemd/system/docker.service.d`) to ensure no old, conflicting configurations are present from previous failed runs.
2.  **Remove Conflicting Flag:** Add a `sed` command to directly edit the main service file (`/usr/lib/systemd/system/docker.service`) and remove the `-H fd://` argument from the `ExecStart` line. This eliminates the source of the conflict.
3.  **Apply Correct Configuration:** The script will then proceed as it does now, creating the `daemon.json` file, which will now be the sole authority for the Docker host configuration.

### 2. Re-Converge the Swarm Manager VM

Once the installation script is corrected, the configuration on the Swarm Manager VM must be reapplied.

- **Action:** Execute the command `phoenix converge 1001`.
- **Justification:** This will run the updated script, which will first clean the environment of any bad state and then apply the single, correct configuration, allowing the Docker service to start successfully.

### 3. Verify Functionality

After the convergence, we will confirm that the fix is successful.

- **Action 1:** Check the status of the Docker service on VM 1001.
- **Action 2:** Inspect the Traefik dashboard to confirm the Swarm provider is connected.
- **Action 3:** Deploy a test service and verify it is discovered and accessible.