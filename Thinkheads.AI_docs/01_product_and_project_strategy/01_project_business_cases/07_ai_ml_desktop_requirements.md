---
title: 'AI/ML Desktop Environment: Project Requirements'
summary: This document details the hardware, software, and configuration requirements for the AI/ML Desktop Environment project.
document_type: Business Case
status: Approved
version: '2.0'
author: Roo
owner: Thinkheads.AI
tags:
  - ai_ml
  - desktop_environment
  - requirements
review_cadence: Annual
last_reviewed: '2025-09-23'
---
This document outlines the requirements and setup for creating a functional Linux desktop environment inside an LXC container on Proxmox 9, optimized for AI/ML workloads, learning, and remote access via RustDesk. The setup leverages two NVIDIA 5060 Ti 16GB GPUs for acceleration, uses lightweight components for efficiency, and integrates with Proxmox tools. LXC containers are preferred over VMs for lower overhead while sharing the host kernel. Key goals: Isolation, GPU passthrough, smooth remote desktop performance, and scalability for multiple containers.

High-level benefits:
- Efficient resource use for AI/ML (e.g., CUDA/TensorFlow).
- Remote access via self-hosted RustDesk.
- Easy snapshots/backups in Proxmox.
- Based on community success stories from Proxmox forums, Reddit (r/Proxmox, r/homelab), and NVIDIA guides.

Assumptions: Proxmox 9 host with NVIDIA drivers installed, familiarity with `/dev/` passthrough, and a self-hosted RustDesk server on a separate web server/container.

## Hardware and Software Prerequisites
- **Host Hardware**: Proxmox 9 on a system with 2x NVIDIA 5060 Ti 16GB GPUs, sufficient CPU (e.g., 16+ cores), RAM (64GB+), and fast storage (NVMe/SSD).
- **Software**:
  - Proxmox templates: Ubuntu 24.04 or Debian 12.
  - NVIDIA drivers: Latest stable series (e.g., 560 series or newer) on host; install with `apt install nvidia-driver`.
  - LXC container: Unprivileged preferred for security; privileged for initial testing.
  - Desktop Environment: XFCE or MATE (lightweight).
  - Remote Access: RustDesk (latest version, e.g., 1.2.3+).
  - AI/ML Tools: CUDA, TensorFlow/PyTorch, Jupyter.
- **Network**: Bridge setup (vmbr0) for low-latency; ports 21115-21117 for RustDesk.

## High-Level Setup Steps
1. **Create LXC Container**: Use Proxmox template (e.g., Ubuntu 24.04).
2. **Install Desktop**: Add XFCE and LightDM.
3. **GPU Passthrough**: Map NVIDIA devices for acceleration.
4. **Install RustDesk**: Client in container, connect to self-hosted server.
5. **Optimize for AI/ML**: Install ML libraries, bind-mount datasets.
6. **Performance Tuning**: Enable NVENC, QoS, and resource limits.
7. **Testing**: Verify GUI, GPU, and remote access.

## Detailed Configuration
### Container Creation
- Download template: `pveam update && pveam download local ubuntu-24.04-standard_24.04-1_amd64.tar.gz`.
- Create via CLI: `pct create 100 /var/lib/vz/template/cache/ubuntu-24.04-standard_24.04-1_amd64.tar.gz --hostname ai-desktop --cores 4 --memory 16384 --storage local-lvm`.
- Start: `pct start 100`.
- Access: `pct console 100` or SSH.

### Desktop Environment Installation
- Update: `apt update`.
- Install XFCE: `apt install -y xfce4 xfce4-goodies --no-install-recommends`.
- Display Manager: `apt install -y lightdm`.
- Reboot: `pct reboot 100`.
- Alternatives: MATE for similar lightness (`apt install mate-desktop-environment`).

### GPU Passthrough
- Host Prep: Verify `nvidia-smi`.
- Edit `/etc/pve/lxc/100.conf`:
  ```
  lxc.cgroup2.devices.allow: c 195:* rwm
  lxc.cgroup2.devices.allow: c 510:* rwm
  lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,create=file
  lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,create=file
  lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,create=file
  lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,create=file
  ```
- In Container: `apt install -y nvidia-driver nvidia-cuda-toolkit`.
- Test: `nvidia-smi`; Python check: `python3 -c "import torch; print(torch.cuda.is_available())"`.
- Multi-GPU: Repeat for second GPU; use NVIDIA MPS for sharing (`nvidia-cuda-mps-control -d`).

### RustDesk Setup
- Install Client: 
  ```bash
  wget https://github.com/rustdesk/rustdesk/releases/download/1.2.3/rustdesk-1.2.3-x86_64.deb
  dpkg -i rustdesk-1.2.3-x86_64.deb
  apt install -f
  ```
- Configure: Point to self-hosted server IP/port; enable GPU acceleration in Settings > General.
- Server Optimization: On web server container, use recent version; config `hbbs.toml` with `bind_addr = "0.0.0.0"`.
- Ports: Open 21115-21117; use NGINX reverse proxy with HTTP/2 for external access.

### AI/ML Integration
- Install Tools: `pip install tensorflow pytorch jupyter` (CUDA versions).
- Datasets: Bind-mount in config: `lxc.mount.entry: /path/to/datasets mnt/datasets none bind,create=dir`.
- Docker Support: `apt install docker.io`; add NVIDIA Container Toolkit for GPU in Docker.

### Performance Optimizations
- **Resources**: Set 4-8 cores, 8-16GB RAM; use NVMe for storage.
- **RustDesk Tuning**: Settings > Video Codec: H.264/H.265 (NVENC); Quality: Speed/Balanced; Enable GPU decoding.
- **Network**: Bridge in config: `lxc.net.0.type: veth lxc.net.0.link: vmbr0`.
- **QoS**: Host: `tc qdisc add dev vmbr0 root tbf rate 500mbit latency 50ms burst 1540`.
- **Desktop Tweaks**: Disable XFCE compositing (Window Manager Tweaks).
- **Monitoring**: `htop`, `nvidia-smi`; logs in `~/.rustdesk` and `journalctl -u lightdm`.

## Deep Specifications
### Advanced LXC Config Example (/etc/pve/lxc/100.conf)
```
arch: amd64
cores: 8
hostname: ai-desktop
memory: 16384
net0: name=eth0,bridge=vmbr0,gw=192.168.1.1,ip=192.168.1.100/24,type=veth
ostype: ubuntu
rootfs: local-lvm:vm-100-disk-0,size=50G
swap: 2048
lxc.privileged: 0  # Unprivileged for production
lxc.cgroup2.devices.allow: c 195:* rwm  # NVIDIA major
lxc.cgroup2.devices.allow: c 510:* rwm  # Additional NVIDIA
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,create=file
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir  # For rendering
lxc.mount.entry: /path/to/datasets mnt/datasets none bind,create=dir
```

### Troubleshooting Deep Dive
- GUI Issues: Check `~/.xsession-errors`; ensure LightDM service: `systemctl enable lightdm`.
- GPU Conflicts: Use MPS for multi-process; verify devices with `ls -l /dev/nvidia*`.
- RustDesk Latency: Test with `iperf`; disable UDP if jittery, fall back to TCP.
- ML Performance: For large models, allocate more VRAM; use `nvidia-smi -q -d UTILIZATION` to monitor.

### Success Stories Summary
- Proxmox Forums: XFCE + xrdp in LXC for remote work, adapted to RustDesk.
- Reddit r/homelab: NVIDIA passthrough in LXC for Frigate/ML, <50ms latency with RustDesk.
- NVIDIA Docs: Multi-GPU sharing in containers for AI workloads.

This setup ensures top-end performance for your use case. For updates, reference Proxmox/NVIDIA/RustDesk official docs.
