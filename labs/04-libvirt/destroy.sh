#!/bin/bash
# Stop the libvirt guest and delete it, disk included.
export LIBVIRT_DEFAULT_URI=qemu:///system
virsh destroy lab-libvirt 2>/dev/null
virsh undefine lab-libvirt --remove-all-storage
