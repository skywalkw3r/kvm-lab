# Lab 02: The raw KVM API

**Runs on:** `lab-kvm` · **Time:** 20 min

## Why this layer exists

This lab writes a **virtual machine monitor** (VMM) from scratch: a program that uses
`/dev/kvm` to run guest code. It's about 150 lines of C, and it does the same thing QEMU,
Firecracker and Cloud Hypervisor do at their core.

```
open("/dev/kvm")
  └─ KVM_CREATE_VM                    → a VM: an empty guest-physical address space
       ├─ KVM_SET_USER_MEMORY_REGION  → "guest RAM is this mmap()ed buffer in my process"
       └─ KVM_CREATE_VCPU             → a virtual CPU
            └─ loop: KVM_RUN          → run the guest until it exits, then handle the exit
```

The guest is a few instructions of assembly ([guest-x86_64.s](guest-x86_64.s)). They write a
string to the serial port, one byte at a time, then halt. The CPU can't complete a write to
a serial port by itself, so **every byte causes a VM exit**. `KVM_RUN` returns, the VMM
prints the byte, and the loop calls `KVM_RUN` again.

## Do it

```bash
cd ~/labs/02-raw-kvm-api
make run
```

```
[vmm] KVM API version 12
[vmm] loaded 40 bytes of guest code at 0x1000
Hello from a KVM guest!
[vmm] guest halted at rip=0x100f
[vmm] 25 exits to userspace (24 port I/O)
```

The whole guest is 40 bytes: 15 bytes of instructions and the 25-byte string.

Then watch the ioctls go by:

```bash
make trace          # strace -e trace=ioctl ./kvm-hello guest.bin
```

```
ioctl(5, KVM_RUN, 0)                    = 0
tioctl(5, KVM_RUN, 0)                    = 0
!ioctl(5, KVM_RUN, 0)                    = 0

ioctl(5, KVM_RUN, 0)                    = 0
ioctl(5, KVM_GET_REGS, {rax=0, ..., rsp=0, rbp=0, ..., rip=0x100f, rflags=0x46}) = 0
```

Each guest character (`t`, `!`, the newline) lands between two `KVM_RUN` calls: the guest runs,
exits on the `out`, the VMM prints the byte, and the loop calls `KVM_RUN` again.

## What to notice

- **Guest RAM is ordinary memory in the VMM's process.** The VMM `mmap()`s a buffer and copies
  the guest code into it. That's also why a VM's memory shows up as QEMU's RSS in `top`.
- **One `KVM_RUN` per exit.** 24 characters means 24 `KVM_EXIT_IO` exits, plus one
  `KVM_EXIT_HLT` at the end. Exits are expensive (microseconds each), which is why real VMs use
  **virtio** devices: they batch I/O through shared memory instead of trapping on every byte.
- **The VMM *is* the hardware.** Port `0x3f8` only means "serial port" because our `switch`
  statement says so. QEMU is a much bigger version of that `switch`.
- **The `kvm_run` page** is shared memory between the kernel and the VMM. KVM writes the exit
  reason and its details there, so they don't have to be copied out.

## Try changing it

1. Make the guest read a byte from port `0x3f8` (`in (%dx), %al`). Handle `KVM_EXIT_IO_IN` in
   the VMM by putting a character into the data area. You've just written a keyboard.
2. Remove the `hlt`. What happens? (Ctrl-C to stop.)
3. On an arm64 Linux machine, the same `make run` builds [kvm-hello-arm64.c](kvm-hello-arm64.c)
   instead. ARM has no I/O ports, so the "serial port" is a memory address that exits with
   `KVM_EXIT_MMIO`, and the guest powers off through a PSCI hypercall that KVM handles in the
   kernel.

**Next:** [Lab 03: QEMU](../03-qemu/)
