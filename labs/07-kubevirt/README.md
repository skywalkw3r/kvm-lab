# Lab 07: KubeVirt, VMs as Kubernetes pods

**Runs on:** `lab-kubevirt` (enable `kubevirt = true`, then `make lab`; `make ssh VM=kubevirt`)
· **Time:** 30 min

## Why this layer exists

KubeVirt puts VMs on Kubernetes, so a VM is scheduled, networked and stored like any other
workload. It keeps lab 04's libvirt + QEMU underneath, but the "central brain" becomes the
Kubernetes control plane:

| oVirt | KubeVirt |
|---|---|
| oVirt Engine + PostgreSQL | Kubernetes API server + etcd, plus `virt-controller` |
| VDSM on each host | `virt-handler` (a DaemonSet: one pod per node) |
| one libvirt per host, many VMs | **one libvirt per VM**, inside that VM's `virt-launcher` pod |
| storage domains | PersistentVolumeClaims, container images (`containerDisk`) |

## Do it

```bash
cd ~/labs/07-kubevirt
./explore.sh                 # creates the VM, then looks inside its pod
virtctl console lab-cirros   # cirros / gocubsgo, Ctrl-] to leave
kubectl delete -f cirros-vm.yaml
```

`explore.sh` with KubeVirt v1.9.1 on k3s v1.36.5, trimmed:

```
== Create the VM and wait for it to boot
virtualmachine.kubevirt.io/lab-cirros created
virtualmachineinstance.kubevirt.io/lab-cirros condition met
NAME                                            AGE   PHASE     IP           NODENAME       READY
virtualmachineinstance.kubevirt.io/lab-cirros   6s    Running   10.42.0.17   lab-kubevirt   True

== Every running VM is a pod: virt-launcher-<vm>-<id>
NAME                             READY   STATUS    RESTARTS   AGE   IP           NODE
virt-launcher-lab-cirros-fbqqf   2/2     Running   0          6s    10.42.0.17   lab-kubevirt

== Inside the pod's 'compute' container: a private libvirt daemon and QEMU
    PID USER     COMMAND
      1 qemu     virt-launcher-m
     14 qemu     virt-launcher
     22 qemu     virtqemud
     23 qemu     virtlogd
     87 qemu     qemu-kvm

== That libvirt has exactly one domain: this VM
 Id   Name                 State
------------------------------------
 1    default_lab-cirros   running

== The domain XML that virt-launcher generated from the VirtualMachine spec (first 30 lines)
<domain type='kvm' id='1'>
  <name>default_lab-cirros</name>
  <metadata>
    <kubevirt xmlns="http://kubevirt.io">
  ...
    <type arch='x86_64' machine='pc-q35-rhel9.8.0'>hvm</type>
  ...
  <cpu mode='custom' match='exact' check='full'>

== From the node's point of view, QEMU is an ordinary process in the pod's cgroup
77317 /usr/libexec/qemu-kvm -name guest=default_lab-cirros,debug-threads=on -S ...
kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod....slice/cri-containerd-....scope
```

## What to notice

- **`VirtualMachine` → `VirtualMachineInstance` → pod.** The VM object is what you declare, the
  VMI is the running instance, and the `virt-launcher-lab-cirros-*` pod is where it actually runs.
  From `kubectl apply` to a running guest took about 6 seconds here.
- **libvirt in a box:** the pod's `compute` container runs a whole lab 04 stack for one VM:
  `virtqemud`, `virtlogd` and `qemu-kvm`, supervised by `virt-launcher` (the job VDSM does on an
  oVirt host). PID 1 (`virt-launcher-m`, truncated) is `virt-launcher-monitor`, which starts
  `virt-launcher` and supervises it; its `--qemu-timeout` flag hints at its job of waiting on QEMU.
  The libvirt domain is named `<namespace>_<vm>`.
- **Nothing in the pod runs as root.** Every process, QEMU included, runs as `qemu`. Compare lab 05,
  where Proxmox runs QEMU as root.
- **The command line looks familiar:** `-name guest=...,debug-threads=on -S` is the same
  libvirt-generated pattern as lab 04. The QEMU build is different, though: `/usr/libexec/qemu-kvm`
  with a `pc-q35-rhel9.8.0` machine type comes from the RHEL-based `virt-launcher` image, not
  from the node's OS. Upgrading KubeVirt upgrades QEMU.
- **CPU model:** the VM didn't specify one, so KubeVirt used `host-model` (`kubectl get vmi
  lab-cirros -o jsonpath='{.spec.domain.cpu}'`). libvirt expanded that into an explicit
  `mode='custom'` CPU definition: close to the host's, but stable enough to migrate between nodes.
  Lab 03 used `-cpu host`, which isn't.
- **QEMU is still just a process** on the node, but inside the pod's cgroup
  (`kubepods-burstable...`). Kubernetes enforces its CPU and memory limits like any container's.
- **The disk is a container image:** `containerDisk` pulls `cirros-container-disk-demo` from a
  registry. VM images ship the same way as app images.

## Questions

1. With one libvirt per VM instead of one per host, what's easier and what's harder?
   (Think upgrades, failure isolation, and per-VM overhead.)
2. Live migration means moving the VM to a new `virt-launcher` pod on another node. Which
   component copies the memory?

**Next:** [Lab 08: full oVirt](../08-ovirt-engine/), or the [big picture](../../docs/layers.md)
