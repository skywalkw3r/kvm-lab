#!/bin/bash
# What did libvirt do on our behalf? Compare everything here with lab 03.
set -euo pipefail
cd "$(dirname "$0")"
export LIBVIRT_DEFAULT_URI=qemu:///system
NAME=lab-libvirt

section() { printf '\n== %s\n' "$*"; }

section "Domains libvirt knows about"
virsh list --all

section "The domain XML: libvirt's description of the VM (first 40 lines)"
virsh dumpxml "$NAME" | sed -n '1,40p'
echo "... (virsh dumpxml $NAME for all of it)"

section "The QEMU command libvirt generated from that XML (one option per line)"
PID=$(pgrep -f "guest=$NAME")
tr '\0' '\n' < /proc/"$PID"/cmdline |
  awk '/^-/ { if (opt) print opt; opt = "  " $0; next } { opt = opt ? opt " " $0 : "  " $0 } END { print opt }' |
  cut -c1-150
echo "Arguments: libvirt=$(tr '\0' '\n' < /proc/"$PID"/cmdline | wc -l)  vs  lab 03=$(wc -w < ~/qemu-lab/cmdline.txt 2>/dev/null || echo '?')"

section "libvirt talks to QEMU over QMP, just like ../03-qemu/qmp.sh did"
virsh qemu-monitor-command "$NAME" --pretty '{"execute": "query-kvm"}'

section "Who runs QEMU? A dedicated user, with a per-VM SELinux label (sVirt)"
ps -o user,label,pid,comm -p "$PID"

section "Stats libvirt collects from QEMU and the kernel (a few of many)"
virsh domstats "$NAME" --cpu-total --balloon --block |
  grep -E '^ +(cpu\.time|balloon\.(current|unused)|block\.[0-9]+\.(name|rd\.reqs|wr\.reqs))='

section "The same information through the libvirt API (what VDSM, Nova and KubeVirt use)"
python3 ./api-example.py
