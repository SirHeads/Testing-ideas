# Container 902 Test Plan

This document outlines the health checks and integration tests for container 902, the Docker template container.

## Health Checks

| Test Name | Description |
|---|---|
| `check_docker_service` | Verifies that the Docker service is active and running within the container. |
| `check_network_access` | Confirms that the container has basic network connectivity by pinging a reliable external host. |
| `check_dns_resolution` | Ensures that DNS is functioning correctly by resolving a common domain name. |

## Integration Tests

| Test Name | Description |
|---|---|
| `test_docker_hello_world` | Runs the `hello-world` Docker container to confirm that the most basic Docker functionality is working. |
| `test_docker_storage_driver` | Checks that Docker is using the `fuse-overlayfs` storage driver, as intended by the AppArmor profile. |
| `test_apparmor_confinement` | Monitors the host's audit log for any AppArmor denials related to container 902 while the other tests are running. |
| `test_shared_storage_mount` | Verifies that the container can correctly mount and access the shared storage locations defined in the AppArmor profile. |