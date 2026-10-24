// The entire "guest OS": prints a string through a fake UART, then powers off.
// Runs at EL1 with the MMU off, loaded at guest-physical 0x40000000.
//
// - Loads from RAM are handled by hardware (no exit).
// - Stores to 0x10000000 hit an address with no memory behind it, so KVM
//   exits to userspace with KVM_EXIT_MMIO. That's how every emulated device
//   in QEMU works.
// - "hvc #0" with x0 = PSCI SYSTEM_OFF is handled inside KVM itself, which then
//   tells userspace with KVM_EXIT_SYSTEM_EVENT.

    .text
    .global _start
_start:
    movz    x1, #0x1000, lsl #16    // x1 = 0x10000000  (our "UART")
    adr     x2, msg
1:  ldrb    w3, [x2], #1            // next byte (RAM read: no exit)
    cbz     w3, 2f
    strb    w3, [x1]                // MMIO write: exit to userspace
    b       1b
2:  movz    w0, #0x8400, lsl #16
    movk    w0, #0x0008             // x0 = 0x84000008  PSCI_0_2_FN_SYSTEM_OFF
    hvc     #0                      // hypercall into KVM
    b       .

msg:
    .asciz  "Hello from a KVM guest!\n"
