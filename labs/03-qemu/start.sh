#!/bin/bash
# Boots CirrOS with plain QEMU: no libvirt, no management layer.
# Every flag here is something libvirt (or Proxmox, VDSM, Nova...) will later generate for you.
set -euo pipefail
cd "$(dirname "$0")"
LAB=~/qemu-lab
mkdir -p "$LAB"
BASE=$(../lib/fetch-cirros.sh)

# Copy-on-write overlay: the guest writes to disk.qcow2, the base image stays pristine.
[[ -f $LAB/disk.qcow2 ]] || qemu-img create -q -f qcow2 -F qcow2 -b "$BASE" "$LAB/disk.qcow2"
# cloud-init seed (hostname + a user-data script), so the guest doesn't wait for a metadata server.
../lib/make-seed.sh "$LAB/seed.iso" lab-qemu

# shellcheck disable=SC2054,SC2140  # commas and quotes are QEMU option syntax
args=(
  # debug-threads=on names QEMU's threads ("CPU 0/KVM", ...) so ps and top can show them.
  -name lab-qemu,debug-threads=on
  # Machine: the modern q35 chipset (PCIe), with KVM doing the CPU work.
  -machine q35,accel=kvm
  # -cpu host passes the real CPU model and features through to the guest.
  -cpu host -smp 2 -m 512
  # Disk: a virtio-blk device backed by the qcow2 overlay.
  -drive file="$LAB/disk.qcow2",if=virtio,format=qcow2
  # The cloud-init seed, as a CD-ROM (like Proxmox's cloud-init drive).
  -cdrom "$LAB/seed.iso"
  # Network: user-mode NAT (slirp) + virtio-net; port 2222 here reaches the guest's ssh.
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22
  -device virtio-net-pci,netdev=n0
  # QMP: the JSON control socket. This is exactly what libvirt uses to drive QEMU.
  -qmp unix:"$LAB/qmp.sock",server=on,wait=off
  # Serial console on a socket (attach with ./console.sh), also logged to a file.
  -chardev socket,id=ser0,path="$LAB/console.sock",server=on,wait=off,logfile="$LAB/console.log"
  -serial chardev:ser0
  -display none
  -daemonize -pidfile "$LAB/qemu.pid"
)

printf '%q ' qemu-system-x86_64 "${args[@]}" > "$LAB/cmdline.txt"; echo >> "$LAB/cmdline.txt"
qemu-system-x86_64 "${args[@]}"
echo "QEMU running as pid $(cat "$LAB/qemu.pid"). Console log: $LAB/console.log"
echo "Next: ./console.sh (log in)   ./inspect.sh (look inside)   ./stop.sh"
