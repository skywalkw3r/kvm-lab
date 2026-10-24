# The API token is read from the environment, never from a file in this repo:
#   export PROXMOX_VE_API_TOKEN='kvmlab@pve!terraform=<secret>'
# labs/00-setup in the README shows how to create it.
provider "proxmox" {
  endpoint = var.pve_endpoint
  insecure = var.pve_insecure_tls
}
