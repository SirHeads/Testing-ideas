---
title: "Monitoring and Logging Guide"
summary: "This guide provides an overview of the monitoring and logging capabilities of the Phoenix Hypervisor."
document_type: "Implementation Guide"
status: "Published"
version: "1.0.0"
author: "Thinkheads.AI"
owner: "Developer"
tags:
  - "Monitoring"
  - "Logging"
  - "Health Checks"
review_cadence: "Annual"
last_reviewed: "2025-09-29"
---

# Monitoring and Logging Guide

This guide provides an overview of the monitoring and logging capabilities of the Phoenix Hypervisor.

## 1. Centralized Logging

All scripts within the Phoenix Hypervisor framework, including the main `phoenix-cli` CLI and all manager and feature scripts, log their output to a central log file:

*   **Log File Location:** `/var/log/phoenix-cli_hypervisor.log`

This centralized approach allows for easy monitoring and troubleshooting of the entire system. You can monitor the log in real-time using the `tail -f` command:

```bash
tail -f /var/log/phoenix-cli_hypervisor.log
```

### Log Levels

The logging functions in `phoenix-cli_hypervisor_common_utils.sh` support the following log levels:

*   **DEBUG:** Detailed information for debugging purposes. Enabled by setting the `PHOENIX_DEBUG` environment variable to `true`.
*   **INFO:** General information about the script's execution.
*   **SUCCESS:** Indicates the successful completion of a significant operation.
*   **WARN:** Indicates a potential issue that does not prevent the script from continuing.
*   **ERROR:** Indicates a recoverable error.
*   **FATAL:** Indicates an unrecoverable error that causes the script to exit.

## 2. Health Checks and Post-Deployment Validation

The Phoenix Hypervisor includes a framework for running automated health checks and post-deployment validation tests.

*   **Test Runner:** The `/usr/local/phoenix-cli_hypervisor/bin/tests/test_runner.sh` script is the entry point for all automated testing.
*   **Integration:** The testing framework is integrated into the `lxc-manager.sh` script and is run automatically after a container is created.
*   **Configuration:** The tests to be run for each container are defined in the `tests` section of the container's configuration in `phoenix-cli_lxc_configs.json`.

## 3. Integration with External Monitoring Tools

The health check and validation scripts can be extended to output metrics in a format that can be scraped by external monitoring tools like Prometheus. This allows for the integration of the Phoenix Hypervisor into a broader monitoring and alerting infrastructure.