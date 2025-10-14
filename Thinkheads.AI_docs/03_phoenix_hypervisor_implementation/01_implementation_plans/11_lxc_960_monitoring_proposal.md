---
title: 'LXC 960: Dedicated Monitoring Container for Prometheus and Grafana'
summary: This document outlines the implementation of a dedicated LXC container (CTID 960) to host Prometheus and Grafana for monitoring the Thinkheads.AI ecosystem.
document_type: Proposal
status: Approved
version: '1.0'
author: Roo
owner: Thinkheads.AI
tags:
  - lxc
  - monitoring
  - prometheus
  - grafana
review_cadence: Annual
last_reviewed: '2025-09-23'
---

# Phoenix LXC 960 Proposal: Dedicated Monitoring Container for Prometheus and Grafana

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Introduction](#introduction)
3. [Proposed Architecture](#proposed-architecture)
   1. [Container Configuration](#container-configuration)
   2. [Deployment via Docker Compose](#deployment-via-docker-compose)
   3. [Prometheus Configuration](#prometheus-configuration)
   4. [Grafana Configuration](#grafana-configuration)
4. [Exporters and Metrics Integration](#exporters-and-metrics-integration)
   1. [Proxmox VE Exporter](#proxmox-ve-exporter)
   2. [NVIDIA DCGM Exporter](#nvidia-dcgm-exporter)
   3. [vLLM Metrics](#vllm-metrics)
   4. [Qdrant Metrics](#qdrant-metrics)
   5. [Other Application Metrics](#other-application-metrics)
5. [Integration with Phoenix Orchestrator](#integration-with-phoenix-orchestrator)
   1. [Schema Updates](#schema-updates)
   2. [Feature Scripts](#feature-scripts)
   3. [Shared Volumes and Dependencies](#shared-volumes-and-dependencies)
6. [Security and Best Practices](#security-and-best-practices)
7. [Benefits and Leverage Opportunities](#benefits-and-leverage-opportunities)
8. [Implementation Steps](#implementation-steps)
9. [Potential Challenges and Mitigations](#potential-challenges-and-mitigations)
10. [Roadmap and Future Enhancements](#roadmap-and-future-enhancements)
11. [References](#references)

---

## Executive Summary

This proposal outlines the implementation of a dedicated LXC container (CTID 960) within the Phoenix Orchestrator to host Prometheus (metrics collection) and Grafana (visualization and alerting). This monitoring solution enhances observability across the Thinkheads.AI ecosystem, covering the Proxmox host, LXC containers, NVIDIA GPUs, and AI/ML applications like vLLM, Qdrant, n8n, Ollama, and llama.cpp. Deployed using Docker within an unprivileged LXC container cloned from the "Template-Docker" (CTID 902), the setup ensures modularity, idempotency, and alignment with existing engineering principles. Key benefits include real-time insights, proactive alerting, and optimized resource utilization for AI workloads, with integration into the existing NGINX proxy (CTID 101) for secure dashboard access. The implementation is low-overhead, scalable, and designed to showcase DevOps expertise to potential employers.

---

## Introduction

The Phoenix Orchestrator, as detailed in `phoenix_orchestrator_v1_product_report.md`, efficiently provisions AI/ML environments but lacks comprehensive monitoring. Prometheus and Grafana address this gap by providing robust time-series metrics collection and interactive visualization, respectively. This proposal outlines a containerized deployment within the Proxmox environment, leveraging Docker for simplicity and isolation. The solution aligns with the orchestrator’s declarative, modular, and idempotent design, ensuring seamless integration. Key objectives include:

- Real-time monitoring of host, container, GPU, and application health.
- Proactive alerting for anomalies (e.g., GPU utilization >80%).
- AI-specific metrics (e.g., vLLM inference latency, Qdrant query performance).
- Enhanced visibility to optimize resources and demonstrate technical mastery.

---

## Proposed Architecture

### VM Configuration

Create a dedicated VM to host the monitoring stack. This aligns with the new architecture of running all Docker workloads in VMs for better isolation and security.

**Configuration in `phoenix_vm_configs.json`**:

```json
{
    "vm_id": 1003,
    "vm_name": "monitoring",
    "description": "Monitoring Stack (Prometheus and Grafana)",
    "tags": ["monitoring"],
    "features": ["base_setup", "docker"],
    "docker_stacks": ["monitoring"]
}
```

**Configuration in `phoenix_stacks_config.json`**:

```json
{
    "name": "monitoring",
    "git_repo": "https://github.com/your-org/monitoring-stack.git",
    "env": [
        { "name": "GRAFANA_ADMIN_PASSWORD", "value": "your-secret-password" }
    ]
}
```

### Declarative Stack Deployment

The monitoring stack will be deployed using the new declarative stack management system. The `docker-compose.yml` file will be stored in a dedicated Git repository and deployed by the `vm-manager.sh` script via the Portainer API.

**`docker-compose.yml` in the Git Repository**:

```yaml
version: '3.8'
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"
    restart: unless-stopped
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    volumes:
      - grafana-data:/var/lib/grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_INSTALL_PLUGINS=grafana-piechart-panel
    restart: unless-stopped
volumes:
  prometheus-data:
  grafana-data:
```

### Prometheus Configuration

Configure `/opt/monitoring/prometheus.yml` to scrape metrics from the Proxmox host, containers, and applications:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  - job_name: 'proxmox'
    static_configs:
      - targets: ['localhost:9221']
  - job_name: 'node'
    static_configs:
      - targets: ['10.0.0.13:9100']
  - job_name: 'dcgm'
    static_configs:
      - targets: ['10.0.0.13:9400']
  - job_name: 'vllm'
    static_configs:
      - targets: ['10.0.0.102:6333/metrics']
```

**Alerting Rules** (e.g., `/etc/prometheus/rules/alerts.yml`):

```yaml
groups:
- name: system_alerts
  rules:
  - alert: HighCPUUsage
    expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High CPU usage detected on {{ $labels.instance }}"
  - alert: HighGPUMemory
    expr: DCGM_FI_DEV_MEMORY_UTIL > 80
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "GPU memory usage exceeds 80% on {{ $labels.instance }}"
```

### Grafana Configuration

Provision datasources and dashboards via `/etc/grafana/provisioning/`:

**Datasource** (`/etc/grafana/provisioning/datasources/prometheus.yml`):

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
```

**Dashboards**: Import community dashboards:
- Proxmox VE (ID 10471): Host/VM/LXC metrics.
- NVIDIA DCGM (ID 12238): GPU utilization, memory, temperature.
- vLLM (custom, based on vLLM docs): Inference metrics.
- Qdrant (official): Collection and query performance.

---

## Exporters and Metrics Integration

### Proxmox VE Exporter

Install `prometheus-pve-exporter` on the Proxmox host:

```bash
pip install prometheus-pve-exporter
pve_exporter --pve.user=monitor@pve --pve.password=secure_password
```

Run as a systemd service on port 9221. Metrics include node status, VM/LXC uptime, storage usage (e.g., quickOS ZFS pools).

### NVIDIA DCGM Exporter

Install DCGM on the host or GPU containers:

```bash
apt install -y datacenter-gpu-manager
```

Run `dcgm-exporter` in CTID 960 or per-GPU container:

```yaml
dcgm-exporter:
  image: nvcr.io/nvidia/k8s/dcgm-exporter:latest
  privileged: true
  runtime: nvidia
  ports:
    - "9400:9400"
```

Metrics: GPU utilization, VRAM usage, temperature, power draw, ECC errors.

### vLLM Metrics

vLLM containers expose a Prometheus-compatible `/metrics` endpoint. This can be scraped to monitor request latency, throughput, queue size, and token generation rate, providing critical insights into inference performance.

### Qdrant Metrics

Qdrant (now on VM 1002) exposes `/metrics` for collection sizes, query latency, storage usage. Integrate with official Grafana dashboard for RAG performance insights.

### Other Application Metrics

- **n8n**: Use cAdvisor for CPU/memory; consider `process-exporter` for workflow metrics.
- **Ollama (CTID 955)**: No native exporter; monitor via cAdvisor or custom API wrapper.
- **llama.cpp (CTID 957)**: Similar to Ollama; integrate DCGM for GPU metrics.
- **Node Exporter**: Install on host (`apt install prometheus-node-exporter`) for system metrics (CPU, memory, disk, network).

---

## Integration with Phoenix Orchestrator

### Schema Updates

Extend `phoenix_lxc_configs.schema.json`:

```json
"features": {
    "type": "array",
    "items": {
        "type": "string",
        "enum": ["base_setup", "nvidia", "docker", "vllm", "monitoring"]
    }
}
```

Update CTID pattern: `"^(90[0-4]|910|920|95[5-7]|960)$"`.


### Shared Volumes and Dependencies

Add to `phoenix_hypervisor_config.json` under `"shared_volumes"`:

```json
"monitoring_data": {
    "host_path": "/mnt/pve/quickOS/shared-prod-data/monitoring",
    "mounts": { "960": "/opt/monitoring/data" }
}
```

Dependency: CTID 101 (NGINX) for proxying Grafana/Prometheus (e.g., `/grafana` to `10.0.0.160:3000`).

---

## Security and Best Practices

- **Unprivileged LXC**: Ensures isolation.
- **Firewall**: Restrict access to 10.0.0.153 (NGINX).
- **Secrets**: Store `GF_SECURITY_ADMIN_PASSWORD` in Vault (roadmap).
- **Retention**: Set Prometheus storage to 30 days (`--storage.tsdb.retention.time=30d`).
- **Backup**: Include `/opt/monitoring/data` in ZFS snapshots.
- **High Availability**: Plan for federated Prometheus in multi-node setups.

---

## Benefits and Leverage Opportunities

- **Real-Time Visibility**: Dashboards for GPU utilization, vLLM throughput, Qdrant query latency.
- **Proactive Alerting**: Notify via n8n (CTID 954) for issues (e.g., GPU memory >80%).
- **Resource Optimization**: Identify underutilized cores/memory; tune vLLM tensor parallelism.
- **AI Insights**: Monitor inference performance to optimize quantization (e.g., AWQ).
- **Showcase**: Highlights DevOps expertise for Thinkheads.AI portfolio.
- **Predictive Analytics**: Use Grafana’s ML plugins for forecasting GPU overload.

---

## Implementation Steps

1.  Create a new Git repository for the monitoring stack, containing the `docker-compose.yml` and `prometheus.yml` files.
2.  Update `phoenix_stacks_config.json` to define the new `monitoring` stack.
3.  Update `phoenix_vm_configs.json` to define the new `monitoring` VM (ID 1003) and assign the `monitoring` stack to it.
4.  Run `phoenix-cli create 1003` to provision the VM and deploy the stack.
5.  Install the necessary exporters on the Proxmox host and other relevant machines.
6.  Configure NGINX (CTID 101) to proxy Grafana and Prometheus.
7.  Import the Grafana dashboards.
8.  Set up and validate alerting.

**Timeline**: 1 week for development and testing.

---

## Potential Challenges and Mitigations

- **Race Conditions**: Use `finalize_container_config` to ensure idmap generation before volumes (per `final_orchestrator_control_flow.md`).
- **Resource Overhead**: Monitor CTID 960; scale memory/cores if needed (start at 4GB/4 cores).
- **Metric Volume**: Use Prometheus downsampling (`--storage.tsdb.min-block-duration=2h`).
- **Compatibility**: Test with Ubuntu 24.04 (from CTID 902 template).
- **Security**: Restrict dashboard access; plan Vault integration.

---

## Roadmap and Future Enhancements

- **Log Aggregation**: Add Loki for logs, integrating with Grafana.
- **Auto-Discovery**: Dynamically update `prometheus.yml` via orchestrator.
- **CI/CD Integration**: Automate dashboard updates with Rumple pipelines.
- **OpenTelemetry**: Add tracing for vLLM inference workflows.
- **Multi-Node**: Plan for federated Prometheus if Proxmox scales.

---

## References

- **Internal**: `phoenix_orchestrator_v1_product_report.md`, `phoenix_lxc_configs.json`, `phoenix_hypervisor_config.json`, `final_orchestrator_control_flow.md`.
- **External**:
  - Prometheus: https://prometheus.io/docs/
  - Grafana: https://grafana.com/docs/
  - Proxmox VE Exporter: https://github.com/prometheus-pve/prometheus-pve-exporter
  - NVIDIA DCGM Exporter: https://github.com/NVIDIA/dcgm-exporter
  - vLLM Metrics: https://vllm.readthedocs.io/en/latest/serving/openai_compatible_server.html
  - Qdrant Metrics: https://qdrant.tech/documentation/monitoring/