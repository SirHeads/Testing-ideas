#!/bin/bash
set -e
if dmesg | grep "apparmor=\"DENIED\"" | grep "lxc-902"; then
    echo "AppArmor denials detected for container 902."
    exit 1
fi
echo "No AppArmor denials detected for container 902."
exit 0