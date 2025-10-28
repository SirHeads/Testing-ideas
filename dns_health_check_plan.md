# DNS Resolution Health Check Plan

## 1. Objective

To create a reusable health check script, `check_dns_resolution.sh`, that can validate the correct functioning of the split-horizon DNS system from both the hypervisor host and a guest container.

## 2. Script Design

The script will be designed to be called with arguments that specify the execution context and the domain to be tested.

**Usage:**
```bash
./check_dns_resolution.sh --context <host|guest> --guest-id <CTID> --domain <domain_to_resolve> --expected-ip <expected_ip_address>
```

- `--context`: Specifies whether the check is being run from the `host` or a `guest` container.
- `--guest-id`: The ID of the guest container (required if context is `guest`).
- `--domain`: The DNS record to resolve.
- `--expected-ip`: The IP address that the domain is expected to resolve to.

## 3. Health Checks

### 3.1. Host Context Check (`--context host`)

1.  **Action:** Run `dig +short <domain>` on the hypervisor host.
2.  **Validation:** Compare the result with the `--expected-ip`.
3.  **Purpose:** To confirm that the host's own `/etc/resolv.conf` is correctly configured and that the `dnsmasq` service is responding correctly to local queries.

### 3.2. Guest Context Check (`--context guest`)

1.  **Action:** Use `pct exec <guest-id> -- dig +short <domain>` to run the DNS query from within the specified guest container.
2.  **Validation:** Compare the result with the `--expected-ip`.
3.  **Purpose:** To confirm that guest containers are correctly configured to use the host's `dnsmasq` service and that the firewall rules allow the necessary DNS traffic.

## 4. Implementation Plan

1.  Create the `check_dns_resolution.sh` script in `usr/local/phoenix_hypervisor/bin/health_checks/`.
2.  Implement the argument parsing and logic for both the `host` and `guest` contexts.
3.  Integrate this new health check into the `lxc-manager.sh` script to be run after the creation of critical containers like the Nginx gateway.