#!/bin/bash
# Run on the Proxmox host as root:  ./inspect-pve.sh 901
# Read-only. Looks at a VM Proxmox is running: by default lab-kvm itself,
# the VM you did labs 01-04 in.
set -euo pipefail
VMID=${1:-901}

section() { printf '\n== %s\n' "$*"; }

command -v qm >/dev/null || { echo "run this on the Proxmox host (qm not found)"; exit 1; }

section "Proxmox's description of the VM: a flat key/value file, not libvirt XML"
cat /etc/pve/qemu-server/"$VMID".conf

section "Is libvirt involved? (Proxmox doesn't use it)"
systemctl is-active libvirtd virtqemud 2>/dev/null || true
command -v virsh >/dev/null && echo "virsh present" || echo "no virsh on this host"

section "The QEMU command Proxmox generates from that file (qm showcmd)"
qm showcmd "$VMID" --pretty

section "The running process: Proxmox's QEMU binary is called 'kvm', and it runs as root"
PID=$(cat /var/run/qemu-server/"$VMID".pid)
ps -o user,pid,pcpu,rss,comm -p "$PID"
ps -L -o tid,comm -p "$PID" | grep -i 'CPU' || true

section "Proxmox drives QEMU over QMP too: here's its socket"
ls -l /var/run/qemu-server/"$VMID".qmp

section "The same QMP the other labs used, via qm's monitor (HMP wrapper)"
for cmd in "info kvm" "info status"; do
  echo "$cmd" | qm monitor "$VMID" 2>/dev/null | grep -vE '^(qm>|Entering QEMU Monitor)' || true
done

section "Nested virtualization on this host"
for m in kvm_intel kvm_amd; do
  if [[ -r /sys/module/$m/parameters/nested ]]; then
    echo "$m nested = $(cat /sys/module/$m/parameters/nested)"
  fi
done
