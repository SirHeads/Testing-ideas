---
title: Phoenix Hypervisor Testing Framework
summary: This document provides an overview of the testing framework for the Phoenix Hypervisor project, including instructions for running tests and adding new ones.
document_type: Quality and Testing
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Developer
tags:
  - Testing
  - Framework
  - Automation
review_cadence: Annual
last_reviewed: 2025-09-23
---

# Phoenix Hypervisor Testing Framework

This document provides an overview of the testing framework for the Phoenix Hypervisor project.

## Running Tests

The main test script is `test_hypervisor_setup.sh`, located in the `bin/tests` directory.

### Running All Tests

To run all tests, execute the script without any arguments:

```bash
./bin/tests/test_hypervisor_setup.sh
```

### Running Tagged Tests

You can run specific groups of tests by providing one or more tags as arguments. For example, to run only the smoke tests:

```bash
./bin/tests/test_hypervisor_setup.sh smoke
```

To run the core and GPU tests:

```bash
./bin/tests/test_hypervisor_setup.sh core gpu
```

Available tags are:
* `core`: Core system configuration (repositories, packages, time, network, firewall)
* `zfs`: ZFS pool and dataset configuration
* `gpu`: NVIDIA driver installation and configuration
* `services`: User creation and NFS/Samba shares
* `smoke`: A small set of critical tests to quickly verify basic functionality

## Adding New Tests

To add a new test, follow these steps:

1.  **Create a new test function** in `test_hypervisor_setup.sh`. The function name should be descriptive and start with `test_`.
2.  **Add the new test function to a tag** in the `TEST_TAGS` associative array in `test_hypervisor_setup.sh`. If a suitable tag doesn't exist, you can create a new one.
3.  **Implement the test logic** in the new function, using the assertion functions provided in `test_utils.sh`.

### Example

Here is an example of how to add a new test that checks if a specific file exists:

```bash
# In test_hypervisor_setup.sh

# ...

# Add the new test to the 'core' tag
TEST_TAGS[core]+=" test_my_new_feature"

# ...

test_my_new_feature() {
    start_suite "My New Feature"
    assert_file_exists "/path/to/my/file" "My file exists"
}

## 6. Container-Native Testing

In addition to host-level testing, it is crucial to verify the functionality of application scripts within the container's native environment. This ensures that all dependencies, paths, and permissions are correctly configured.

### Manual Testing Procedure

1.  **Access the Container Shell**:
    ```bash
    pct enter <CTID>
    ```
2.  **Navigate to the Script Directory**:
    Application scripts are typically located in the `/usr/local/bin` directory inside the container.
3.  **Execute the Script**:
    Run the script with the appropriate arguments and observe its output for any errors.
    ```bash
    /usr/local/bin/your_application_script.sh <arguments>
    ```
4.  **Check Logs**:
    Review the systemd journal or application-specific log files for any errors or unexpected behavior.
    ```bash
    journalctl -u <service_name>