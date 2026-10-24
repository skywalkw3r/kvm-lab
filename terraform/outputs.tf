locals {
  # Static address if one is configured; otherwise ask the guest agent, which
  # reports addresses per interface (lo, eth0, ...): take the first non-loopback IPv4.
  vm_ips = {
    for name, vm in proxmox_virtual_environment_vm.lab : name => (
      lookup(var.ipv4, name, "dhcp") != "dhcp" ? split("/", var.ipv4[name])[0] : try(
        [for ip in flatten(vm.ipv4_addresses) : ip if !startswith(ip, "127.")][0],
        null
      )
    )
  }
}

output "vms" {
  description = "Lab VMs: ID, name and IP."
  value = {
    for name, vm in proxmox_virtual_environment_vm.lab : name => {
      vm_id = vm.vm_id
      name  = vm.name
      ip    = local.vm_ips[name]
    }
  }
}

# Ansible inventory, regenerated on every apply (git-ignored).
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory.yml"
  file_permission = "0644"
  content = templatefile("${path.module}/inventory.yml.tftpl", {
    vms    = local.vms
    ips    = local.vm_ips
    names  = { for name, vm in proxmox_virtual_environment_vm.lab : name => vm.name }
    vm_ids = { for name, vm in proxmox_virtual_environment_vm.lab : name => vm.vm_id }
  })
}
