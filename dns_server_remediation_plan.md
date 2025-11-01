# DNS Server Remediation Plan

## 1. Analysis of the Failure

The `dnsmasq` service on the hypervisor is active but unresponsive to local queries. The service logs show the critical error: `ignoring nameserver 10.0.0.13 - local interface`.

This is caused by a DNS loop. The `/etc/resolv.conf` file on the hypervisor is configured to use `10.0.0.13` (itself) as a nameserver. By default, `dnsmasq` reads this file to determine its upstream servers. It detects that it is being asked to forward queries to itself, and to prevent a loop, it ignores its own address.

As a result, `dnsmasq` only forwards queries to external servers (`8.8.8.8`, `1.1.1.1`) and never resolves queries for the internal domain (`internal.thinkheads.ai`) from its own configuration files.

## 2. Proposed Change

The solution is to instruct `dnsmasq` to not use the system's `/etc/resolv.conf` file. We will do this by adding the `no-resolv` option to its main configuration file.

**File to Modify**: `usr/local/phoenix_hypervisor/bin/hypervisor_setup/hypervisor_feature_setup_dns_server.sh`

**Diff**:

```diff
<<<<<<< SEARCH
# Prevent DNS-rebind attacks
stop-dns-rebind
# Do not forward queries for the internal domain
local=/internal.thinkheads.ai/
=======
# Prevent DNS-rebind attacks
stop-dns-rebind
# Do not read /etc/resolv.conf for upstream servers
no-resolv
# Do not forward queries for the internal domain
local=/internal.thinkheads.ai/
>>>>>>> REPLACE
```

This change will break the DNS loop and ensure `dnsmasq` correctly serves records for the internal domain.

## 3. Verification

1.  Apply the code change.
2.  Run `phoenix setup` to regenerate the `dnsmasq` configuration and restart the service.
3.  Run `phoenix sync all` to confirm the entire process completes successfully.
