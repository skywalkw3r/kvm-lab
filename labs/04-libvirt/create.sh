#!/bin/bash
# Same CirrOS guest as lab 03, but this time libvirt builds and runs QEMU for us.
set -euo pipefail
cd "$(dirname "$0")"
export LIBVIRT_DEFAULT_URI=qemu:///system
NAME=lab-libvirt
POOL=/var/lib/libvirt/images

BASE=$(../lib/fetch-cirros.sh)
# libvirt's QEMU runs as the 'qemu' user, confined by SELinux, so its disks
# belong in libvirt's storage pool directory rather than in ~/images.
sudo install -m 0644 "$BASE" "$POOL/cirros-base.qcow2"
sudo qemu-img create -q -f qcow2 -F qcow2 -b "$POOL/cirros-base.qcow2" "$POOL/$NAME.qcow2"
# The same cloud-init seed as lab 03.
../lib/make-seed.sh /tmp/$NAME-seed.iso "$NAME"
sudo install -m 0644 /tmp/$NAME-seed.iso "$POOL/$NAME-seed.iso" && rm /tmp/$NAME-seed.iso

# virt-install turns these high-level options into domain XML, defines it, and starts it.
virt-install \
  --name "$NAME" \
  --memory 512 --vcpus 2 \
  --cpu host-passthrough \
  --import --disk "$POOL/$NAME.qcow2",bus=virtio \
  --disk "$POOL/$NAME-seed.iso",device=cdrom \
  --network network=default,model=virtio \
  --osinfo linux2022 \
  --graphics none --console pty,target_type=serial \
  --noautoconsole

echo
echo "Running. Next: ./inspect.sh    console: virsh console $NAME (Ctrl-] to leave)    cleanup: ./destroy.sh"
