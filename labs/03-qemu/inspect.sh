#!/bin/bash
# Look inside a running QEMU process: a VM is just a Linux process with some special fds.
set -euo pipefail
cd "$(dirname "$0")"
PID=$(cat ~/qemu-lab/qemu.pid)

section() { printf '\n== %s\n' "$*"; }

section "Threads: one per vCPU ('CPU n/KVM'), plus the main loop and worker threads"
ps -L -o tid,comm,pcpu -p "$PID"

section "KVM file descriptors: /dev/kvm, the VM, one per vCPU"
for fd in /proc/"$PID"/fd/*; do
  target=$(readlink "$fd")
  [[ $target == *kvm* ]] && echo "fd $(basename "$fd") -> $target"
done

section "Guest RAM is just a big mapping in QEMU's address space (look for 512M)"
grep -E 'rw-s|rw-p' /proc/"$PID"/maps | awk '{split($1,a,"-"); s=strtonum("0x"a[2])-strtonum("0x"a[1]); if (s >= 256*1024*1024) printf "%s  %d MiB\n", $1, s/1048576}'

section "QMP: is KVM really on? (vs TCG, QEMU's software CPU emulator)"
./qmp.sh query-kvm

section "QMP: vCPUs and the host thread that runs each one"
./qmp.sh query-cpus-fast | jq -c '.return[] | {"cpu-index", "thread-id"}'

section "QMP: block devices"
./qmp.sh query-block | jq -c '.return[] | {device, qdev, file: .inserted.file, driver: .inserted.drv}'

TMP=$(mktemp -d)
trap 'sudo rm -rf "$TMP"' EXIT

section "QEMU's ioctl() calls over 3 s, by request (strace)"
sudo timeout 3 strace -f -qq -e trace=ioctl -p "$PID" -o "$TMP/strace.txt" || true
grep -oE 'ioctl\([0-9]+, [A-Z0-9_]+' "$TMP/strace.txt" | awk '{print $2}' | sort | uniq -c | sort -rn | sed -n '1,6p'

section "VM exits by reason over 3 s, seen by the kernel (kvm:kvm_exit tracepoint)"
sudo perf record -q -e kvm:kvm_exit -p "$PID" -o "$TMP/perf.data" -- sleep 3 2>/dev/null || true
sudo perf script -i "$TMP/perf.data" -F trace 2>/dev/null |
  grep -oE 'reason [A-Z_]+' | awk '{print $2}' | sort | uniq -c | sort -rn | sed -n '1,8p'

section "KVM's own counters for this VM: /sys/kernel/debug/kvm/<qemu pid>-<vm fd>/"
VMDIR=$(sudo find /sys/kernel/debug/kvm -maxdepth 1 -name "$PID-*" | sed -n '1,1p')
for stat in exits halt_exits io_exits mmio_exits irq_injections; do
  printf '  %-15s %s\n' "$stat" "$(sudo cat "$VMDIR/$stat" 2>/dev/null || echo '?')"
done
