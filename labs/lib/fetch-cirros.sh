#!/bin/bash
# Downloads the CirrOS test image (~20 MB, boots in seconds) to ~/images.
# Prints the image path. Used by labs 03 and 04.
set -euo pipefail
VER=0.6.3
ARCH=$(uname -m)
declare -A MD5=(  # from the release's MD5SUMS file
  [x86_64]=87617e24a5e30cb3b87fda8c0764838f
  [aarch64]=28009b5399ef386f7720258de40d43cf
)
IMG=~/images/cirros-$VER-$ARCH.qcow2
mkdir -p ~/images
if [[ ! -f $IMG ]]; then
  curl -fsSL -o "$IMG.part" \
    "https://github.com/cirros-dev/cirros/releases/download/$VER/cirros-$VER-$ARCH-disk.img"
  echo "${MD5[$ARCH]}  $IMG.part" | md5sum -c --quiet >&2
  mv "$IMG.part" "$IMG"
fi
echo "$IMG"
