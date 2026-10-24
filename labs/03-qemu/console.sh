#!/bin/bash
# Attach to the guest's serial console. Detach with Ctrl-].
# CirrOS login: cirros / gocubsgo
exec socat -,raw,echo=0,escape=0x1d unix-connect:"$HOME/qemu-lab/console.sock"
