---
title: "Phoenix Hypervisor: Docker-in-LXC Startup Failure Mitigation Plan"
summary: "A plan to diagnose and resolve the persistent startup failure of Docker-enabled LXC containers, specifically the `Template-Docker` container (CTID 902)."
document_type: "Mitigation Plan"
status: "Draft"
version: "1.0.0"
author: "Roo"
owner: "Technology Team"
tags:
  - "Phoenix Hypervisor"
  - "Docker"
  - "LXC"
  - "Mitigation"
  - "fuse"
review_cadence: "Ad-hoc"
---

## 1. Executive Summary

This document outlines a plan to address the critical startup failure of Docker-enabled LXC containers, which is currently blocking the testing of the `portainer` feature and other Docker-dependent services. The issue manifests as a failure to mount the `/dev/fuse` device inside the container, even when the device is present on the host and the container configuration appears correct.

This plan proposes a temporary workaround to allow the Stage 6 test plan to proceed, while also defining a clear path for a full investigation and permanent resolution of the underlying issue.

## 2. Issue Description

When attempting to start the `Template-Docker` container (CTID 902), the `pct start` command fails with the following error:

```
safe_mount: 1334 No such device - Failed to mount "/dev/fuse" onto "/usr/lib/x86_64-linux-gnu/lxc/rootfs/"
mount_entry: 2202 No such device - Failed to mount "/dev/fuse" on "/usr/lib/x86_64-linux-gnu/lxc/rootfs/"
lxc_setup: 3908 Failed to setup mount entries
do_start: 1273 Failed to setup container "902"
```

This failure occurs despite the following conditions being met:
- The `/dev/fuse` device exists on the Proxmox host.
- The `fuse` kernel module is loaded on the host.
- The container's configuration includes the necessary `lxc.mount.entry` and `pct_options`.

The failure of this template container prevents the creation and testing of any container that depends on it, such as the `test-portainer` container (CTID 105).

## 3. Immediate Mitigation (Workaround)

**Objective:** Allow the Stage 6 End-to-End System Test Plan to proceed by avoiding the problematic `docker` feature.

*   **Task 1: Skip Docker-Dependent Tests**
    *   **Action:** The `portainer` feature test will be skipped. Any other feature tests that depend on a Docker environment will also be skipped.
    *   **Reasoning:** This allows the test plan to continue and validate the remaining, non-Docker-related features.

*   **Task 2: Proceed with Remaining Tests**
    *   **Action:** Continue with the test plan, starting with the `python_api_service` feature.
    *   **Reasoning:** This maximizes the productivity of the current testing cycle while the Docker issue is investigated separately.

## 4. Long-Term Resolution (Investigation)

**Objective:** Identify the root cause of the `/dev/fuse` mount failure and implement a permanent, reliable solution.

*   **Task 1: In-Depth Investigation**
    *   **Action:** A separate, dedicated debugging session will be initiated to investigate the `/dev/fuse` mount issue.
    *   **Areas of Investigation:**
        - AppArmor profile interactions, even when set to `unconfined`.
        - Proxmox-specific LXC security features.
        - Kernel-level permissions and cgroup configurations.
        - Comparison with a working Docker-in-LXC setup on a different Proxmox environment.

*   **Task 2: Implement and Test Fix**
    *   **Action:** Based on the findings of the investigation, a permanent fix will be implemented and thoroughly tested.
    *   **Validation:** The fix will be validated by successfully creating and starting the `Template-Docker` container (CTID 902) and running a series of Docker-specific tests.

## 5. Conclusion

This plan provides a clear, two-pronged approach to the Docker-in-LXC startup failure. By implementing the immediate mitigation, we can unblock the current test plan and continue to make progress. The long-term resolution will ensure that this critical issue is addressed in a thorough and sustainable manner.