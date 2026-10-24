# Lab 04: libvirt

**Runs on:** `lab-kvm` · **Time:** 30 min

## Why this layer exists

QEMU's command line changes between versions, and QEMU knows nothing about the host it runs
on: which disks belong to which VM, which networks exist, who's allowed to do what. **libvirt**
sits on top and provides:

- a **stable API** (C, with bindings for Python, Go and more) that hasn't broken compatibility in
  over a decade
- **domain XML**: a declarative description of a VM that libvirt turns into the right QEMU
  command for the QEMU version installed
- **process management**: it starts QEMU, talks to it over QMP, and keeps track of its state
- **storage pools and virtual networks** (the `default` NAT network with `virbr0` and dnsmasq)
- **security**: each QEMU runs as the `qemu` user with its own SELinux label (sVirt), so one
  compromised VM can't touch another VM's disks

`virsh` is just a command-line client for that API. So are most of the management layers in
labs 06-08.

## Do it

```bash
cd ~/labs/04-libvirt
./create.sh           # same CirrOS guest as lab 03, created with virt-install
./inspect.sh          # domain XML vs the QEMU command libvirt generated
virsh console lab-libvirt
python3 api-example.py
./destroy.sh
```

`inspect.sh`, trimmed:

```
== The QEMU command libvirt generated from that XML (one option per line)
  /usr/bin/qemu-system-x86_64
  -name guest=lab-libvirt,debug-threads=on
  -S
  -machine pc-q35-10.2,usb=off,dump-guest-core=off,memory-backend=pc.ram,hpet=off,acpi=on
  -accel kvm
  -cpu host,migratable=on
  -chardev socket,id=charmonitor,fd=25,server=on,wait=off
  -mon chardev=charmonitor,id=monitor,mode=control
  -device {"driver":"pcie-root-port","port":8,"chassis":1,"id":"pci.1","bus":"pcie.0","multifunction":true,"addr":"0x1"}
  ... 13 more pcie-root-ports ...
  -device {"driver":"virtio-blk-pci","bus":"pci.4","addr":"0x0","drive":"libvirt-2-format","id":"virtio-disk0","bootindex":1}
  -netdev {"type":"tap","fd":"26","vhost":true,"vhostfd":"28","id":"hostnet0"}
  -sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny
Arguments: libvirt=115  vs  lab 03=30

== Who runs QEMU? A dedicated user, with a per-VM SELinux label (sVirt)
USER     LABEL                                   PID COMMAND
qemu     system_u:system_r:svirt_t:s0:c273,c325 37235 qemu-system-x86

== The same information through the libvirt API (what VDSM, Nova and KubeVirt use)
hypervisor: QEMU 10.2.2 on lab-kvm, libvirt 12.0.0, 4 host CPUs
  lab-libvirt    running   2 vCPU  512 MiB  9.3s CPU used
```

## What to notice

- **XML in, QEMU command out.** Lab 03's hand-written command had 30 arguments; libvirt
  generated 115 for the same guest. The extras are things you'd otherwise have to get right
  yourself: a pinned machine type version (`pc-q35-10.2`, so the guest's hardware doesn't change
  when QEMU is upgraded), explicit PCI addresses, PCIe root ports for hot-plugging devices later,
  and a seccomp `-sandbox`.
- **`-S` means "start paused."** libvirt starts QEMU frozen, finishes setting it up over QMP, then
  sends `cont`. And `fd=25`: libvirt opens the monitor socket and the tap device itself and hands
  QEMU the file descriptors, so QEMU never needs the privileges to create them.
- **libvirt uses QMP too.** `virsh qemu-monitor-command` sends raw QMP, the same protocol as
  `../03-qemu/qmp.sh`. libvirt didn't replace QEMU's control interface; it wraps it.
- **sVirt:** QEMU runs as the unprivileged `qemu` user with the SELinux label
  `svirt_t:s0:c273,c325`. That category pair is unique to this VM, and `sudo ls -Z
  /var/lib/libvirt/images/` shows that only the VM's *writable* disk has the same pair:

  ```
  system_u:object_r:svirt_image_t:s0:c273,c325 lab-libvirt.qcow2
           system_u:object_r:virt_content_t:s0 cirros-base.qcow2
           system_u:object_r:virt_content_t:s0 lab-libvirt-seed.iso
  ```

  The shared, read-only base image and seed get `virt_content_t`, which every VM may read but none
  may write. A compromised QEMU can't open another VM's disk, even though both run as `qemu`.
- **Modular daemons:** modern libvirt splits into `virtqemud`, `virtnetworkd`, `virtstoraged`
  and so on, each started on demand by its systemd socket (`systemctl list-sockets | grep virt`).

## Questions

1. `virsh edit lab-libvirt`, change the vCPU count, and `virsh start` it again. What changed
   in the QEMU command line?
2. libvirt also drives Xen, LXC, VMware ESXi and others through the same API. What does that
   say about where the line between "libvirt" and "QEMU" sits?

**Next:** [Lab 05: Proxmox](../05-proxmox/)
