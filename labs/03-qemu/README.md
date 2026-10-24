# Lab 03: QEMU, the userspace VMM

**Runs on:** `lab-kvm` · **Time:** 30 min

## Why this layer exists

Lab 02's VMM emulated one serial port. A real operating system expects a whole PC: firmware,
PCI buses, disk and network controllers, a clock, a graphics card. **QEMU** provides all of
that. On its own it's a full machine *emulator*; with `accel=kvm` it hands the CPU work to KVM
and handles the exits, exactly like `kvm-hello` did.

QEMU also brings the things that make VMs practical:

- **disk image formats** (qcow2, with snapshots and copy-on-write backing files)
- **virtio** paravirtual devices, designed to cause few VM exits
- **live migration**
- **QMP**, the QEMU Machine Protocol: a JSON control socket for scripts and management software

## Do it

```bash
cd ~/labs/03-qemu
./start.sh            # downloads CirrOS (~20 MB) and boots it with plain qemu-system-x86_64
./console.sh          # log in: cirros / gocubsgo   (Ctrl-] to detach)
./inspect.sh          # look inside the running QEMU process
./qmp.sh query-status # talk QMP yourself
./stop.sh
```

Read [start.sh](start.sh) first: every QEMU option has a comment saying what it is. The guest
reaches its login prompt in about 15 seconds. It gets its hostname from a small cloud-init
seed ISO ([../lib/make-seed.sh](../lib/make-seed.sh)), the same kind of disk Proxmox attaches to
the lab VM you're working in.

`inspect.sh` on an idle guest, trimmed:

```
== Threads: one per vCPU ('CPU n/KVM'), plus the main loop and worker threads
    TID COMMAND         %CPU
  28099 qemu-system-x86  0.8
  28100 call_rcu         0.0
  28102 IO mon_iothread  0.0
  28103 CPU 0/KVM       21.6
  28104 CPU 1/KVM       14.0

== KVM file descriptors: /dev/kvm, the VM, one per vCPU
fd 17 -> /dev/kvm
fd 18 -> anon_inode:kvm-vm
fd 24 -> anon_inode:kvm-vcpu:0
fd 26 -> anon_inode:kvm-vcpu:1

== Guest RAM is just a big mapping in QEMU's address space (look for 512M)
7f200be00000-7f202be00000  512 MiB

== QEMU's ioctl() calls over 3 s, by request (strace)
   1500 KVM_IRQ_LINE_STATUS
      2 KVM_RUN

== VM exits by reason over 3 s, seen by the kernel (kvm:kvm_exit tracepoint)
     50 MSR_WRITE
     19 HLT
      5 MSR_READ

== KVM's own counters for this VM: /sys/kernel/debug/kvm/<qemu pid>-<vm fd>/
  exits           247874
  io_exits        111484
  mmio_exits      15434
```

## What to notice

- **A VM is a process.** One thread per vCPU (`CPU 0/KVM`, `CPU 1/KVM`) runs lab 02's
  `KVM_RUN` loop. The others are QEMU's main loop, its monitor and I/O workers. (The thread names
  appear because of `debug-threads=on` in `start.sh`.)
- **The fds** are lab 02's: `/dev/kvm`, one `kvm-vm`, and one `kvm-vcpu:N` per vCPU.
- **Guest RAM** is one 512 MiB anonymous mapping in QEMU's address space, exactly like lab 02's
  `mmap()`.
- **`KVM_RUN` almost never returns.** In 3 seconds strace saw just 2 `KVM_RUN` calls: the vCPU
  threads sit *inside* the kernel. Meanwhile the kernel recorded about 75 exits, and KVM handled
  all of them itself (`MSR_WRITE` and `HLT` are a timer being programmed and an idle CPU) without
  waking QEMU. Lab 02 exited to userspace on every byte; a real VM with in-kernel devices mostly
  doesn't. The `io_exits` and `mmio_exits` counters grew during boot, when the firmware and kernel
  were probing devices.
- **Most of QEMU's own ioctls are `KVM_IRQ_LINE_STATUS`:** QEMU updating interrupt lines for
  its emulated devices in KVM's interrupt controller. Which device? See question 3.
- **`query-kvm`** says `"enabled": true`. Remove `accel=kvm` from `start.sh` and QEMU falls back
  to TCG, its software CPU emulator. Compare how long the boot takes in `console.log`.
- **The command line is long and fragile.** Imagine maintaining hundreds of them, plus their
  disks, networks and firewall rules, across many hosts. That's the next layer's job.

## Questions

1. `inspect.sh` shows a 512 MiB mapping in QEMU's memory map. What happens to it when the
   guest isn't using all of its RAM? (Look up *memory ballooning* and *KSM*.)
2. QMP has `migrate`. What would QEMU have to copy, and in what order, to move this running VM
   to another host?
3. Find the device behind the `KVM_IRQ_LINE_STATUS` calls. Useful tools:
   `./qmp.sh human-monitor-command '{"command-line": "info qtree"}'`, `info irq`, and
   `strace -f -e trace=ioctl -p <pid>` to see the arguments of each call.

**Next:** [Lab 04: libvirt](../04-libvirt/)
