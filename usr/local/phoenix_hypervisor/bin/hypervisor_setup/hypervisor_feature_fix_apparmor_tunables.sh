#!/bin/bash
#
# This script ensures the AppArmor tunables for home directories are correctly configured.
# It overwrites the /etc/apparmor.d/tunables/home file with the required settings
# to prevent profile loading issues due to misconfigured paths.

# Overwrite the tunables file with the correct home directory settings
cat <<EOF > /etc/apparmor.d/tunables/home
@{HOME}=/home/*/ /root/
@{HOMEDIRS}=/home/
EOF