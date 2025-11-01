# Traefik ACME Challenge Remediation Plan

## 1. Diagnosis

The root cause of the ACME `http-01` challenge failure is a misconfiguration in how Traefik services are defined. Services with a `traefik_service` block in `phoenix_lxc_configs.json` and `phoenix_vm_configs.json` are missing the `tls.certresolver` label. This prevents Traefik from initiating the ACME challenge with the Step-CA server.

## 2. Remediation

The script that generates the Traefik dynamic configuration must be updated to include the `tls.certresolver=internal-resolver` label for all services that have a `traefik_service` block.

This will be done by modifying the `generate_traefik_config.sh` script.

## 3. Validation

After the changes are applied, we will need to:
1.  Restart the Traefik service to load the new configuration.
2.  Monitor the Step-CA logs to confirm that certificate requests are now being successfully processed.
3.  Verify that the services are accessible via HTTPS with a valid certificate.

## 4. Rollback

In the event of a failure, the changes to `generate_traefik_config.sh` can be reverted, and the Traefik service can be restarted to restore the previous configuration.