#!/bin/bash
# Layer 0: is hardware virtualization available, and is KVM loaded?
# Run inside lab-kvm (and on your Proxmox host, to compare).

section() { printf '\n== %s\n' "$*"; }

section "CPU virtualization extensions (vmx = Intel VT-x, svm = AMD-V)"
grep -oEm1 '\b(vmx|svm)\b' /proc/cpuinfo || echo "none: KVM can't run here"
lscpu | grep -iE 'virtualization|hypervisor vendor|model name'

section "KVM kernel modules"
lsmod | grep -E '^kvm' || echo "no kvm modules loaded"

section "Nested virtualization (can *this* machine's guests run KVM too?)"
for m in kvm_intel kvm_amd; do
  if [[ -r /sys/module/$m/parameters/nested ]]; then
    echo "$m nested = $(cat /sys/module/$m/parameters/nested)"
  fi
done

section "/dev/kvm: the whole KVM API is ioctl() calls on this one file"
ls -l /dev/kvm

section "Kernel messages from KVM"
sudo dmesg | grep -i kvm | tail -5

section "VMs this kernel is running right now (one dir per VM)"
sudo ls /sys/kernel/debug/kvm/ 2>/dev/null | grep -E '^[0-9]+-' || echo "(none yet)"
