# The entire "guest OS": prints a string to the serial port, then halts.
# Runs in 16-bit real mode (how every x86 CPU starts), loaded at guest-physical 0x1000.
#
# - `out` to I/O port 0x3f8 (the classic COM1 serial port) can't be handled
#   by the CPU alone, so KVM stops the guest and returns KVM_EXIT_IO to us.
#   QEMU emulates every legacy device this way.
# - `hlt` with interrupts off means "nothing left to do": KVM_EXIT_HLT.

    .code16
    .text
    .global _start
_start:
    mov     $0x3f8, %dx         # COM1 data port
    mov     $msg, %si
1:  lodsb                       # al = next byte (RAM read: no exit)
    test    %al, %al
    jz      2f
    out     %al, (%dx)          # port I/O: exit to userspace
    jmp     1b
2:  hlt

msg:
    .asciz  "Hello from a KVM guest!\n"
