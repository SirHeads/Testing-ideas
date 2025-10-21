# VM Template Creation Remediation Plan

## 1. Executive Summary

The `phoenix create 9000` command is failing due to a network deadlock during the `cloud-init` process in new VMs. The root cause is the absence of the `qemu-guest-agent` in the base cloud image, which prevents the hypervisor from configuring the network. Without a network, the VM cannot download the agent, leading to a timeout.

This plan outlines the necessary changes to the `vm-manager.sh` script to inject the guest agent *before* the VM is created, ensuring reliable network initialization and resolving the issue.

## 2. Analysis of the Root Cause

The core of the problem lies in the `create_vm_from_image` function within `usr/local/phoenix_hypervisor/bin/managers/vm-manager.sh`. The current implementation downloads a fresh Ubuntu cloud image and immediately creates a VM from it.

The orchestration logic correctly waits for the guest agent to become responsive before proceeding with network configuration. However, the agent is not present in the base image and is scheduled to be installed by `cloud-init`. This creates a classic deadlock:

1.  **Orchestrator:** "I need the guest agent to be running before I can configure the network."
2.  **Cloud-Init:** "I need a network connection before I can download and install the guest agent."

This deadlock causes the `wait_for_guest_agent` function to time out, leading to the failure of the entire VM creation process.

## 3. Proposed Solution

The solution is to modify the `create_vm_from_image` function to mirror the logic found in the older `provision_cloud_template.sh` script. This involves two key additions:

1.  **Dependency Check:** Ensure the `libguestfs-tools` package, which provides the necessary `virt-customize` utility, is installed on the hypervisor.
2.  **Image Customization:** Use `virt-customize` to inject the `qemu-guest-agent` directly into the downloaded cloud image *before* it is used to create the VM.

This ensures the guest agent is available from the very first boot, breaking the deadlock and allowing the network configuration and `cloud-init` process to complete successfully.

## 4. Code Changes for `vm-manager.sh`

The following `diff` shows the exact changes to be applied to `usr/local/phoenix_hypervisor/bin/managers/vm-manager.sh`.

```diff
--- a/usr/local/phoenix_hypervisor/bin/managers/vm-manager.sh
+++ b/usr/local/phoenix_hypervisor/bin/managers/vm-manager.sh
@@ -338,6 +338,22 @@
          log_fatal "Failed to download cloud image."
      fi
 
+     # --- Install Dependencies ---
+     # `libguestfs-tools` is required for `virt-customize`.
+     if ! dpkg -l | grep -q "libguestfs-tools"; then
+         log_info "Installing libguestfs-tools..."
+         apt-get update
+         apt-get install -y libguestfs-tools
+     fi
+
+    # --- Customize Image ---
+    # This is a critical step. `virt-customize` allows us to modify the image offline
+    # before it's ever booted. We inject the `qemu-guest-agent`, which is essential
+    # for the Proxmox host to communicate reliably with the guest VM.
+    log_info "Installing qemu-guest-agent into the cloud image..."
+    if ! virt-customize -a "$download_path" --install qemu-guest-agent --run-command 'systemctl enable qemu-guest-agent'; then
+        log_fatal "Failed to customize cloud image."
+    fi
+
      log_info "Radically simplified VM creation starting..."
      local vm_name
      vm_name=$(jq_get_vm_value "$VMID" ".name")

```

## 5. Next Steps

1.  **Review and Approve:** Please review this plan and the proposed code changes.
2.  **Apply Changes:** Once approved, I will switch to `code` mode to apply the changes to the `vm-manager.sh` script.
3.  **Test:** After the changes are applied, you can re-run the `phoenix create 9000` command to verify the fix.
