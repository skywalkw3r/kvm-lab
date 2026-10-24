#!/bin/bash
# Lab 06: what VDSM adds on top of libvirt. Run inside lab-vdsm.
set -uo pipefail

section() { printf '\n== %s\n' "$*"; }
# --insecure: plain TCP, matching the lab's ssl = false (an engine would use TLS)
vdsm() { vdsm-client --insecure "$@"; }

section "The services that make up an oVirt host"
systemctl --no-pager --type=service --state=running | grep -E 'vdsm|supervdsm|libvirt|virtqemud|sanlock|mom' || true

section "VDSM runs as user 'vdsm'; supervdsmd runs as root and does the privileged work for it"
ps -o user,pid,args -p "$(pgrep -d, -f 'vdsmd|supervdsmd')" | cut -c1-120

section "VDSM's JSON-RPC API on port 54321: this is what oVirt Engine talks to"
sudo ss -ltnp | grep 54321

section "Host capabilities as VDSM reports them to the engine (8 of $(vdsm Host getCapabilities | jq 'keys | length') fields)"
vdsm Host getCapabilities | jq '{cpuModel, cpuCores, cpuSockets, memSize, kvmEnabled,
  vdsm: .software_version, libvirt: .packages2.libvirt.version, qemu: .packages2["qemu-kvm"].version}'

section "Live host stats (what the engine polls every few seconds)"
vdsm Host getStats | jq '{cpuIdle, cpuUser, cpuSys, memFree, memUsed, vmCount}'

section "VMs VDSM manages right now"
vdsm Host getVMList

section "vdsm-tool configure rewrote libvirt's config: look for the 'by vdsm' sections"
sudo grep -lr 'by vdsm' /etc/libvirt/ 2>/dev/null
sudo grep -A6 'beginning of configuration section by vdsm' /etc/libvirt/libvirtd.conf 2>/dev/null | sed -n '1,12p'

section "libvirt now requires authentication; only read-only virsh works without credentials"
virsh -r -c qemu:///system list --all
echo "Plain virsh, even as root:"
sudo virsh -c qemu:///system list </dev/null 2>&1 | tail -1
