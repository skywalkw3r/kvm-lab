// kvm-hello: the smallest useful VMM (x86_64).
// Everything QEMU does starts with these same ioctls on /dev/kvm.
//
//   /dev/kvm  --KVM_CREATE_VM-->  vm fd  --KVM_CREATE_VCPU-->  vcpu fd  --KVM_RUN--> (guest runs)
//
// Usage: ./kvm-hello guest.bin

#include <err.h>
#include <fcntl.h>
#include <linux/kvm.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#define GUEST_RAM_SIZE  0x10000UL  // 64 KiB of guest RAM at guest-physical 0
#define GUEST_LOAD_ADDR 0x1000UL   // where the guest code goes
#define SERIAL_PORT     0x3f8      // COM1

int main(int argc, char **argv)
{
    if (argc != 2)
        errx(1, "usage: %s guest.bin", argv[0]);

    // 1. Talk to the KVM module.
    int kvm = open("/dev/kvm", O_RDWR | O_CLOEXEC);
    if (kvm < 0)
        err(1, "open /dev/kvm");
    printf("[vmm] KVM API version %d\n", ioctl(kvm, KVM_GET_API_VERSION, 0));

    // 2. Create a VM: an empty guest-physical address space, no CPUs yet.
    int vm = ioctl(kvm, KVM_CREATE_VM, 0);
    if (vm < 0)
        err(1, "KVM_CREATE_VM");

    // Intel quirk: real mode needs a scratch area for a task state segment
    // on CPUs without "unrestricted guest". QEMU sets this too.
    if (ioctl(vm, KVM_SET_TSS_ADDR, 0xfffbd000) < 0)
        err(1, "KVM_SET_TSS_ADDR");

    // 3. Guest RAM is ordinary memory in *our* process, handed to KVM.
    //    KVM maps it into the guest with EPT/NPT (second-level) page tables.
    uint8_t *ram = mmap(NULL, GUEST_RAM_SIZE, PROT_READ | PROT_WRITE,
                        MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (ram == MAP_FAILED)
        err(1, "mmap");

    FILE *f = fopen(argv[1], "rb");
    if (!f)
        err(1, "%s", argv[1]);
    size_t n = fread(ram + GUEST_LOAD_ADDR, 1, GUEST_RAM_SIZE - GUEST_LOAD_ADDR, f);
    fclose(f);
    printf("[vmm] loaded %zu bytes of guest code at 0x%lx\n", n, GUEST_LOAD_ADDR);

    struct kvm_userspace_memory_region region = {
        .slot = 0,
        .guest_phys_addr = 0,
        .memory_size = GUEST_RAM_SIZE,
        .userspace_addr = (uint64_t)ram,
    };
    if (ioctl(vm, KVM_SET_USER_MEMORY_REGION, &region) < 0)
        err(1, "KVM_SET_USER_MEMORY_REGION");

    // 4. Create a vCPU.
    int vcpu = ioctl(vm, KVM_CREATE_VCPU, 0);
    if (vcpu < 0)
        err(1, "KVM_CREATE_VCPU");

    // 5. The kvm_run struct is shared memory between KVM and us: after each
    //    KVM_RUN returns, it says *why* the guest stopped.
    int run_size = ioctl(kvm, KVM_GET_VCPU_MMAP_SIZE, 0);
    struct kvm_run *run = mmap(NULL, run_size, PROT_READ | PROT_WRITE,
                               MAP_SHARED, vcpu, 0);
    if (run == MAP_FAILED)
        err(1, "mmap kvm_run");

    // 6. Set up the CPU: real mode, code segment at 0, instruction pointer at our code.
    //    (A real x86 resets to 0xffff0 in the BIOS; we skip the BIOS.)
    struct kvm_sregs sregs;
    if (ioctl(vcpu, KVM_GET_SREGS, &sregs) < 0)
        err(1, "KVM_GET_SREGS");
    sregs.cs.base = 0;
    sregs.cs.selector = 0;
    if (ioctl(vcpu, KVM_SET_SREGS, &sregs) < 0)
        err(1, "KVM_SET_SREGS");

    struct kvm_regs regs = {
        .rip = GUEST_LOAD_ADDR,
        .rflags = 0x2, // bit 1 is reserved and must be set; interrupts off
    };
    if (ioctl(vcpu, KVM_SET_REGS, &regs) < 0)
        err(1, "KVM_SET_REGS");

    // 7. The run loop. This is the heart of every VMM, QEMU included:
    //    run the guest until it does something the hardware can't handle alone.
    unsigned long exits = 0, io_exits = 0;
    for (;;) {
        if (ioctl(vcpu, KVM_RUN, 0) < 0)
            err(1, "KVM_RUN");
        exits++;

        switch (run->exit_reason) {
        case KVM_EXIT_IO:
            io_exits++;
            if (run->io.direction == KVM_EXIT_IO_OUT && run->io.port == SERIAL_PORT) {
                // We are the "device model": emulate a serial port by printing.
                // The byte sits inside the kvm_run page, at io.data_offset.
                putchar(*((char *)run + run->io.data_offset));
                fflush(stdout);
            } else {
                printf("[vmm] unexpected port I/O %s port 0x%x\n",
                       run->io.direction == KVM_EXIT_IO_OUT ? "out" : "in", run->io.port);
            }
            break;

        case KVM_EXIT_HLT:
            if (ioctl(vcpu, KVM_GET_REGS, &regs) < 0)
                err(1, "KVM_GET_REGS");
            printf("[vmm] guest halted at rip=0x%llx\n", (unsigned long long)regs.rip);
            printf("[vmm] %lu exits to userspace (%lu port I/O)\n", exits, io_exits);
            return 0;

        case KVM_EXIT_FAIL_ENTRY:
            errx(1, "KVM_EXIT_FAIL_ENTRY: hardware reason 0x%llx",
                 (unsigned long long)run->fail_entry.hardware_entry_failure_reason);

        case KVM_EXIT_INTERNAL_ERROR:
            errx(1, "KVM_EXIT_INTERNAL_ERROR: suberror %u", run->internal.suberror);

        default:
            errx(1, "unhandled exit reason %u", run->exit_reason);
        }
    }
}
