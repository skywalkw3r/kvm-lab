#!/bin/bash
# SSH into a lab VM by its short name:  scripts/ssh.sh kvm   (or vdsm, kubevirt, ovirt_engine)
# Extra arguments run as a command:     scripts/ssh.sh kvm 'uname -a'
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM=${1:?usage: scripts/ssh.sh <kvm|vdsm|kubevirt|ovirt_engine> [command]}
shift

IP=$(terraform -chdir="$REPO/terraform" output -json vms | jq -r --arg vm "$VM" '.[$vm].ip // empty')
[[ -n $IP ]] || { echo "no running VM '$VM' (is it enabled in terraform.tfvars? run make up)" >&2; exit 1; }

# Ask for a terminal only when there is one (interactive use), not when scripted.
tty=-T; [[ -t 0 ]] && tty=-t
exec ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$REPO/ansible/.known_hosts" \
  "$tty" "lab@$IP" "$@"
