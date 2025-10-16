# Phoenix Hypervisor Guest and Container Summary

This document provides a comprehensive summary of all LXC containers, virtual machines (VMs), and Docker containers defined within the Phoenix Hypervisor ecosystem.

## 1. LXC Containers

| CTID | Name | Purpose | Cores | Memory | Storage | IP Address | Features |
|---|---|---|---|---|---|---|---|
| 101 | Nginx-Phoenix | External-facing Nginx reverse proxy and API gateway. | 4 | 4096 MB | 32 GB | 10.0.0.153 | base_setup, dns_server, trusted_ca |
| 102 | Traefik-Internal | Internal service mesh and reverse proxy. | 2 | 2048 MB | 16 GB | 10.0.0.12 | base_setup, traefik, trusted_ca |
| 103 | Step-CA | Internal certificate authority. | 2 | 1024 MB | 16 GB | 10.0.0.10 | base_setup, step_ca |
| 801 | granite-embedding | vLLM container for Granite embedding models. | 6 | 72000 MB | 128 GB | 10.0.0.141 | vllm |
| 802 | granite-3.3-8b-fp8 | vLLM container for Granite 3.3B models. | 6 | 72000 MB | 128 GB | 10.0.0.142 | vllm |
| 900 | Copy-Base | Base template for creating new containers. | 2 | 2048 MB | 16 GB | 10.0.0.200 | base_setup |
| 901 | Copy-Cuda12.8 | Template with NVIDIA drivers and CUDA 12.8. | 2 | 2048 MB | 16 GB | 10.0.0.201 | nvidia |
| 905 | NAT-Gateway-Template | Template for creating a NAT gateway. | 1 | 1024 MB | 8 GB | 10.0.0.205 | base_setup, nat_gateway |
| 910 | Copy-VLLM-GPUx2 | vLLM container with two GPUs. | 10 | 72000 MB | 128 GB | 10.0.0.220 | nvidia, vllm |
| 911 | Copy-VLLM-GPU0 | vLLM container with a single GPU. | 10 | 72000 MB | 64 GB | 10.0.0.221 | nvidia, vllm |
| 912 | Copy-VLLM-GPU1 | vLLM container with a single GPU. | 10 | 72000 MB | 64 GB | 10.0.0.222 | nvidia, vllm |
| 914 | ollama-gpu0 | Ollama container with a single GPU. | 6 | 32768 MB | 128 GB | 10.0.0.155 | nvidia, ollama |
| 917 | llamacpp-gpu0 | Llama.cpp container with a single GPU. | 6 | 32768 MB | 128 GB | 10.0.0.157 | nvidia |

## 2. Virtual Machines

| VMID | Name | Purpose | Cores | Memory | Storage | IP Address | Features |
|---|---|---|---|---|---|---|---|
| 9000 | ubuntu-2404-cloud-template | Base template for creating new VMs. | 2 | 4096 MB | 50 GB | DHCP | |
| 1001 | Portainer | Portainer server for managing Docker environments. | 4 | 8192 MB | 32 GB | 10.0.0.101 | base_setup, docker, trusted_ca |
| 1002 | agent | Portainer agent for managing Docker environments. | 4 | 4096 MB | 64 GB | 10.0.0.102 | base_setup, docker, trusted_ca |

## 3. Docker Containers

| Stack Name | Description | Environment |
|---|---|---|
| qdrant_service | Qdrant vector database for RAG. | production |
| thinkheads_ai_app | The main Thinkheads.AI web application. | development |
