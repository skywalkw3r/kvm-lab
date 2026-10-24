# Lab 01: Hardware and KVM

**Runs on:** `lab-kvm` (`make ssh VM=kvm`) · **Time:** 10 min

## Why this layer exists

A CPU can't safely run two operating systems at once by itself: both expect to own the page
tables, the interrupt controller and the privileged instructions. Hardware virtualization
(Intel **VT-x**, AMD **AMD-V**, ARM's **EL2**) adds a mode for the guest. In that mode the CPU
runs guest code at full speed, but **traps out** to a hypervisor whenever the guest does
something only the real machine should handle.

**KVM** is the Linux kernel module that drives those extensions. It turns the kernel into a
hypervisor, but KVM itself does surprisingly little:

- runs a guest CPU until it traps (a **VM exit**)
- manages the second-level page tables (Intel EPT, AMD NPT) that map guest memory to host memory
- emulates a few hot-path devices in the kernel (interrupt controllers, timers)

Everything else (disks, network cards, firmware, the whole "computer") is left to a userspace
program. That program is the next layer.

## Do it

```bash
cd ~/labs/01-kvm
./check-kvm.sh
```

Then run the same checks **on your Proxmox host** and compare.

## What to notice

- `vmx` (Intel) or `svm` (AMD) shows up **inside a VM**. That's nested virtualization: Proxmox
  gave this VM `cpu: host`, so the extensions pass through and KVM works here too. Your VM
  is a hypervisor running inside a hypervisor.
- `lsmod` shows two modules: `kvm` (generic) and `kvm_intel` or `kvm_amd` (CPU-specific).
- `/dev/kvm` is a character device. **The entire KVM API is `ioctl()` calls on this one file.**
  No daemon, no service: if you can open it, you can make VMs.
- `/sys/kernel/debug/kvm/` is empty now. Check it again during labs 02-04: a directory appears
  for each running VM, with live counters like `exits`, `halt_exits` and `io_exits`.

## Questions

1. `/dev/kvm` is mode `0666` on some distros and `0660` (group `kvm`) on others. What could
   an unprivileged user do with it?
2. On the Proxmox host, `nested` must be `Y` for this lab to work. What would you see inside
   `lab-kvm` if it weren't?

**Next:** [Lab 02: the raw KVM API](../02-raw-kvm-api/)
