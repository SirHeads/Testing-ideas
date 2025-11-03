# Certificate Lifecycle Specification

## 1. Overview

This document outlines the certificate lifecycle management for the Phoenix Hypervisor system. It covers the issuance, renewal, and revocation of all internal TLS certificates.

## 2. Certificate Authority

The Phoenix Hypervisor system uses a Smallstep CA instance running in LXC container 103 as its internal Certificate Authority (CA). The CA is responsible for issuing and renewing all internal TLS certificates.

## 3. Certificate Issuance

Certificates are issued by the `phoenix_hypervisor_lxc_102.sh` script when the Traefik container is first set up. The script uses the `step ca certificate` command to request a new certificate from the Step CA.

## 4. Certificate Renewal

Certificate renewal is automated by the `certificate-renewal-manager.sh` script. This script is run on a daily cron job in the Step CA container (LXC 103). The cron job is created by the `hypervisor_feature_setup_auto_renewal.sh` script during the `phoenix setup` process.

The `certificate-renewal-manager.sh` script reads a manifest file at `/usr/local/phoenix_hypervisor/etc/certificate-manifest.json` to determine which certificates to renew. The script checks the expiration of each certificate and renews it if it is within the renewal threshold (12 hours).

The cron job is created as a file in `/etc/cron.d/phoenix-cert-renewal` and runs every 12 hours.

## 5. Certificate Revocation

Certificates can be revoked using the `step ca revoke` command. This should be done manually if a certificate is compromised or no longer needed.
