# APT Installation Hang Fix Plan

## 1. Summary of the Problem

The `phoenix create 900` command is hanging during the `base_setup` feature installation. This is caused by the `apt-get install` command waiting for user input, which is not possible in a non-interactive script. This is a critical flaw that prevents the creation of any new containers.

## 2. Proposed Solution

To resolve this, I will implement a two-part solution to ensure all `apt` operations are non-interactive and resilient to failure.

### 2.1. Force Non-Interactive APT in `base_setup`

I will modify the `phoenix_hypervisor_feature_install_base_setup.sh` script to set the `DEBIAN_FRONTEND=noninteractive` environment variable. This is the standard method for preventing `apt` from displaying interactive prompts.

**File:** `usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_base_setup.sh`

**Change:**

```diff
--- a/usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_base_setup.sh
+++ b/usr/local/phoenix_hypervisor/bin/lxc_setup/phoenix_hypervisor_feature_install_base_setup.sh
@@ -105,8 +105,10 @@
  
      if [ ${#packages_to_install[@]} -gt 0 ]; then
          log_info "Missing packages: ${packages_to_install[*]}. Installing..."
-         pct_exec "$CTID" apt-get update
-         pct_exec "$CTID" apt-get install -y "${packages_to_install[@]}"
+        pct_exec "$CTID" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get update"
+        pct_exec "$CTID" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y ${packages_to_install[*]}"
      else
          log_info "All essential packages are already installed."
      fi
```

### 2.2. Add Precautionary Lock File Cleanup in `lxc-manager.sh`

As a safeguard against unclean shutdowns of `apt`, I will add a step to the `lxc-manager.sh` script to remove any stale lock files before the `apply_features` function is called.

**File:** `usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh`

**Change:**

```diff
--- a/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
+++ b/usr/local/phoenix_hypervisor/bin/managers/lxc-manager.sh
@@ -1494,6 +1494,10 @@
                      create_pre_configured_snapshot "$ctid"
                  fi
  
+                # Precautionary cleanup of apt lock files
+                log_info "Running precautionary cleanup of apt lock files for CTID $ctid..."
+                pct_exec "$ctid" -- bash -c "rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*"
+
                  apply_features "$ctid"
                  
                  run_application_script "$ctid"
```

## 3. Next Steps

Please review this plan. If you approve, I will switch to `code` mode to implement these changes.