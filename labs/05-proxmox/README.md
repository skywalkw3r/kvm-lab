# Lab 05: Proxmox VE, a stack without libvirt

**Runs on:** your Proxmox host, as root (read-only) · **Time:** 15 min

## Why this layer exists

Proxmox VE is a management layer you already use, and it makes an interesting contrast: it
**doesn't use libvirt at all**. Proxmox's own Perl code (`qemu-server`) reads a VM's config file
and builds the QEMU command line itself, then manages the process over QMP, just as libvirt does.

The VM you did labs 01-04 in, `lab-kvm`, is one of those QEMU processes. This lab looks at it
from the outside.

## Do it

Copy the script to the host and run it (it only reads):

```bash
scp labs/05-proxmox/inspect-pve.sh root@<your-pve>:/root/
ssh root@<your-pve> bash /root/inspect-pve.sh 901
```

Trimmed output for `lab-kvm`:

```
== Proxmox's description of the VM: a flat key/value file, not libvirt XML
cores: 4
cpu: host
ide2: local-lvm:vm-901-cloudinit,media=cdrom
ipconfig0: gw=192.168.10.1,ip=192.168.10.51/24
memory: 6144
net0: virtio=BC:24:11:00:00:01,bridge=vmbr0,firewall=0
tags: kvm-lab
virtio0: local-lvm:vm-901-disk-0,aio=io_uring,backup=0,cache=none,discard=on,iothread=1,replicate=1,size=30G

== Is libvirt involved? (Proxmox doesn't use it)
inactive
inactive
no virsh on this host

== The QEMU command Proxmox generates from that file (qm showcmd)
/usr/bin/kvm \
  -id 901 \
  -name lab-kvm \
  -chardev 'socket,id=qmp,path=/var/run/qemu-server/901.qmp,server=on,wait=off' \
  -mon 'chardev=qmp,mode=control' \
  -chardev 'socket,id=qmp-event,path=/var/run/qmeventd.sock,reconnect-ms=5000' \
  -mon 'chardev=qmp-event,mode=control' \
  -smp '4,sockets=1,cores=4,maxcpus=4' \
  -cpu host,+kvm_pv_eoi,+kvm_pv_unhalt \
  -m 6144 \
  ...
  -netdev 'type=tap,id=net0,ifname=tap901i0,script=/usr/libexec/qemu-server/pve-bridge,...' \
  -machine 'hpet=off,type=pc+pve0'

== The running process: Proxmox's QEMU binary is called 'kvm', and it runs as root
USER         PID %CPU   RSS COMMAND
root       20073 38.1 4928304 kvm
  20131 CPU 0/KVM
  20132 CPU 1/KVM
  20133 CPU 2/KVM
  20134 CPU 3/KVM
```

## What to notice

- **Config format:** `/etc/pve/qemu-server/901.conf` is flat `key: value` lines, not XML. `/etc/pve`
  is **pmxcfs**, a small cluster filesystem that Proxmox replicates to every node through corosync.
  It's Proxmox's equivalent of oVirt Engine's database.
- **`ide2: ...cloudinit`** is a NoCloud seed disk like the one labs 03 and 04 built with
  `make-seed.sh`. Proxmox generated it from `ciuser`, `ipconfig0` and `sshkeys`, and that's how
  this VM got its IP address and your SSH key.
- **`qm showcmd`** prints the full QEMU command Proxmox builds from the config file. Compare it
  with what libvirt generated in lab 04: different authors, same building blocks. Proxmox also
  pins a machine type (`pc+pve0`) and wires up QMP through a socket, here two of them: one for
  `qm` and one for `qmeventd`, which reacts to QEMU events such as a guest shutting down.
- **The binary is called `kvm`:** Proxmox ships its own QEMU build (`pve-qemu-kvm`), and
  `/usr/bin/kvm` is a symlink to its `qemu-system-x86_64`.
- **QEMU runs as root.** Lab 04's libvirt ran QEMU as the `qemu` user with a per-VM SELinux label
  and a seccomp sandbox. Here the process is `root`, its security label is `unconfined`, and
  `/proc/<pid>/status` shows `Seccomp: 0`. Proxmox isolates VMs with systemd cgroups
  (`/qemu.slice/901.scope`) for resource limits, but a QEMU escape lands as root on the host.
  That's one of the trade-offs of skipping libvirt.
- **The same threads as lab 03:** one `CPU n/KVM` thread per vCPU. Your `lab-kvm` VM is that
  process, and the guests you started in labs 03-04 were processes inside it.
- **`cpu: host`** in the config becomes `-cpu host,...` on the command line. It's what made labs
  01-04 possible inside this VM.
- **`qm monitor`** gives you QEMU's human monitor for the VM, the text cousin of QMP.

## Questions

1. Proxmox clusters have no central management server. Where does a cluster-wide decision
   like "start VM 901 on node B" get made, and what stops two nodes from starting it at once?
2. Proxmox skipped libvirt. What does it gain, and what does it give up?

**Next:** [Lab 06: VDSM](../06-vdsm/)
