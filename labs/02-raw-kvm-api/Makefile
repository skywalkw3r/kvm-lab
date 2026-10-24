# Builds the VMM and the guest for whatever machine you're on (x86_64 or aarch64).
ARCH   := $(shell uname -m)
CFLAGS := -O2 -Wall -Wextra

ifeq ($(ARCH),x86_64)
  VMM_SRC   := kvm-hello-x86_64.c
  GUEST_SRC := guest-x86_64.s
  AS_CMD    := as --32
  LD_CMD    := ld -m elf_i386 -Ttext=0x1000
else ifeq ($(ARCH),aarch64)
  VMM_SRC   := kvm-hello-arm64.c
  GUEST_SRC := guest-arm64.S
  AS_CMD    := $(CC) -c
  LD_CMD    := ld -Ttext=0x40000000
else
  $(error unsupported architecture $(ARCH))
endif

all: kvm-hello guest.bin

kvm-hello: $(VMM_SRC)
	$(CC) $(CFLAGS) -o $@ $<

# Assemble the guest and strip it down to raw machine code: just the .text section,
# no ELF headers (and none of the notes some toolchains add).
guest.bin: $(GUEST_SRC)
	$(AS_CMD) -o guest.o $<
	$(LD_CMD) -o guest.elf guest.o
	objcopy -O binary -j .text guest.elf $@

run: all
	./kvm-hello guest.bin

# Watch every ioctl the VMM makes: one KVM_RUN per guest exit.
trace: all
	strace -e trace=ioctl ./kvm-hello guest.bin

clean:
	rm -f kvm-hello guest.o guest.elf guest.bin

.PHONY: all run trace clean
