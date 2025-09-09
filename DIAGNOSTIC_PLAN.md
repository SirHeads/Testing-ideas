# Server Deployment Issue: Diagnostic Plan

## Objective
This plan outlines a series of non-destructive checks to systematically diagnose why an updated Python script (`/opt/app/embedding_server.py`) is not being loaded by the `uvicorn` server process in the Proxmox LXC container.

---

### Hypothesis 1: Rogue Process Manager

**Theory:** An unknown process manager (e.g., `supervisord`, `pm2`, or a cron job) is automatically restarting the `uvicorn` process, overwriting our manual intervention.

**Diagnostic Steps:**

1.  **Check for common process managers:**
    ```bash
    ps aux | grep -E "supervisord|pm2|cron"
    ```
2.  **Look for systemd user services that might not be obvious:**
    ```bash
    systemctl --user list-units | grep -i uvicorn
    ```
3.  **Check the crontab for any relevant entries:**
    ```bash
    crontab -l
    cat /etc/crontab /etc/cron.*/*
    ```

---

### Hypothesis 2: File System or Mount Issues

**Theory:** The `/opt/app` directory is a mount point from a read-only, ephemeral, or network-based file system, causing our changes to be ignored or reverted.

**Diagnostic Steps:**

1.  **Check the mount points on the system:**
    ```bash
    df -h
    mount | grep "/opt/app"
    ```
2.  **Inspect the container's configuration for mount definitions (if accessible from the Proxmox host):**
    ```bash
    pct config <CT_ID>
    ```
3.  **Perform a "touch test" to see if a new file persists after a restart:**
    ```bash
    touch /opt/app/test_persistence.txt
    # Manually restart the uvicorn process as before
    ls /opt/app/test_persistence.txt
    ```

---

### Hypothesis 3: Python Caching or Environment Issues

**Theory:** Python is using a cached version of the old script (`.pyc` files) or the Python path is incorrect.

**Diagnostic Steps:**

1.  **Find and delete all `.pyc` cache files:**
    ```bash
    find /opt/app -name "*.pyc" -delete
    find /opt/vllm -name "*.pyc" -delete
    ```
2.  **Check the Python path being used by the running process:**
    *   First, find the PID of the `uvicorn` process: `ps aux | grep uvicorn`
    *   Then, inspect the environment of that process (replace `<PID>`):
        ```bash
        cat /proc/<PID>/environ | tr '\0' '\n' | grep PYTHONPATH
        ```
3.  **Explicitly check the version of the code Python is loading:**
    *   Add a temporary print statement to the top of `/opt/app/embedding_server.py`:
        ```python
        import time
        print(f"LOADING embedding_server.py - VERSION: {time.time()}")
        ```
    *   Restart the server and check the logs to see if the new version timestamp appears.

---

### Hypothesis 4: Container Orchestration or Configuration Management

**Theory:** A tool like Ansible, Puppet, or a Docker entrypoint script is enforcing a specific file state, reverting our changes.

**Diagnostic Steps:**

1.  **Check for common configuration management agents:**
    ```bash
    ps aux | grep -E "ansible|puppet|chef|salt"
    ```
2.  **Review the container's entrypoint or command (if it's a Docker-like container):**
    *   This may require inspecting the container's configuration on the Proxmox host.
3.  **Look for signs of recent file changes by other users/processes:**
    ```bash
    stat /opt/app/embedding_server.py
    ```
    *   Pay close attention to the `Modify` and `Change` timestamps.

---

### Hypothesis 5: Multiple `uvicorn` Processes

**Theory:** There are multiple `uvicorn` processes running, and we are killing and restarting a decoy process while an old one continues to serve requests.

**Diagnostic Steps:**

1.  **Get a detailed list of all Python processes:**
    ```bash
    ps aux | grep python
    ```
2.  **Use `pstree` to see the process hierarchy:**
    ```bash
    pstree -p
    ```
3.  **Kill all `uvicorn` processes decisively before restarting:**
    ```bash
    pkill -f uvicorn
    # Verify they are all gone
    ps aux | grep uvicorn
    # Then restart the server
    ```
