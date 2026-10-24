# The lab VMs. Each one is a hypervisor in its own right, so every VM gets
# cpu type "host": that passes VT-x/AMD-V through and lets KVM run *inside* it
# (nested virtualization).

locals {
  all_vms = {
    kvm = {
      enabled = var.labs.kvm
      id      = var.vm_id_base + 1
      image   = "fedora"
      cores   = 4
      memory  = 6144
      disk    = 30
      groups  = ["kvm_hosts"]
      purpose = "Labs 01-04: KVM, the raw KVM API, QEMU and libvirt"
    }
    vdsm = {
      enabled = var.labs.vdsm || var.labs.ovirt_engine # the engine needs a host to manage
      id      = var.vm_id_base + 2
      image   = "centos"
      cores   = 4
      memory  = 6144
      disk    = 40
      groups  = ["vdsm_hosts"]
      purpose = "Lab 06: VDSM, oVirt's host agent, driven directly"
    }
    kubevirt = {
      enabled = var.labs.kubevirt
      id      = var.vm_id_base + 3
      image   = "centos"
      cores   = 4
      memory  = 8192
      disk    = 40
      groups  = ["kubevirt_hosts"]
      purpose = "Lab 07: k3s + KubeVirt"
    }
    ovirt_engine = {
      enabled = var.labs.ovirt_engine
      id      = var.vm_id_base + 4
      image   = "centos"
      cores   = 4
      memory  = 8192
      disk    = 40
      groups  = ["ovirt_engines"]
      purpose = "Lab 08: oVirt Engine (management for the vdsm VM)"
    }
  }

  vms = { for name, vm in local.all_vms : name => vm if vm.enabled }
}

resource "proxmox_virtual_environment_vm" "lab" {
  for_each = local.vms

  name        = "lab-${replace(each.key, "_", "-")}"
  description = "kvm-lab: ${each.value.purpose}"
  tags        = ["kvm-lab"]
  node_name   = var.pve_node
  vm_id       = each.value.id

  on_boot         = false # lab VMs shouldn't start with the node
  stop_on_destroy = true

  # The cloud images ship qemu-guest-agent; Terraform uses it to learn the VM's IP.
  agent {
    enabled = true
  }

  cpu {
    type  = "host" # required for nested KVM
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.vm_datastore
    import_from  = proxmox_download_file.image[each.value.image].id
    interface    = "virtio0"
    size         = each.value.disk
    discard      = "on"
    iothread     = true
    backup       = false # keep throwaway lab disks out of scheduled vzdump jobs
  }

  network_device {
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  operating_system {
    type = "l26"
  }

  # Serial console: `qm terminal <vmid>` on the PVE host works even if networking doesn't.
  serial_device {}

  initialization {
    datastore_id = var.vm_datastore

    ip_config {
      ipv4 {
        address = lookup(var.ipv4, each.key, "dhcp")
        gateway = lookup(var.ipv4, each.key, "dhcp") == "dhcp" ? null : var.ipv4_gateway
      }
    }

    dynamic "dns" {
      for_each = length(var.dns_servers) > 0 ? [1] : []
      content {
        servers = var.dns_servers
      }
    }

    user_account {
      username = "lab"
      keys     = var.ssh_public_keys
    }
  }
}
