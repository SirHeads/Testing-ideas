# QEMU Guest Agent Initialization Issue

## Summary

During the execution of the `phoenix` CLI End-to-End System Test Plan, it was discovered that the QEMU guest agent is not starting automatically on VM creation. This causes the `vm-manager.sh` script to time out while waiting for the guest agent to become responsive.

## Details

The `user-data.template.yml` file includes a `runcmd` section that is supposed to reinstall and enable the guest agent, but this is not being executed correctly. Attempts to explicitly start the guest agent in the `bootcmd` and `runcmd` sections of the cloud-init configuration have been unsuccessful.

## Workaround

The current workaround is to manually start the QEMU guest agent after the VM has been created. This can be done by logging into the VM and running the command `sudo systemctl start qemu-guest-agent`.

## Recommendation

It is recommended that a separate task be created to investigate and resolve this issue. The investigation should focus on the cloud-init process and the execution of the `runcmd` and `bootcmd` sections.