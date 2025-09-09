# Qdrant Container Failure in LXC 952 - Diagnostic Plan

## 1. Initial Assessment
- [ ] **Goal:** Verify the running status of LXC 952.
- [ ] **Action:** Use the appropriate `phoenix_hypervisor` script to check the status of LXC 952.

## 2. Docker Service Health Check
- [ ] **Goal:** Ensure the Docker service is active within LXC 952.
- [ ] **Action:** Execute a command inside LXC 952 to check the status of the Docker daemon.

## 3. Qdrant Container Investigation
- [ ] **Goal:** Inspect the Qdrant container for error messages.
- [ ] **Action:** View the logs of the failed Qdrant container to identify specific startup errors.
- [ ] **Action:** Inspect the container's configuration (`docker inspect`).

## 4. Resource Utilization Analysis
- [ ] **Goal:** Check for resource exhaustion (CPU, Memory, Disk) in LXC 952.
- [ ] **Action:** Check the memory and CPU usage of the LXC.
- [ ] **Action:** Check the disk space available within the LXC and on the Docker volumes.

## 5. Propose and Verify Solution
- [ ] **Goal:** Based on the findings, propose a solution.
- [ ] **Action:** Ask for user confirmation of the diagnosis.
- [ ] **Action:** Apply the fix.
- [ ] **Action:** Verify that the Qdrant container starts successfully and that the Nginx gateway in LXC 953 becomes healthy.
