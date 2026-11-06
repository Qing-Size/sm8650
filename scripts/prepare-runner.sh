#!/usr/bin/env bash
set -euo pipefail

# This script deletes preinstalled software on a disposable GitHub VM only.
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "${RUNNER_OS:-}" != Linux ]]; then
  echo 'Refusing storage preparation outside a GitHub-hosted Linux runner.' >&2
  exit 1
fi

# Disk knobs (see README "资源旋钮"):
#   YARP_SWAP_GIB     swap file size in GiB (default 8; the file lives on the
#                     build disk, so smaller swap = more space for sources)
#   YARP_MIN_FREE_GIB free disk required after swap allocation (default 25)
swap_gib="${YARP_SWAP_GIB:-8}"
min_free_gib="${YARP_MIN_FREE_GIB:-25}"

df -h / /mnt
free -h
sudo swapoff -a
sudo rm -f /mnt/swapfile /swapfile
sudo docker image prune --all --force
sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc \
  /usr/local/.ghcup /usr/local/swift /opt/hostedtoolcache
sudo apt-get clean

# Keep the existing filesystem: no loop images consuming the runner's root disk.
sudo fallocate -l "${swap_gib}G" /yarp-swapfile
sudo chmod 600 /yarp-swapfile
sudo mkswap /yarp-swapfile
sudo swapon /yarp-swapfile
sudo mkdir -p /build/yarp
sudo chown "$(id -u):$(id -g)" /build/yarp
df -h / /build/yarp
free -h
swapon --show

# Disk-usage report to help tune the knobs above.
sudo du -xh --max-depth=1 / 2>/dev/null | sort -h | tail -n 12 || true

available_kib="$(df -Pk /build/yarp | awk 'NR == 2 {print $4}')"
if (( available_kib < min_free_gib * 1024 * 1024 )); then
  echo "::error::Only $((available_kib / 1024 / 1024)) GiB is free after swap allocation; this build wants at least ${min_free_gib} GiB. Reduce YARP_SWAP_GIB, free more disk, or run on a larger runner (override the threshold with YARP_MIN_FREE_GIB)."
  exit 1
fi
