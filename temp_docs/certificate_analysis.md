# Certificate Generation and Renewal Analysis

This document analyzes the certificate management process within the Phoenix Hypervisor system, focusing on the `certificate-renewal-manager.sh` script and its interaction with the Step-CA container (LXC 103).

## Process Overview

The `certificate-renewal-manager.sh` script is the central component for managing the lifecycle of all internal TLS certificates. It operates in a declarative manner, driven by the `certificate-manifest.json` file.

1.  **Manifest-Driven:** The script reads the `etc/certificate-manifest.json` file, which contains a list of all certificates to be managed. Each entry in the manifest defines:
    *   `common_name`: The primary domain for the certificate.
    *   `cert_path` & `key_path`: The locations on the hypervisor where the certificate and key files should be stored.
    *   `owner` & `permissions`: The file ownership and permissions to be applied after renewal.
    *   `sans`: A list of Subject Alternative Names to be included in the certificate.
    *   `post_renewal_command`: A shell command to be executed after a successful renewal.

2.  **Renewal Check:** For each certificate in the manifest, the script checks if a renewal is necessary. A renewal is triggered if:
    *   The certificate file does not exist.
    *   The certificate is expired or will expire within the next 12 hours.
    *   The Subject Alternative Names (SANs) in the certificate do not match the SANs defined in the manifest.

3.  **Certificate Generation:** If a renewal is needed, the script executes the `step ca certificate` command. This command communicates with the Step-CA service running in LXC 103 to request a new certificate. The `--force` flag is used to ensure that a new certificate is always issued, even if a valid one already exists.

4.  **Post-Renewal Actions:** After a certificate is successfully renewed, the script executes the `post_renewal_command` defined in the manifest. This is a critical step for ensuring that services are reloaded to use the new certificate. For example, the Nginx service is reloaded after its certificate is renewed.

## Key Components

-   **Step-CA (LXC 103):** This container runs the Smallstep CA service, which acts as the root of trust for the entire internal network. It is responsible for issuing all internal TLS certificates.
-   **`certificate-manifest.json`:** This file is the single source of truth for all managed certificates. It provides a declarative way to manage the certificate lifecycle.
-   **`certificate-renewal-manager.sh`:** This script provides the automation for the renewal process. It is executed as part of the `phoenix sync all` command, ensuring that all certificates are checked and renewed if necessary during each sync.

## Potential Issues

1.  **Step-CA Unavailability:** If the Step-CA container (LXC 103) is not running or is not accessible from the hypervisor, the `step ca certificate` command will fail, and no certificates can be renewed.
2.  **Firewall Rules:** The hypervisor's firewall must allow traffic from the host to the Step-CA container on port 9000. If this rule is missing or incorrect, certificate renewal will fail.
3.  **Provisioner Password:** The `step ca certificate` command requires a provisioner password to authenticate with the CA. This password is read from a file on the NFS share. If this file is missing, inaccessible, or contains the wrong password, renewals will fail.
4.  **Post-Renewal Command Failures:** If a `post_renewal_command` fails, the service may not be reloaded, and it will continue to use the old, expired certificate. This can lead to service disruptions.
5.  **File Permissions:** Incorrect file permissions on the certificate and key files can prevent services from reading them. The `owner` and `permissions` fields in the manifest are critical for ensuring that services have the necessary access.
