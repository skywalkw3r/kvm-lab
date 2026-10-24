#!/bin/bash
# Send one QMP command and pretty-print the reply. Examples:
#   ./qmp.sh query-status
#   ./qmp.sh query-kvm
#   ./qmp.sh qom-list '{"path": "/machine"}'
#   ./qmp.sh human-monitor-command '{"command-line": "info mtree"}'
set -euo pipefail
cmd=$1 args=${2:-'{}'}
{
  echo '{"execute": "qmp_capabilities"}'
  echo "{\"execute\": \"$cmd\", \"arguments\": $args}"
  sleep 0.5
} | socat - unix-connect:"$HOME/qemu-lab/qmp.sock" | sed -n '3p' | jq .
