#!/bin/bash
# Run ON THE PROXMOX HOST as root. Safe to re-run.
#   bash pve-setup.sh [image-storage]      (default: local)
#
# 1. Lets the image storage hold "import" images, so Terraform can create VM disks
#    from cloud images through the API (no root SSH to the node needed).
# 2. Creates a least-privilege user + API token for Terraform:
#      role  KvmLab        only what's needed to download images and manage VMs
#      role  KvmLabImages  delete downloaded images, granted on the image storage only
#      user  kvmlab@pve    no password, can't log in to the web UI
#      token kvmlab@pve!terraform
#    The secret is printed once. Put it in the repo's .env file (see .env.example).
#
# What it changed is recorded in /var/lib/kvm-lab/setup.env, so scripts/pve-cleanup.sh
# can undo exactly that and nothing more.
set -euo pipefail

STORAGE=${1:-local}
ROLE=KvmLab
USER=kvmlab@pve
TOKEN=terraform
STATE=/var/lib/kvm-lab/setup.env

PRIVS=(
  # download cloud images onto a storage, and import them as VM disks
  Datastore.Audit Datastore.AllocateSpace Datastore.AllocateTemplate Sys.Audit Sys.Modify Sys.AccessNetwork
  # create, configure, start/stop and delete VMs
  VM.Allocate VM.Audit VM.PowerMgmt VM.Console
  VM.Config.CPU VM.Config.Memory VM.Config.Disk VM.Config.Network VM.Config.Options
  VM.Config.HWType VM.Config.Cloudinit VM.Config.CDROM
  # read the VM's IP address from the guest agent
  VM.GuestAgent.Audit
  # attach VMs to a bridge
  SDN.Use SDN.Audit
)

command -v pveum >/dev/null || { echo "run this on the Proxmox host" >&2; exit 1; }

# Record the storage's content types before the first change, for pve-cleanup.sh.
content=$(pvesh get /storage/"$STORAGE" --output-format json |
  python3 -c 'import json,sys; print(json.load(sys.stdin).get("content", ""))')
mkdir -p "$(dirname "$STATE")"
if [[ ! -f $STATE ]]; then
  if [[ ,$content, == *,import,* ]]; then import_added=no; else import_added=yes; fi
  cat > "$STATE" <<EOF
# Written by kvm-lab pve-setup.sh on $(date -Is). Read by pve-cleanup.sh.
STORAGE=$STORAGE
ORIGINAL_CONTENT=$content
IMPORT_ADDED=$import_added
EOF
fi

# ---- 1. "import" content on the image storage --------------------------------------
if [[ ,$content, == *,import,* ]]; then
  echo "storage $STORAGE: import content already enabled"
else
  pvesm set "$STORAGE" --content "$content,import"
  echo "storage $STORAGE: content is now $content,import"
fi

# ---- 2. Role, user, token -----------------------------------------------------------
if pveum role list --output-format json | grep -q "\"roleid\":\"$ROLE\""; then
  pveum role modify "$ROLE" -privs "${PRIVS[*]}"
else
  pveum role add "$ROLE" -privs "${PRIVS[*]}"
fi
echo "role $ROLE: ${#PRIVS[@]} privileges"

# Deleting a downloaded image (terraform destroy) needs Datastore.Allocate. That privilege
# also allows editing storage settings, so it's granted on the image storage alone.
pveum role list --output-format json | grep -q "\"roleid\":\"${ROLE}Images\"" ||
  pveum role add "${ROLE}Images" -privs Datastore.Allocate

pveum user list --output-format json | grep -q "\"userid\":\"$USER\"" ||
  pveum user add "$USER" --comment "kvm-lab Terraform"
pveum acl modify / -user "$USER" -role "$ROLE"
# Careful: an ACL on a more specific path *replaces* what the user inherits from /
# there, it doesn't add to it. So the storage gets both roles.
pveum acl modify /storage/"$STORAGE" -user "$USER" -roles "$ROLE,${ROLE}Images"
echo "user $USER: $ROLE on /, $ROLE + ${ROLE}Images on /storage/$STORAGE"

if pveum user token list "$USER" --output-format json | grep -q "\"tokenid\":\"$TOKEN\""; then
  echo "token $USER!$TOKEN: already exists (your .env keeps working)."
  echo "  lost the secret? pveum user token remove $USER $TOKEN && bash pve-setup.sh"
  exit 0
fi

# privsep=0: the token has exactly the user's permissions.
SECRET=$(pveum user token add "$USER" "$TOKEN" --privsep 0 --output-format json |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["value"])')

cat <<EOF

Done. Put this line in the repo's .env file (it's git-ignored). It won't be shown again:

PROXMOX_VE_API_TOKEN=$USER!$TOKEN=$SECRET

EOF
