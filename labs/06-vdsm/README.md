# Lab 06: VDSM, oVirt's host agent

**Runs on:** `lab-vdsm` (enable `vdsm = true` in `terraform.tfvars`, then `make lab`;
`make ssh VM=vdsm`) · **Time:** 30 min

## Why this layer exists

libvirt manages one host. **oVirt** manages a data center: many hosts, shared storage, VM
migration, high availability. It splits that work in two:

- **oVirt Engine** (lab 08): the central brain, a Java application with a PostgreSQL database.
  It decides *what* should happen.
- **VDSM** (Virtual Desktop and Server Manager), on every host: a Python daemon that makes it
  happen locally. It's built on lab 04's libvirt Python bindings.

VDSM does a lot that libvirt doesn't:

- **storage domains**: shared storage (NFS, iSCSI, FC) with oVirt's own on-disk layout, and
  **sanlock** leases so two hosts never write the same disk
- **host networking**: bridges, bonds and VLANs, configured through NetworkManager by `supervdsmd`
- **monitoring**: CPU, memory and VM stats, polled by the engine every few seconds
- **a JSON-RPC API** on TCP 54321, over TLS with certificates the engine issues

In this lab VDSM runs **without an engine**. You call its API directly with `vdsm-client`, which
is exactly what the engine does over the network. The engine normally issues VDSM's TLS
certificates; without one, the lab turns TLS off (`/etc/vdsm/vdsm.conf.d/50-kvm-lab.conf`).
That's fine on a lab VM, never in production.

## Do it

```bash
cd ~/labs/06-vdsm
./explore.sh
vdsm-client --insecure Host getCapabilities | less    # everything the engine learns about a host
vdsm-client --insecure Host getStats
```

`--insecure` means plain TCP instead of TLS, matching the lab's `ssl = false`. An engine would
connect with TLS and its own certificates.

`explore.sh`, trimmed:

```
== The services that make up an oVirt host
  libvirtd.service     loaded active running libvirt legacy monolithic daemon
  mom-vdsm.service     loaded active running MOM instance configured for VDSM purposes
  sanlock.service      loaded active running Shared Storage Lease Manager
  supervdsmd.service   loaded active running Auxiliary vdsm service for running helper functions as root
  vdsmd.service        loaded active running Virtual Desktop Server Manager

== VDSM runs as user 'vdsm'; supervdsmd runs as root and does the privileged work for it
USER         PID COMMAND
root       69578 /usr/bin/python3 /usr/libexec/vdsm/supervdsmd --sockfile /run/vdsm/svdsm.sock
vdsm       69912 /usr/bin/python3 /usr/libexec/vdsm/vdsmd

== VDSM's JSON-RPC API on port 54321: this is what oVirt Engine talks to
LISTEN 0      5                  *:54321            *:*    users:(("vdsmd",pid=69912,fd=22))

== Host capabilities as VDSM reports them to the engine (8 of 71 fields)
{
  "cpuModel": "Intel(R) Xeon(R) Silver 4310 CPU @ 2.10GHz",
  "cpuCores": "4",
  "memSize": "5662",
  "kvmEnabled": "true",
  "vdsm": "4.50.6.1",
  "libvirt": "11.10.0",
  "qemu": "10.1.0"
}

== vdsm-tool configure rewrote libvirt's config: look for the 'by vdsm' sections
/etc/libvirt/libvirtd.conf
/etc/libvirt/qemu-sanlock.conf
/etc/libvirt/qemu.conf
## beginning of configuration section by vdsm-4.40.0
auth_tcp="none"
auth_unix_rw="sasl"
...

== libvirt now requires authentication; only read-only virsh works without credentials
Plain virsh, even as root:
error: authentication failed: Failed to start SASL negotiation: ...
```

## What to notice

- **Five services make an oVirt host:** `vdsmd`, `supervdsmd`, `libvirtd`, `sanlock` (storage
  leases) and `mom-vdsm`, the Memory Overcommitment Manager, which balloons and shares memory
  between VMs on the engine's behalf. Note that VDSM uses libvirt's **monolithic** `libvirtd`, not
  the modular `virtqemud` and friends from lab 04.
- **Two daemons, two privilege levels:** `vdsmd` runs as the unprivileged `vdsm` user, and
  `supervdsmd` runs as root and does the privileged operations for it (networking, storage
  mounts) over a local socket. That privilege split is a common pattern in host agents.
- **VDSM took over libvirt:** `vdsm-tool configure` rewrote three libvirt config files (look for
  the "by vdsm" sections) and set `auth_unix_rw="sasl"`. Now even `root` gets a SASL login prompt
  from plain `virsh`; only `virsh -r` (read-only) works. On an oVirt host, only VDSM is supposed
  to change libvirt.
- **`getCapabilities`** is a big JSON document, 71 top-level fields here: CPU flags, NUMA
  topology, NICs, storage, package versions. The engine uses it to decide which hosts can run which
  VMs and where a VM can migrate. Compare `cpuCores` and `memSize` with what Terraform gave this VM.

## Questions

1. Why does VDSM need sanlock when libvirt and QEMU already work fine without it?
2. The engine is down. What happens to VMs that are already running on VDSM hosts?

**Next:** [Lab 07: KubeVirt](../07-kubevirt/) · [Lab 08: full oVirt](../08-ovirt-engine/)
