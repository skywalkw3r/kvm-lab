# Cloud images, downloaded once by the Proxmox node itself.
# Pinned to exact builds + checksums so everyone following the labs gets the same OS.
# They're stored with the "import" content type, so VM disks can be created from them
# through the API alone (no root SSH to the node). scripts/pve-setup.sh enables it.

locals {
  images = {
    fedora = {
      url       = "https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2"
      file_name = "kvmlab-fedora-44-1.7.x86_64.qcow2"
      checksum  = "28680fe5b371a5a82ebf43a31926e086a168e59949d03969c5093e7071f90b7f"
    }
    # oVirt/VDSM target Enterprise Linux 9.
    centos = {
      url       = "https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-20260930.0.x86_64.qcow2"
      file_name = "kvmlab-centos-stream-9-20260930.0.x86_64.qcow2"
      checksum  = "a7f804379970e055d5d5ff408787f0d984b4d640e261473ff58d83561bd19433"
    }
  }

  # Only download images that an enabled VM actually uses.
  images_needed = toset([for vm in values(local.vms) : vm.image])
}

resource "proxmox_download_file" "image" {
  for_each = local.images_needed

  node_name          = var.pve_node
  datastore_id       = var.image_datastore
  content_type       = "import"
  url                = local.images[each.key].url
  file_name          = local.images[each.key].file_name
  checksum           = local.images[each.key].checksum
  checksum_algorithm = "sha256"
  overwrite          = false
}
