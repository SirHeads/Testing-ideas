# Step-CA Certificate Verification Commands for VM 1001

## Objective
Verify that the trusted CA certificate has been correctly installed on VM 1001, as per the `feature_install_trusted_ca.sh` script.

## Commands to be executed inside VM 1001

1.  **Verify Certificate Existence:**
    *   **Purpose:** Confirms that the `phoenix_ca.crt` file exists in the system's shared certificate directory.
    *   **Command:**
        ```bash
        [ -f /usr/local/share/ca-certificates/phoenix_ca.crt ] && echo "SUCCESS: CA certificate file found." || echo "FAILURE: CA certificate file is missing."
        ```

2.  **Verify Certificate Symlink:**
    *   **Purpose:** After `update-ca-certificates` runs, it should create a symbolic link in `/etc/ssl/certs`. This command verifies that the link exists and is not broken. The actual filename might have a hash, so we'll look for any symlink pointing to our cert.
    *   **Command:**
        ```bash
        find /etc/ssl/certs -type l -exec readlink -f {} + | grep -q "/usr/local/share/ca-certificates/phoenix_ca.crt" && echo "SUCCESS: Certificate symlink is valid." || echo "FAILURE: Certificate symlink is missing or broken."
        ```

3.  **Verify Certificate Content:**
    *   **Purpose:** Checks that the content of the installed certificate matches the source certificate from persistent storage. This ensures the file wasn't corrupted during the copy.
    *   **Command:**
        ```bash
        diff -q /usr/local/share/ca-certificates/phoenix_ca.crt /persistent-storage/.phoenix_scripts/phoenix_ca.crt && echo "SUCCESS: Certificate content matches source." || echo "FAILURE: Certificate content differs from source."
        ```

4.  **Verify with OpenSSL:**
    *   **Purpose:** Uses OpenSSL to verify that the system's trust store recognizes the certificate. This is the ultimate test of whether the installation was successful.
    *   **Command:**
        ```bash
        openssl verify /usr/local/share/ca-certificates/phoenix_ca.crt
