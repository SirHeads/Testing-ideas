#!/bin/bash

# File: hypervisor_feature_fix_apparmor_tunables.sh
# Description: This script performs a declarative fix for the AppArmor 'home' tunable file.
#              It directly overwrites `/etc/apparmor.d/tunables/home` with a known-good configuration.
#              This is a critical remediation step to resolve potential AppArmor profile loading failures,
#              specifically the `TOK_EQUALS` error that can occur if this file is misconfigured (e.g., missing '@' symbols).
#              By ensuring the tunables are correctly defined, this script guarantees that AppArmor can properly
#              interpret path aliases like `@{HOME}` within security profiles.
#
# Dependencies:
#   - A running system with AppArmor installed.
#
# Inputs:
#   - None. The script is not configuration-driven and applies a static fix.
#
# Outputs:
#   - Overwrites the `/etc/apparmor.d/tunables/home` file.
#   - Exit Code: 0 on success.

# Overwrite the tunables file with the correct home directory settings.
# The `cat <<EOF` construct allows for a clean, multi-line write to the target file.
# This is an idempotent operation; running the script multiple times will result in the same file content.
cat <<EOF > /etc/apparmor.d/tunables/home
# This tunable defines the locations that AppArmor considers to be user home directories.
# It is crucial for profiles that use the @{HOME} alias to grant access to user-specific files.
@{HOME}=/home/*/ /root/

# This tunable defines the parent directory for home directories.
@{HOMEDIRS}=/home/
EOF