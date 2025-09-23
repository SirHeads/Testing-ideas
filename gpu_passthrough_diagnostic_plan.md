# GPU Passthrough Failure Diagnostic Plan for CTID 901

## 1. Objective

This document outlines the diagnostic procedure to identify the root cause of the GPU passthrough failure for container 901. The `/dev/nvidia0` device is not appearing inside the container, indicating a potential issue at the Proxmox hypervisor level.

## 2. Diagnostic Procedure

The following commands must be executed on the **Proxmox host** by a Debug specialist. All command outputs must be captured and included in the final report.

### 2.1. Verify Final Container Configuration

After the passthrough script has been executed, inspect the final container configuration to ensure the settings have been correctly written and persisted.

```bash
# Command to be executed:
cat /etc/pve/lxc/901.conf
```

### 2.2. Check Host dmesg for Errors

Immediately after attempting to start the container, check the host's kernel log for any errors related to IOMMU, VFIO, or NVIDIA drivers.

```bash
# Command to be executed:
dmesg | grep -i -e "vfio" -e "iommu" -e "nvidia" -e "dmar"
```

### 2.3. Verify Kernel Modules

Ensure that all necessary VFIO kernel modules are loaded on the Proxmox host.

```bash
# Command to be executed:
lsmod | grep vfio
```
**Expected Output:** The output should include `vfio_pci`, `vfio_iommu_type1`, and `vfio`.

### 2.4. Check IOMMU Status

Verify that IOMMU is enabled and functioning correctly on the Proxmox host.

```bash
# Command to be executed:
dmesg | grep -e DMAR -e IOMMU
```
**Expected Output:** You should see messages indicating that DMAR and IOMMU are enabled and initialized.

### 2.5. Check Host GPU Driver Binding

Verify that the NVIDIA GPU on the host is correctly bound to the `vfio-pci` driver, which is necessary for passthrough.

```bash
# Command to be executed:
lspci -k
```
**Expected Output:** Look for the NVIDIA GPU device and confirm that the "Kernel driver in use" is `vfio-pci`.

## 3. Final Report Structure

The Debug specialist will compile a final report containing the complete, unaltered output of each command executed. The report should be structured as follows:

```markdown
# GPU Passthrough Diagnostic Report: CTID 901

## 1. Final Container Configuration (`/etc/pve/lxc/901.conf`)

<Paste output of `cat /etc/pve/lxc/901.conf` here>

## 2. Host dmesg Logs

<Paste output of `dmesg | grep ...` here>

## 3. Kernel Modules (`lsmod | grep vfio`)

<Paste output of `lsmod | grep vfio` here>

## 4. IOMMU Status (`dmesg | grep -e DMAR -e IOMMU`)

<Paste output of `dmesg | grep ...` here>

## 5. Host GPU Driver Binding (`lspci -k`)

<Paste output of `lspci -k` here>

## 6. Summary of Findings

<A brief summary of the findings based on the command outputs.>