// kvm-hello: the smallest useful VMM (arm64).
// Everything QEMU does starts with these same ioctls on /dev/kvm.
//
//   /dev/kvm  --KVM_CREATE_VM-->  vm fd  --KVM_CREATE_VCPU-->  vcpu fd  --KVM_RUN--> (guest runs)
//
// Usage: ./kvm-hello guest.bin

#include <err.h>
#include <fcntl.h>
#include <linux/kvm.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#define GUEST_RAM_BASE 0x40000000UL
#define GUEST_RAM_SIZE 0x10000UL      // 64 KiB is plenty
#define UART_ADDR      0x10000000UL   // no RAM here, so accesses exit to us

// Register ids for KVM_{GET,SET}_ONE_REG: "core" registers are addressed by
// their offset in struct kvm_regs, in 32-bit units.
#define CORE_REG(field) \
    (KVM_REG_ARM64 | KVM_REG_SIZE_U64 | KVM_REG_ARM_CORE | \
     (offsetof(struct kvm_regs, field) / sizeof(uint32_t)))

static uint64_t get_reg(int vcpu, uint64_t id)
{
    uint64_t val;
    struct kvm_one_reg reg = { .id = id, .addr = (uint64_t)&val };
    if (ioctl(vcpu, KVM_GET_ONE_REG, &reg) < 0)
        err(1, "KVM_GET_ONE_REG");
    return val;
}

static void set_reg(int vcpu, uint64_t id, uint64_t val)
{
    struct kvm_one_reg reg = { .id = id, .addr = (uint64_t)&val };
    if (ioctl(vcpu, KVM_SET_ONE_REG, &reg) < 0)
        err(1, "KVM_SET_ONE_REG");
}

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

    // 3. Guest RAM is ordinary memory in *our* process, handed to KVM.
    //    KVM maps it into the guest with stage-2 page tables.
    uint8_t *ram = mmap(NULL, GUEST_RAM_SIZE, PROT_READ | PROT_WRITE,
                        MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (ram == MAP_FAILED)
        err(1, "mmap");

    FILE *f = fopen(argv[1], "rb");
    if (!f)
        err(1, "%s", argv[1]);
    size_t n = fread(ram, 1, GUEST_RAM_SIZE, f);
    fclose(f);
    printf("[vmm] loaded %zu bytes of guest code at 0x%lx\n", n, GUEST_RAM_BASE);

    struct kvm_userspace_memory_region region = {
        .slot = 0,
        .guest_phys_addr = GUEST_RAM_BASE,
        .memory_size = GUEST_RAM_SIZE,
        .userspace_addr = (uint64_t)ram,
    };
    if (ioctl(vm, KVM_SET_USER_MEMORY_REGION, &region) < 0)
        err(1, "KVM_SET_USER_MEMORY_REGION");

    // 4. Create a vCPU and initialise it as "whatever the host CPU is".
    //    PSCI 0.2 lets the guest power itself off via a hypercall.
    int vcpu = ioctl(vm, KVM_CREATE_VCPU, 0);
    if (vcpu < 0)
        err(1, "KVM_CREATE_VCPU");

    struct kvm_vcpu_init init;
    if (ioctl(vm, KVM_ARM_PREFERRED_TARGET, &init) < 0)
        err(1, "KVM_ARM_PREFERRED_TARGET");
    init.features[0] |= 1 << KVM_ARM_VCPU_PSCI_0_2;
    if (ioctl(vcpu, KVM_ARM_VCPU_INIT, &init) < 0)
        err(1, "KVM_ARM_VCPU_INIT");

    // 5. The kvm_run struct is shared memory between KVM and us: after each
    //    KVM_RUN returns, it says *why* the guest stopped.
    int run_size = ioctl(kvm, KVM_GET_VCPU_MMAP_SIZE, 0);
    struct kvm_run *run = mmap(NULL, run_size, PROT_READ | PROT_WRITE,
                               MAP_SHARED, vcpu, 0);
    if (run == MAP_FAILED)
        err(1, "mmap kvm_run");

    // 6. Point the program counter at our code. (The reset state is EL1, MMU off.)
    set_reg(vcpu, CORE_REG(regs.pc), GUEST_RAM_BASE);

    // 7. The run loop. This is the heart of every VMM, QEMU included:
    //    run the guest until it does something the hardware can't handle alone.
    unsigned long exits = 0, mmio_exits = 0;
    for (;;) {
        if (ioctl(vcpu, KVM_RUN, 0) < 0)
            err(1, "KVM_RUN");
        exits++;

        switch (run->exit_reason) {
        case KVM_EXIT_MMIO:
            mmio_exits++;
            if (run->mmio.is_write && run->mmio.phys_addr == UART_ADDR) {
                // We are the "device model": emulate a UART by printing.
                putchar(run->mmio.data[0]);
                fflush(stdout);
            } else {
                printf("[vmm] unexpected MMIO %s at 0x%llx\n",
                       run->mmio.is_write ? "write" : "read",
                       (unsigned long long)run->mmio.phys_addr);
            }
            break;

        case KVM_EXIT_SYSTEM_EVENT:
            printf("[vmm] guest asked for system event %u (%s)\n",
                   run->system_event.type,
                   run->system_event.type == KVM_SYSTEM_EVENT_SHUTDOWN ? "SHUTDOWN" : "other");
            printf("[vmm] guest PC=0x%llx x0=0x%llx\n",
                   (unsigned long long)get_reg(vcpu, CORE_REG(regs.pc)),
                   (unsigned long long)get_reg(vcpu, CORE_REG(regs.regs[0])));
            printf("[vmm] %lu exits to userspace (%lu MMIO)\n", exits, mmio_exits);
            return 0;

        default:
            errx(1, "unhandled exit reason %u", run->exit_reason);
        }
    }
}
