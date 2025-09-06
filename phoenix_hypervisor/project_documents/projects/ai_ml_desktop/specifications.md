---
title: "Technical Specifications for AI/ML Desktop Environment"
tags: ["AI/ML", "Desktop Environment", "LXC", "Proxmox", "Technical Specifications", "GPU Passthrough", "NVIDIA", "XFCE", "RustDesk", "CUDA", "TensorFlow", "PyTorch", "Jupyter"]
summary: "This document provides detailed technical specifications for the setup and configuration of the AI/ML Desktop Environment, including LXC container configuration, GPU passthrough settings, software installation commands, and performance optimizations."
version: "1.0.0"
author: "Phoenix Hypervisor Team"
---

This document provides detailed technical specifications for the setup and configuration of the AI/ML Desktop Environment.

## LXC Container Configuration
- **Template:** Ubuntu 24.04 Standard
- **Hostname:** `ai-desktop`
- **Cores:** 8
- **Memory:** 16384 MB
- **Root Filesystem:** 50G on `local-lvm`
- **Swap:** 2048 MB
- **Privileged:** No (unprivileged)
- **Network:** Static IP on `vmbr0` (e.g., 192.168.1.100/24)

## GPU Passthrough
The following lines must be added to the LXC configuration file (e.g., `/etc/pve/lxc/100.conf`):
```
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 510:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,create=file
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
```

## Software Installation
- **Desktop Environment:**
  ```bash
  apt update
  apt install -y xfce4 xfce4-goodies lightdm --no-install-recommends
  ```
- **NVIDIA Drivers (in container):**
  ```bash
  apt install -y nvidia-driver nvidia-cuda-toolkit
  ```
- **RustDesk Client:**
  ```bash
  wget https://github.com/rustdesk/rustdesk/releases/download/1.2.3/rustdesk-1.2.3-x86_64.deb
  dpkg -i rustdesk-1.2.3-x86_64.deb
  apt install -f
  ```
- **AI/ML Stack:**
  ```bash
  pip install tensorflow pytorch jupyter
  ```

## Performance Optimizations
- **RustDesk:** Enable H.264/H.265 (NVENC) video codec and GPU decoding in the client settings.
- **XFCE:** Disable compositing in Window Manager Tweaks.
- **QoS:** Implement traffic shaping on the host's network bridge to prioritize remote desktop traffic.