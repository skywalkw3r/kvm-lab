#!/bin/bash
# Lab 07: a VM as a Kubernetes pod. Run inside lab-kubevirt.
set -euo pipefail
cd "$(dirname "$0")"

section() { printf '\n== %s\n' "$*"; }

section "KubeVirt's own components (control plane + one virt-handler per node)"
kubectl -n kubevirt get pods

section "Create the VM and wait for it to boot"
kubectl apply -f cirros-vm.yaml
kubectl wait vmi lab-cirros --for=condition=Ready --timeout=300s
kubectl get vm,vmi

section "Every running VM is a pod: virt-launcher-<vm>-<id>"
POD=$(kubectl get pod -l kubevirt.io/vm=lab-cirros -o jsonpath='{.items[0].metadata.name}')
kubectl get pod "$POD" -o wide

section "Inside the pod's 'compute' container: a private libvirt daemon and QEMU"
kubectl exec "$POD" -c compute -- ps -eo pid,user,comm

section "That libvirt has exactly one domain: this VM"
kubectl exec "$POD" -c compute -- virsh list --all

section "The domain XML that virt-launcher generated from the VirtualMachine spec (first 30 lines)"
kubectl exec "$POD" -c compute -- virsh dumpxml 1 | sed -n '1,30p'

section "From the node's point of view, QEMU is an ordinary process in the pod's cgroup"
pgrep -a qemu-kvm | cut -c1-200
QPID=$(pgrep -f qemu-kvm | sed -n '1,1p')
grep -o 'kubepods[^ ]*' /proc/"$QPID"/cgroup | sed -n '1,1p'

echo
echo "Console: virtctl console lab-cirros (cirros / gocubsgo, Ctrl-] to leave)"
echo "Cleanup: kubectl delete -f cirros-vm.yaml"
