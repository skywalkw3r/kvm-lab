#!/bin/bash
# Builds a cloud-init "NoCloud" seed: a tiny ISO with the volume label "cidata"
# holding meta-data and user-data files.
#   make-seed.sh <output.iso> <hostname>
#
# Guests that run cloud-init (CirrOS has a small version of it) look for a disk
# with that label at boot. Without one, CirrOS spends minutes polling for an EC2
# metadata server that doesn't exist. Proxmox gives every cloud-init VM the same
# kind of disk: look for "ide2: ...cloudinit" in a lab VM's config.
set -euo pipefail
OUT=${1:?usage: make-seed.sh <output.iso> <hostname>}
NAME=${2:?usage: make-seed.sh <output.iso> <hostname>}

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

# Written as JSON: CirrOS's small cloud-init only parses JSON, and JSON is valid YAML,
# so real cloud-init reads it too.
cat > "$dir/meta-data" <<EOF
{"instance-id": "$NAME", "local-hostname": "$NAME"}
EOF

cat > "$dir/user-data" <<'EOF'
#!/bin/sh
echo "Hello from cloud-init user-data"
EOF

xorriso -as mkisofs -quiet -output "$OUT" -volid cidata -joliet -rock "$dir" 2>/dev/null ||
  { echo "make-seed.sh: xorriso failed (is it installed?)" >&2; exit 1; }
