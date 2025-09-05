# ThinkHeadsAI Environment Requirements

## High-Level Strategy
The ThinkHeadsAI environment is designed to support AI-driven web-based technology development, testing, and showcasing. The core strategy emphasizes:
- **Modularity and Portability**: Leverage Docker for all web-facing services to ensure consistency across development, testing, production, and live environments. This allows seamless replication and reduces deployment errors.
- **Resource Optimization**: Offload GPU-intensive AI tasks (e.g., LLM inference, model training) to a powerful local server (Phoenix), while using a lightweight, reliable hosted server (Rumple) for public web access. This minimizes costs and maximizes performance for low-volume usage.
- **Mirrored Environments**: Maintain three virtual machines (VMs) on Phoenix that mimic the hosted Rumple server (rumpledev for dynamic development, rumpletest for stable testing, rumpleprod for production mirroring). This enables local iteration without risking the live site.
- **Integration and Automation**: Use web services/APIs for Phoenix-Rumple communication, with tools like n8n for workflows. Centralized management via Portainer ensures efficient orchestration.
- **Security and Scalability**: Prioritize open-source tools, free tiers (e.g., Cloudflare), and monitoring for secure, low-maintenance operations. Start small for low traffic (few dozen users) with easy scaling paths.
- **Focus Areas**: LLM chat interfaces, document serving, video streaming, and workflow management via subdomains, all powered by AI integrations.

This approach supports learning, building, and showcasing AI tech while keeping operations lean and cost-effective (~$10-30/month for Rumple hosting).

## Architecture Overview
The architecture is a hybrid setup:
- **Backend (Phoenix)**: High-performance server with GPUs for AI compute. Hosts LXC containers (e.g., for Portainer, GPU services) and VMs (rumpleprod/test/dev). Exposes AI capabilities via APIs/WebSockets.
- **Frontend (Rumple)**: Externally hosted Ubuntu server running Docker containers for web services. Handles user interactions, routing via subdomains, and calls to Phoenix for heavy tasks.
- **Mirrored Environments**: Three Phoenix VMs replicate Rumple's setup, allowing isolated dev/test/prod workflows.
- **Management Layer**: Portainer in a dedicated LXC on Phoenix provides a unified UI/API for Docker management across all four environments.
- **Data Flow**: User requests hit Rumple (via Cloudflare for security/CDN), which proxies to internal services or Phoenix APIs. Workflows (n8n) automate tasks like AI processing.
- **Key Principles**: 100% Docker-based on Rumple/environments; open-source/free tools; industry standards (e.g., PostgreSQL, Nginx); low-volume optimization.

High-level diagram (text-based):
```
[User] --> [Cloudflare (DNS/WAF/CDN)] --> [Rumple (Hosted Web Server: Docker Stack)]
           |
           +--> Subdomains: chat (LLM), docs (Documents), video (Streaming), workflows (n8n)
           |
           +--> API Calls --> [Phoenix (GPU Server: LXC/VMs)]
                                |
                                +--> Portainer LXC: Manages All Docker Envs
                                +--> rumpleprod/test/dev VMs: Mirror Rumple
                                +--> GPU Services: LLM Inference, AI Tasks
```

## Summary
- **Hardware/Hosting**: Phoenix (local, 2x RTX 5060Ti GPUs) for backend; Rumple (hosted VPS, e.g., DigitalOcean/Linode) for frontend.
- **Environments**: 1 hosted (Rumple) + 3 VMs (mirrors) = 4 Docker-based Ubuntu 24.04 setups.
- **Core Tools**: Docker for orchestration; Portainer for management; Nginx/Cloudflare for serving; PostgreSQL/Redis for data; n8n for workflows; VLLM for LLM inference.
- **Benefits**: Easy replication, secure integrations, efficient AI offloading, monitoring via Prometheus/Grafana.
- **Assumptions**: Low traffic; focus on OSS/free solutions; no initial need for clustering (e.g., Swarm).

## Detailed Requirements

### 1. Phoenix Server Setup
Phoenix is the central hub for AI-heavy tasks and local environments.
- **Hardware Specifications**:
  - CPUs: Sufficient cores to support multiple VMs/LXCs (e.g., 8+ cores recommended).
  - GPUs: 2x NVIDIA RTX 5060Ti (for LLM inference, model training; ~8-16 GB VRAM per card).
  - RAM: 32+ GB (allocate ~4-8 GB per VM + overhead for LXCs/GPU tasks).
  - Storage: NVMe SSD (500+ GB) for VMs, containers, and data.
- **Hypervisor/OS**: Use Proxmox VE, LXD, or KVM for managing VMs/LXCs on Ubuntu/Debian base.
- **LXC Containers**:
  - Dedicated LXC for Portainer (see Section 5).
  - Additional LXCs for GPU services: e.g., one for FastAPI/LLM inference (expose APIs like `/inference` on port 8000).
  - Resource Allocation: Minimal for LXCs (1-2 vCPU, 1-4 GB RAM, 10-50 GB storage each).
  - GPU Passthrough: Configure to assign GPUs to specific LXCs/VMs (e.g., via Proxmox PCI passthrough for NVIDIA drivers).
- **VMs for Mirrored Environments**:
  - rumpledev: Dynamic dev env (2-4 vCPU, 4-8 GB RAM, 50-100 GB NVMe).
  - rumpletest: Stable testing (same specs).
  - rumpleprod: Prod mirror (same specs).
  - OS: Ubuntu 24.04 LTS per VM.
  - Install Docker on each: `curl -fsSL https://get.docker.com | sh`.
  - Networking: Internal bridge for Phoenix-local access; expose APIs securely.
- **AI Integrations**:
  - Run GPU-accelerated services in LXCs (e.g., Python/FastAPI with Hugging Face Transformers for LLMs).
  - Expose via REST APIs or WebSockets (e.g., `ws://phoenix:8000/chat` for real-time LLM).
  - Handle intensive tasks: Model training, inference, video processing.

### 2. Rumple Hosted Server Setup
Rumple is the public-facing web server.
- **Hosting Provider**: DigitalOcean, Linode, Hetzner, or Vultr for reliability (global data centers, backups).
- **Specifications** (Low-Volume Optimized):
  - CPU: 2-4 vCPUs (2.5GHz+).
  - RAM: 4-8 GB.
  - Storage: 50-100 GB NVMe SSD.
  - Bandwidth: 1-2 TB/month, 100-200 Mbps uplink.
  - OS: Ubuntu 24.04 LTS.
  - Other: IPv4/IPv6, root access, snapshots/backups.
- **Docker Installation**: Standard setup; use Docker Compose for stack management.
- **Networking/Security**: No public ports except via Cloudflare Tunnel; HTTPS via Let's Encrypt.

### 3. Docker Stack Configuration
All four environments (Rumple + mirrors) are 100% Docker-based. Use Docker Compose for deployment.
- **Core Principles**:
  - Modularity: One service per container.
  - Persistence: Named volumes for data (e.g., DBs, documents).
  - Networking: Internal Docker network; expose only Nginx/Cloudflare.
  - Environment Variables: For secrets/config (e.g., API keys, Phoenix endpoints).
- **Recommended Services/Containers**:
  | Category | Service | Docker Image | Purpose | Configuration Notes |
  |----------|---------|--------------|---------|---------------------|
  | Web Proxy | Nginx | `nginx:latest` | Reverse proxy for subdomains, static files, HTTPS. | Config: `/etc/nginx/nginx.conf` volume; routes to services (e.g., chat -> Open WebUI). |
  | LLM Chat | Open WebUI | `ghcr.io/open-webui/open-webui:main` | AI chat interface; calls Phoenix APIs. | Env: Phoenix API endpoint; subdomain `chat.example.com`. |
  | Workflows | n8n | `n8nio/n8n:latest` | Automation (e.g., AI pipelines, integrations). | Port 5678; integrate with Phoenix APIs; subdomain `workflows.example.com`. |
  | Database | PostgreSQL | `postgres:latest` | Data storage (chat history, workflows). | Env: Password; volume `pgdata`; optional pgAdmin (`dpage/pgadmin4`). |
  | Caching | Redis | `redis:latest` | Session caching, queues. | Minimal config; used by n8n/Open WebUI. |
  | Monitoring | Prometheus | `prom/prometheus:latest` | Metrics collection. | Config for Docker/host scraping. |
  | Monitoring | Grafana | `grafana/grafana:latest` | Dashboards/visualization. | Data source: Prometheus; subdomain `monitoring.example.com`. |
  | Security/CDN | Cloudflare Tunnel | `cloudflare/cloudflared:latest` | Secure exposure without open ports. | Sidecar; tunnel to Nginx; zero-trust auth. |
  | Video Streaming | Nginx-RTMP | `alfg/nginx-rtmp:latest` | Low-volume video streams. | Integrate with Phoenix for AI-generated content; subdomain `video.example.com`. |
  | Documents | Nextcloud or Paperless-ngx | `nextcloud:latest` or `ghcr.io/paperless-ngx/paperless-ngx:latest` | File serving/OCR. | Volume for files; AI integration via Phoenix; subdomain `docs.example.com`. |
  | Management (Optional) | Portainer Agent | `portainer/agent:latest` | Remote management hook. | For Rumple; TLS-secured Docker API. |
- **Example Docker Compose (`docker-compose.yml`)**:
  ```yaml
  version: '3.8'
  services:
    nginx:
      image: nginx:latest
      ports:
        - "80:80"
        - "443:443"
      volumes:
        - ./nginx.conf:/etc/nginx/nginx.conf
    open-webui:
      image: ghcr.io/open-webui/open-webui:main
      environment:
        - OPENAI_API_BASE=http://phoenix:8000/v1  # Example Phoenix integration
    postgres:
      image: postgres:latest
      environment:
        POSTGRES_PASSWORD: securepassword
      volumes:
        - pgdata:/var/lib/postgresql/data
    n8n:
      image: n8nio/n8n:latest
      ports:
        - "5678:5678"
    redis:
      image: redis:latest
    prometheus:
      image: prom/prometheus:latest
      volumes:
        - ./prometheus.yml:/etc/prometheus/prometheus.yml
    grafana:
      image: grafana/grafana:latest
      ports:
        - "3000:3000"
    cloudflared:
      image: cloudflare/cloudflared:latest
      command: tunnel --url http://nginx:80
  volumes:
    pgdata:
  ```
  - Deployment: `docker compose up -d`; version via Git for CI/CD.

### 4. Integrations and Workflows
- **Phoenix-Rumple Communication**: REST APIs (e.g., FastAPI on Phoenix) for AI tasks; secure with API keys or OAuth.
- **Subdomains**: Managed via Cloudflare DNS + Nginx proxy (e.g., `chat.thinkheadsai.com` -> Open WebUI).
- **n8n Workflows**: Automate e.g., document OCR via Phoenix, video generation, chat escalations.
- **Data Persistence**: Backups via provider snapshots or Docker volumes to S3 (add MinIO if needed: `minio/minio:latest`).

### 5. Portainer Management
Portainer centralizes control in a dedicated LXC on Phoenix.
- **LXC Setup**: Ubuntu 24.04; 1 vCPU, 1-2 GB RAM, 10 GB storage; install Docker.
- **Installation**:
  ```bash
  docker volume create portainer_data
  docker run -d -p 9000:9000 --name portainer --restart always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest
  ```
- **Environment Connections**:
  - Local: Add Phoenix VMs via socket.
  - Remote: Add Rumple via agent (`portainer/agent:latest` on Rumple; TLS TCP).
- **Features Utilization**:
  - Stacks: Deploy Compose files across envs.
  - Monitoring: Container stats, logs.
  - API: For n8n automation (e.g., `/api/endpoints`).
  - Security: Behind Cloudflare Tunnel; subdomain access.
- **GPU Management**: If passed through, monitor GPU containers.

### 6. Security, Monitoring, and Maintenance
- **Security**: Cloudflare WAF/DDoS; Let's Encrypt HTTPS; env vars for secrets; minimal exposed ports.
- **Monitoring**: Prometheus scrapes metrics; Grafana dashboards; alerts for high usage.
- **Backups**: Daily volumes snapshots; sync to external storage.
- **Scalability**: Add Swarm via Portainer if needed; monitor Phoenix GPUs to avoid contention.
- **Costs**: Rumple ~$10-30/month; Phoenix local (power/hardware costs).

This document provides a comprehensive blueprint. Update as your setup evolves.