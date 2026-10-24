# ---- Where your Proxmox is ----------------------------------------------------

variable "pve_endpoint" {
  description = "Proxmox API URL, e.g. https://pve.example.com:8006/"
  type        = string
}

variable "pve_insecure_tls" {
  description = "Skip TLS verification (only for a self-signed lab node)."
  type        = bool
  default     = false
}

variable "pve_node" {
  description = "Name of the Proxmox node to create the VMs on (as shown in the web UI tree)."
  type        = string
}

variable "image_datastore" {
  description = "Storage for downloaded cloud images. Must allow the 'import' content type (scripts/pve-setup.sh)."
  type        = string
  default     = "local"
}

variable "vm_datastore" {
  description = "Storage for VM disks, e.g. local-lvm or local-zfs."
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Network bridge the lab VMs attach to."
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "VLAN tag on that bridge (null = untagged)."
  type        = number
  default     = null
}

# ---- Which lab VMs to create ---------------------------------------------------
# Turn on only what you're working on: each VM reserves its RAM while it runs.

variable "labs" {
  description = "Which lab VMs to create."
  type = object({
    kvm          = optional(bool, true)  # labs 01-04: KVM, raw KVM API, QEMU, libvirt
    vdsm         = optional(bool, false) # lab 06: VDSM without an engine
    kubevirt     = optional(bool, false) # lab 07: k3s + KubeVirt
    ovirt_engine = optional(bool, false) # lab 08: full oVirt (engine + the vdsm VM as its host)
  })
  default = {}
}

variable "vm_id_base" {
  description = "Lab VMs get IDs vm_id_base+1 .. +4. Pick a range nothing else uses."
  type        = number
  default     = 900
}

# ---- Access -------------------------------------------------------------------

variable "ssh_public_keys" {
  description = "SSH public keys allowed to log in as the 'lab' user on every VM."
  type        = list(string)
}

variable "ipv4" {
  description = <<-EOT
    Per-VM IPv4 config: "dhcp" (default) or a CIDR like "192.168.10.51/24".
    Keys: kvm, vdsm, kubevirt, ovirt_engine.
  EOT
  type        = map(string)
  default     = {}
}

variable "ipv4_gateway" {
  description = "Gateway for static addresses (ignored for DHCP)."
  type        = string
  default     = null
}

variable "dns_servers" {
  description = "DNS servers for static addresses (empty = inherit from the PVE host)."
  type        = list(string)
  default     = []
}
