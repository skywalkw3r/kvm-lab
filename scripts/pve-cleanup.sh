#!/bin/bash
# Run ON THE PROXMOX HOST as root, after `make down`. Undoes scripts/pve-setup.sh.
#   bash pve-cleanup.sh             dry run: show what would be removed
#   bash pve-cleanup.sh --yes       remove it
#
# Removes, in order:
#   1. leftover kvmlab-* images on the image storage (normally `make down` already did this)
#   2. the kvmlab@pve!terraform token, the kvmlab@pve user (and its ACLs), the KvmLab roles
#   3. the "import" content type, only if pve-setup.sh added it (see /var/lib/kvm-lab/setup.env)
#   4. /var/lib/kvm-lab
# It refuses to run while VMs tagged kvm-lab still exist: Terraform owns those.
#
# Options:
#   --remove-import   remove the "import" content type even without a record that
#                     pve-setup.sh added it (e.g. it was set up by an older version)
#   --storage NAME    the image storage, if setup.env is missing (default: local)
set -euo pipefail

ROLES=(KvmLab KvmLabImages)
USER=kvmlab@pve
TOKEN=terraform
STATE=/var/lib/kvm-lab/setup.env

apply=no remove_import=no storage_arg=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --yes) apply=yes ;;
    --remove-import) remove_import=yes ;;
    --storage) storage_arg=${2:?--storage needs a name}; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

command -v pveum >/dev/null || { echo "run this on the Proxmox host" >&2; exit 1; }

STORAGE='' ORIGINAL_CONTENT='' IMPORT_ADDED=''
# shellcheck source=/dev/null
[[ -f $STATE ]] && . "$STATE"
STORAGE=${storage_arg:-${STORAGE:-local}}
NODE=$(hostname)

run() {
  if [[ $apply == yes ]]; then echo "+ $*"; "$@"; else echo "  would run: $*"; fi
}
json() { python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

[[ $apply == yes ]] || echo "Dry run. Nothing is changed; re-run with --yes to apply."
echo

# ---- 0. Lab VMs must be gone first ------------------------------------------------------
vms=$(pvesh get /cluster/resources --type vm --output-format json |
  json 'print("\n".join("  %s %s" % (v["vmid"], v.get("name", "")) for v in d if "kvm-lab" in (v.get("tags") or "").split(";")))')
if [[ -n $vms ]]; then
  echo "These kvm-lab VMs still exist:"
  echo "$vms"
  echo "Run 'make down' in the repo first. (If its Terraform state is lost: qm stop <id>; qm destroy <id>.)"
  exit 1
fi
echo "VMs: no kvm-lab VMs left"

# ---- 1. Leftover images -----------------------------------------------------------------
images=$(pvesh get /nodes/"$NODE"/storage/"$STORAGE"/content --output-format json |
  json 'print("\n".join(v["volid"] for v in d if "/kvmlab-" in v["volid"]))')
if [[ -n $images ]]; then
  echo "Images on $STORAGE:"
  while read -r volid; do run pvesm free "$volid"; done <<< "$images"
else
  echo "Images: no kvmlab-* images on $STORAGE"
fi

# ---- 2. Token, user, roles --------------------------------------------------------------
if pveum user list --output-format json | grep -q "\"userid\":\"$USER\""; then
  echo "User $USER:"
  if pveum user token list "$USER" --output-format json | grep -q "\"tokenid\":\"$TOKEN\""; then
    run pveum user token remove "$USER" "$TOKEN"
  fi
  run pveum user delete "$USER" # also removes the user's ACL entries
else
  echo "User: $USER doesn't exist"
fi

for role in "${ROLES[@]}"; do
  if pveum role list --output-format json | grep -q "\"roleid\":\"$role\""; then
    echo "Role $role:"
    run pveum role delete "$role"
  fi
done

# ---- 3. "import" content type -----------------------------------------------------------
content=$(pvesh get /storage/"$STORAGE" --output-format json | json 'print(d.get("content", ""))')
if [[ ,$content, != *,import,* ]]; then
  echo "Storage $STORAGE: no import content type to remove"
else
  target=
  if [[ $IMPORT_ADDED == yes && -n $ORIGINAL_CONTENT ]]; then
    target=$ORIGINAL_CONTENT
  elif [[ $remove_import == yes ]]; then
    target=$(tr ',' '\n' <<< "$content" | grep -vx import | paste -sd, -)
  else
    echo "Storage $STORAGE: keeping the import content type (no record that pve-setup.sh added it)."
    echo "  To remove it anyway: bash pve-cleanup.sh --remove-import --yes"
  fi

  if [[ -n $target ]]; then
    others=$(pvesh get /nodes/"$NODE"/storage/"$STORAGE"/content --content import --output-format json |
      json 'print("\n".join("  " + v["volid"] for v in d if "/kvmlab-" not in v["volid"]))')
    if [[ -n $others ]]; then
      echo "Storage $STORAGE: keeping the import content type, other import images use it:"
      echo "$others"
    else
      echo "Storage $STORAGE: restore content types $content -> $target"
      run pvesm set "$STORAGE" --content "$target"
    fi
  fi
fi

# ---- 4. Setup record --------------------------------------------------------------------
if [[ -d $(dirname "$STATE") ]]; then
  echo "Setup record:"
  run rm -rf "$(dirname "$STATE")"
fi

echo
[[ $apply == yes ]] && echo "Done. The repo's .env token no longer works; delete that line too." ||
  echo "Dry run complete. Re-run with --yes to apply."
