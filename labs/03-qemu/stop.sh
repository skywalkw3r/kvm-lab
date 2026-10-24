#!/bin/bash
# Ask the guest to power off through QMP (like pressing the power button), then wait.
cd "$(dirname "$0")" || exit 1
PID=$(cat ~/qemu-lab/qemu.pid 2>/dev/null) || { echo "not running"; exit 0; }
./qmp.sh system_powerdown >/dev/null || true
for _ in $(seq 30); do
  kill -0 "$PID" 2>/dev/null || { echo "stopped"; exit 0; }
  sleep 1
done
./qmp.sh quit >/dev/null 2>&1
echo "guest ignored the power button; QEMU told to quit"
