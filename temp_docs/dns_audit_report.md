# DNS Audit Report

## 1. Executive Summary

This report provides an analysis of the internal DNS architecture for the Phoenix Hypervisor environment. The system uses a dedicated DNS server, running within the Nginx container (LXC 101), to provide name resolution for all internal services. This centralized approach simplifies service discovery and provides a single source of truth for all internal domain names.

## 2. Architecture Overview

The internal DNS server is a key component of the Phoenix Hypervisor's networking infrastructure.

*   **LXC 101 (Nginx & DNS Server):** The Nginx container is configured with the `dns_server` feature, which installs and configures a DNS server. This server is responsible for resolving all internal domain names (e.g., `portainer.phoenix.local`, `ca.internal.thinkheads.ai`).
*   **VMs and Containers:** All VMs and containers within the environment are configured to use the Nginx container (10.0.0.153) as their primary nameserver.

This architecture ensures that all DNS queries for internal services are resolved locally, without the need to query external DNS servers.

## 3. DNS Records and Configuration

The internal DNS server uses a simple `/etc/hosts` file to manage DNS records. This file is populated by the `phoenix_hypervisor_lxc_102.sh` script during the setup of the Traefik container.

The following table details the DNS records for the internal network:

| IP Address | Hostname |
|---|---|
| 10.0.0.10 | `ca.internal.thinkheads.ai` |
| 10.0.0.153 | `traefik.internal.thinkheads.ai` |
| 10.0.0.153 | `granite-embedding.internal.thinkheads.ai` |
| 10.0.0.153 | `granite-3b.internal.thinkheads.ai` |
| 10.0.0.153 | `ollama.internal.thinkheads.ai` |
| 10.0.0.153 | `llamacpp.internal.thinkheads.ai` |

## 4. Analysis and Recommendations

This section will analyze the effectiveness of the current DNS configuration and provide recommendations for potential improvements.

### 4.1. Strengths

*   **Centralized Name Resolution:** A single, internal DNS server provides a consistent and reliable way to resolve internal domain names.
*   **Simplified Service Discovery:** The use of DNS simplifies service discovery, as services can be accessed by name rather than by IP address.
*   **Declarative Configuration:** The DNS server's configuration is managed as part of the declarative, Infrastructure-as-Code approach of the Phoenix Hypervisor.

### 4.2. Areas for Improvement

*   **Static Host File:** The use of a static `/etc/hosts` file for DNS resolution is simple, but it does not scale well. As the number of services grows, this file will become increasingly difficult to manage.
*   **Lack of Dynamic Updates:** The host file is only updated when the `phoenix_hypervisor_lxc_102.sh` script is run. This means that new services will not be discoverable until the script is re-run.
*   **Limited Querying Capabilities:** A host file-based DNS server does not provide the advanced querying capabilities of a full-featured DNS server, such as SRV records or DNS-based service discovery.

### 4.3. Recommendations

*   **Implement a Full-Featured DNS Server:** Replace the host file-based DNS server with a full-featured DNS server, such as CoreDNS or BIND. This will provide a more scalable and flexible solution for internal name resolution.
*   **Integrate with a Service Discovery System:** As a long-term goal, consider integrating the DNS server with a service discovery system, such as Consul or etcd. This would allow for the automatic registration and de-registration of services, providing a fully dynamic DNS environment.
*   **Centralize DNS Configuration:** Move the DNS record definitions from the `phoenix_hypervisor_lxc_102.sh` script to a dedicated configuration file. This will make it easier to manage the DNS records and will align with the Infrastructure-as-Code principles of the Phoenix Hypervisor.
